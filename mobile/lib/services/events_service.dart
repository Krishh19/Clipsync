import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/events_client.dart';
import '../core/models.dart';
import '../data/db.dart';
import '../data/secure_store.dart';
import 'notifications.dart';

typedef ClipboardSetter = Future<void> Function(String text);
typedef FileDownloader = Future<String?> Function(String fileId, String fileName);
typedef EventsClientFactory = EventsClient Function({
  required String host,
  required int port,
  required String fingerprint,
  required String secret,
  void Function(WsEvent event)? onEvent,
  void Function(Object error)? onError,
});

class EventsService {
  final SecureStore secureStore;
  final AppDatabase? database;
  final ApiClient? apiClient;
  final ClipboardSetter? clipboardSetter;
  final FileDownloader? fileDownloader;
  final EventsClientFactory? clientFactory;

  EventsClient? _client;
  bool _isRunning = false;
  bool _isWsConnected = false;
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();

  EventsService({
    required this.secureStore,
    this.database,
    this.apiClient,
    this.clipboardSetter,
    this.fileDownloader,
    this.clientFactory,
  });

  bool get isRunning => _isRunning;
  bool get isWsConnected => _isWsConnected;
  Stream<bool> get connectionStream => _connectionController.stream;
  EventsClient? get client => _client;

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    final host = await secureStore.getPcHost();
    final port = await secureStore.getPcPort();
    final fp = await secureStore.getPcFingerprint();
    final secret = await secureStore.getPcSecret();

    if (host == null || port == null || fp == null || secret == null) {
      _isRunning = false;
      return;
    }

    if (clientFactory != null) {
      _client = clientFactory!(
        host: host,
        port: port,
        fingerprint: fp,
        secret: secret,
        onEvent: handleEvent,
        onError: (err) {},
      );
    } else {
      _client = EventsClient(
        host: host,
        port: port,
        fingerprint: fp,
        secret: secret,
        onEvent: handleEvent,
        onError: (err) {},
        onConnectionChanged: (connected) {
          _isWsConnected = connected;
          if (!_connectionController.isClosed) {
            _connectionController.add(connected);
          }
        },
      );
    }
    _client?.connect();
  }

  /// Processes incoming WsEvent per docs/SPEC.md Section 7 & 10
  Future<void> handleEvent(WsEvent event) async {
    final senderName = await secureStore.getPcName() ?? 'PC';

    if (event.type == 'text') {
      final content = event.data['content'] as String? ?? '';
      final id = (event.data['id']?.toString() ?? const Uuid().v4()).hashCode;

      // Flag with loop prevention so phone never echoes this content back to PC
      LoopPrevention.markIncoming(content);

      // Record in SQLite history immediately so Recent Transfers shows it
      await insertHistoryItem(
        direction: 'in',
        kind: (content.startsWith('http://') || content.startsWith('https://'))
            ? 'link'
            : 'text',
        label: content,
        size: content.length,
        status: 'done',
      );

      // Dispatch notification with Copy action
      await NotificationsService.showTextReceived(
        id: id,
        senderName: senderName,
        text: content,
      );
    } else if (event.type == 'file_offer') {
      final fileId = event.data['id']?.toString() ?? '';
      final fileName = event.data['name'] as String? ?? 'File';
      final size = event.data['size'] as int?;
      final id = fileId.hashCode;

      // Dispatch notification with Download action
      await NotificationsService.showFileOffer(
        id: id,
        senderName: senderName,
        fileName: fileName,
        fileId: fileId,
        size: size,
      );

      // Auto-download offered file so it appears in Recent Transfers
      if (fileId.isNotEmpty) {
        unawaited(handleDownloadAction(fileId: fileId, fileName: fileName, size: size));
      }
    }
  }

  /// Handles user tapping an action on an incoming notification
  Future<void> handleNotificationAction({
    required String actionId,
    required String payload,
  }) async {
    if (actionId == 'copy_action') {
      await handleCopyAction(payload);
    } else if (actionId == 'download_action') {
      final parts = payload.split('|');
      final fileId = parts.first;
      final fileName = parts.length > 1 ? parts.sublist(1).join('|') : 'downloaded_file';
      await handleDownloadAction(fileId: fileId, fileName: fileName);
    }
  }

  /// Copies text to Android clipboard, flags loop prevention, and inserts into history
  Future<void> handleCopyAction(String content) async {
    // 1. Flag loop prevention
    LoopPrevention.markIncoming(content);

    // 2. Write to system clipboard
    if (clipboardSetter != null) {
      await clipboardSetter!(content);
    } else {
      await Clipboard.setData(ClipboardData(text: content));
    }

    // 3. Record in SQLite history
    await insertHistoryItem(
      direction: 'in',
      kind: (content.startsWith('http://') || content.startsWith('https://'))
          ? 'link'
          : 'text',
      label: content.length > 50 ? '${content.substring(0, 50)}...' : content,
      size: content.length,
      status: 'done',
    );
  }

  /// Downloads file from PC via GET /api/v1/files/:id and records in history
  Future<String?> handleDownloadAction({
    required String fileId,
    required String fileName,
    int? size,
  }) async {
    String? savedPath;

    if (fileDownloader != null) {
      savedPath = await fileDownloader!(fileId, fileName);
    } else {
      savedPath = await _downloadFileDirect(fileId: fileId, fileName: fileName);
    }

    // Record in SQLite history
    await insertHistoryItem(
      direction: 'in',
      kind: ApiClient.inferMimeType(fileName).startsWith('image/')
          ? 'image'
          : (ApiClient.inferMimeType(fileName).startsWith('video/')
              ? 'video'
              : 'file'),
      label: fileName,
      size: size ?? 0,
      status: savedPath != null ? 'done' : 'failed',
      filePath: savedPath,
    );

    return savedPath;
  }

  Future<String?> _downloadFileDirect({
    required String fileId,
    required String fileName,
  }) async {
    try {
      final host = await secureStore.getPcHost();
      final port = await secureStore.getPcPort();
      final fp = await secureStore.getPcFingerprint();
      final secret = await secureStore.getPcSecret();

      if (host == null || port == null || fp == null || secret == null) {
        return null;
      }

      final client = apiClient ??
          ApiClient.fromConfig(
            host: host,
            port: port,
            fingerprint: fp,
            deviceSecret: secret,
          );

      final saveDir = await getDownloadsFolder();
      final destinationPath = p.join(saveDir.path, fileName);

      await client.downloadFile(
        fileId: fileId,
        destinationPath: destinationPath,
      );

      return destinationPath;
    } catch (_) {
      return null;
    }
  }

  static Future<Directory> getDownloadsFolder() async {
    try {
      final dirs = await getExternalStorageDirectories(
        type: StorageDirectory.downloads,
      );
      if (dirs != null && dirs.isNotEmpty) {
        return dirs.first;
      }
    } catch (_) {}
    try {
      final dir = await getDownloadsDirectory();
      if (dir != null) return dir;
    } catch (_) {}
    return await getApplicationDocumentsDirectory();
  }

  Future<void> insertHistoryItem({
    required String direction,
    required String kind,
    required String label,
    required int size,
    required String status,
    String? filePath,
  }) async {
    if (database == null) return;
    try {
      await database!.into(database!.transfers).insert(
            TransfersCompanion.insert(
              id: const Uuid().v4(),
              direction: direction,
              kind: kind,
              label: label,
              filePath: Value(filePath),
              size: size,
              status: status,
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
            mode: InsertMode.insertOrReplace,
          );
    } catch (_) {}
  }

  void stop() {
    _isRunning = false;
    _isWsConnected = false;
    if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }
    _client?.dispose();
    _client = null;
  }
}
