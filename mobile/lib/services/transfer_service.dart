import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../data/secure_store.dart';

class TransferService {
  final SecureStore secureStore;
  final List<TransferItem> _queue = [];
  bool _isProcessing = false;

  final StreamController<List<TransferItem>> _queueController =
      StreamController<List<TransferItem>>.broadcast();

  Stream<List<TransferItem>> get queueStream => _queueController.stream;
  List<TransferItem> get queue => List.unmodifiable(_queue);

  TransferService({required this.secureStore});

  Future<void> sendText(String content, {String kind = 'text'}) async {
    final item = TransferItem(
      id: const Uuid().v4(),
      direction: 'out',
      kind: kind,
      label: content.length > 50 ? '${content.substring(0, 50)}...' : content,
      size: content.length,
      status: 'queued',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _queue.insert(0, item);
    _queueController.add(_queue);

    _processNext();
  }

  Future<void> sendFile(File file, {String? fileName}) async {
    final name = fileName ?? file.uri.pathSegments.last;
    final size = await file.length();
    final item = TransferItem(
      id: const Uuid().v4(),
      direction: 'out',
      kind: _inferKind(name),
      label: name,
      size: size,
      status: 'queued',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _queue.insert(0, item);
    _queueController.add(_queue);

    _processNext();
  }

  void _processNext() async {
    if (_isProcessing) return;
    final nextIndex = _queue.indexWhere((e) => e.status == 'queued');
    if (nextIndex == -1) return;

    _isProcessing = true;
    final item = _queue[nextIndex];
    _updateStatus(item.id, 'sending');

    try {
      final host = await secureStore.getPcHost();
      final port = await secureStore.getPcPort();
      final fp = await secureStore.getPcFingerprint();
      final secret = await secureStore.getPcSecret();

      if (host == null || port == null || fp == null || secret == null) {
        throw Exception('PC not configured');
      }

      final client = ApiClient.fromConfig(
        host: host,
        port: port,
        fingerprint: fp,
        deviceSecret: secret,
      );

      await _executeWithRetry(() async {
        if (item.kind == 'text' || item.kind == 'link') {
          await client.sendText(content: item.label, kind: item.kind, clientId: item.id);
        }
      });

      _updateStatus(item.id, 'done');
    } catch (e) {
      _updateStatus(item.id, 'failed', error: e.toString());
    } finally {
      _isProcessing = false;
      _processNext();
    }
  }

  Future<T> _executeWithRetry<T>(Future<T> Function() action) async {
    int attempts = 0;
    while (true) {
      try {
        attempts++;
        return await action();
      } catch (e) {
        if (e is DioException) {
          final statusCode = e.response?.statusCode;
          // Never retry on 4xx client errors per SPEC Section 10
          if (statusCode != null && statusCode >= 400 && statusCode < 500) {
            rethrow;
          }
        }
        if (attempts >= 3) {
          rethrow;
        }
        // Exponential backoff for network errors
        await Future.delayed(Duration(milliseconds: 500 * attempts));
      }
    }
  }

  void _updateStatus(String id, String status, {String? error}) {
    final idx = _queue.indexWhere((e) => e.id == id);
    if (idx != -1) {
      _queue[idx] = _queue[idx].copyWith(status: status, error: error);
      _queueController.add(_queue);
    }
  }

  String _inferKind(String fileName) {
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
