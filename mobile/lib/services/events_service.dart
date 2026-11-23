import 'dart:async';
import '../core/events_client.dart';
import '../core/models.dart';
import '../data/secure_store.dart';
import 'notifications.dart';

class EventsService {
  final SecureStore secureStore;
  EventsClient? _client;
  bool _isRunning = false;

  EventsService({required this.secureStore});

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

    _client = EventsClient(
      host: host,
      port: port,
      fingerprint: fp,
      secret: secret,
      onEvent: _handleEvent,
      onError: (err) {
        // Logging or handling error
      },
    );
    _client?.connect();
  }

  void _handleEvent(WsEvent event) async {
    final senderName = await secureStore.getPcName() ?? 'PC';

    if (event.type == 'text') {
      final content = event.data['content'] as String? ?? '';
      final id = event.data['id'].hashCode;
      await NotificationsService.showTextReceived(
        id: id,
        senderName: senderName,
        text: content,
      );
    } else if (event.type == 'file_offer') {
      final fileId = event.data['id'] as String? ?? '';
      final fileName = event.data['name'] as String? ?? 'File';
      final id = fileId.hashCode;
      await NotificationsService.showFileOffer(
        id: id,
        senderName: senderName,
        fileName: fileName,
        fileId: fileId,
      );
    }
  }

  void stop() {
    _isRunning = false;
    _client?.dispose();
    _client = null;
  }
}
