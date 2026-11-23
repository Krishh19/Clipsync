import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../data/secure_store.dart';

class TransferService {
  static const int maxTextSizeBytes = 1024 * 1024; // 1 MB limit per SPEC
  static const int maxFileSizeBytes = 50 * 1024 * 1024; // 50 MB limit per SPEC

  final SecureStore secureStore;
  final ApiClient? customClient;
  final List<TransferItem> _queue = [];
  bool _isProcessing = false;

  final StreamController<List<TransferItem>> _queueController =
      StreamController<List<TransferItem>>.broadcast();

  Stream<List<TransferItem>> get queueStream => _queueController.stream;
  List<TransferItem> get queue => List.unmodifiable(_queue);

  TransferService({required this.secureStore, this.customClient});

  /// Enqueues text to send to PC.
  /// Validates <= 1 MB limit per SPEC before enqueueing.
  Future<TransferItem> sendText(String content, {String kind = 'text'}) async {
    final bytes = utf8.encode(content);
    if (bytes.length > maxTextSizeBytes) {
      throw ArgumentError(
        'Text size (${bytes.length} bytes) exceeds maximum limit of 1 MB',
      );
    }

    final item = TransferItem(
      id: const Uuid().v4(),
      direction: 'out',
      kind: kind,
      label: content.length > 50 ? '${content.substring(0, 50)}...' : content,
      content: content,
      size: bytes.length,
      status: 'queued',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _queue.insert(0, item);
    _queueController.add(_queue);

    _processNext();
    return item;
  }

  /// Enqueues file to stream to PC.
  /// Validates <= 50 MB limit per SPEC before enqueueing.
  Future<TransferItem> sendFile(File file, {String? fileName}) async {
    final length = await file.length();
    if (length > maxFileSizeBytes) {
      throw ArgumentError(
        'File size ($length bytes) exceeds maximum limit of 50 MB',
      );
    }

    final name = fileName ?? file.uri.pathSegments.last;
    final item = TransferItem(
      id: const Uuid().v4(),
      direction: 'out',
      kind: _inferKind(name),
      label: name,
      filePath: file.path,
      size: length,
      status: 'queued',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _queue.insert(0, item);
    _queueController.add(_queue);

    _processNext();
    return item;
  }

  void _processNext() async {
    if (_isProcessing) return;
    final nextIndex = _queue.indexWhere((e) => e.status == 'queued');
    if (nextIndex == -1) return;

    _isProcessing = true;
    final item = _queue[nextIndex];
    _updateStatus(item.id, 'sending');

    try {
      final client = customClient ?? await _buildClient();

      await executeWithRetry(() async {
        if (item.kind == 'text' || item.kind == 'link') {
          await client.sendText(
            content: item.content ?? item.label,
            kind: item.kind,
            clientId: item.id,
          );
        } else if (item.filePath != null) {
          final file = File(item.filePath!);
          await client.sendFile(
            file: file,
            fileName: item.label,
            clientId: item.id,
            onProgress: (sent, total) {
              if (total > 0) {
                final prog = (sent / total).clamp(0.0, 1.0);
                _updateProgress(item.id, prog);
              }
            },
          );
        }
      });

      _updateStatus(item.id, 'done', progress: 1.0);
    } catch (e) {
      _updateStatus(item.id, 'failed', error: e.toString());
    } finally {
      _isProcessing = false;
      _processNext();
    }
  }

  Future<ApiClient> _buildClient() async {
    final host = await secureStore.getPcHost();
    final port = await secureStore.getPcPort();
    final fp = await secureStore.getPcFingerprint();
    final secret = await secureStore.getPcSecret();
    final isDev = await secureStore.isDevMode();

    if (host == null || port == null || secret == null) {
      throw Exception('PC not configured');
    }

    return ApiClient.fromConfig(
      host: host,
      port: port,
      fingerprint: fp,
      deviceSecret: secret,
      isDevPlainHttp: isDev,
    );
  }

  /// Retries twice with exponential backoff on network errors only.
  /// Never retries on 4xx HTTP responses per SPEC Section 10.
  static Future<T> executeWithRetry<T>(
    Future<T> Function() action, {
    int maxAttempts = 3,
    Duration baseDelay = const Duration(milliseconds: 500),
  }) async {
    int attempts = 0;
    while (true) {
      try {
        attempts++;
        return await action();
      } catch (e) {
        if (e is DioException) {
          final statusCode = e.response?.statusCode;
          if (statusCode != null && statusCode >= 400 && statusCode < 500) {
            rethrow; // Never retry on 4xx per SPEC
          }
        }
        if (attempts >= maxAttempts) {
          rethrow;
        }
        await Future.delayed(baseDelay * attempts);
      }
    }
  }

  void _updateStatus(
    String id,
    String status, {
    double? progress,
    String? error,
  }) {
    final idx = _queue.indexWhere((e) => e.id == id);
    if (idx != -1) {
      _queue[idx] = _queue[idx].copyWith(
        status: status,
        progress: progress,
        error: error,
      );
      _queueController.add(_queue);
    }
  }

  void _updateProgress(String id, double progress) {
    final idx = _queue.indexWhere((e) => e.id == id);
    if (idx != -1) {
      _queue[idx] = _queue[idx].copyWith(progress: progress);
      _queueController.add(_queue);
    }
  }

  static String _inferKind(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      return 'image';
    }
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm')) {
      return 'video';
    }
    return 'file';
  }

  void dispose() {
    _queueController.close();
  }
}
