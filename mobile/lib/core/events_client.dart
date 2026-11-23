import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'models.dart';
import 'pinned_client.dart';

/// WebSocket client that connects to PC /events with certificate pinning and auto-reconnect
class EventsClient {
  final String host;
  final int port;
  final String fingerprint;
  final String secret;
  final void Function(WsEvent event)? onEvent;
  final void Function(Object error)? onError;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _disposed = false;
  int _backoffSeconds = 1;

  EventsClient({
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.secret,
    this.onEvent,
    this.onError,
  });

  void connect() {
    if (_disposed) return;

    try {
      final customHttpClient = PinnedClient.createHttpClient(fingerprint);
      final uri = Uri.parse('wss://$host:$port/api/v1/events');

      final channel = IOWebSocketChannel.connect(
        uri,
        headers: {
          'Authorization': 'Bearer $secret',
        },
        customClient: customHttpClient,
      );

      _channel = channel;
      _backoffSeconds = 1;

      _subscription = channel.stream.listen(
        (data) {
          _handleMessage(data);
        },
        onError: (err) {
          onError?.call(err);
          _scheduleReconnect();
        },
        onDone: () {
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      onError?.call(e);
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic data) {
    try {
      final text = data.toString();
      final event = WsEvent.fromJsonString(text);

      if (event.type == 'ping') {
        sendPong();
      }

      onEvent?.call(event);
    } catch (_) {}
  }

  void sendPong() {
    _channel?.sink.add(jsonEncode({'type': 'pong'}));
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _subscription?.cancel();
    _channel = null;

    final delay = Duration(seconds: _backoffSeconds);
    _backoffSeconds = (_backoffSeconds * 2).clamp(1, 30);

    Timer(delay, () {
      if (!_disposed) {
        connect();
      }
    });
  }

  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _channel?.sink.close();
  }
}
