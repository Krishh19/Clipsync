import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'models.dart';
import 'pinned_client.dart';

typedef WebSocketChannelFactory = WebSocketChannel Function(
  Uri uri, {
  Map<String, dynamic>? headers,
  dynamic customClient,
});

/// WebSocket client that connects to PC /events with certificate pinning and auto-reconnect
class EventsClient {
  final String host;
  final int port;
  final String fingerprint;
  final String secret;
  final void Function(WsEvent event)? onEvent;
  final void Function(Object error)? onError;
  final void Function(bool connected)? onConnectionChanged;
  final WebSocketChannelFactory? channelFactory;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;
  int _backoffSeconds = 1;

  EventsClient({
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.secret,
    this.onEvent,
    this.onError,
    this.onConnectionChanged,
    this.channelFactory,
  });

  int get backoffSeconds => _backoffSeconds;
  bool get isConnected => _channel != null && !_disposed;

  /// Calculates exponential backoff clamped between 1 and 30 seconds
  static int calculateNextBackoff(int current) => (current * 2).clamp(1, 30);

  void connect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();

    try {
      final customHttpClient = PinnedClient.createHttpClient(fingerprint);
      final uri = Uri.parse('wss://$host:$port/api/v1/events');

      final channel = channelFactory != null
          ? channelFactory!(
              uri,
              headers: {'Authorization': 'Bearer $secret'},
              customClient: customHttpClient,
            )
          : IOWebSocketChannel.connect(
              uri,
              headers: {'Authorization': 'Bearer $secret'},
              customClient: customHttpClient,
            );

      _channel = channel;

      _subscription = channel.stream.listen(
        (data) {
          // Reset backoff on successful communication
          _backoffSeconds = 1;
          onConnectionChanged?.call(true);
          _handleMessage(data);
        },
        onError: (err) {
          onConnectionChanged?.call(false);
          onError?.call(err);
          _scheduleReconnect();
        },
        onDone: () {
          onConnectionChanged?.call(false);
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      onConnectionChanged?.call(false);
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
    _subscription = null;
    _channel = null;

    final delay = Duration(seconds: _backoffSeconds);
    _backoffSeconds = calculateNextBackoff(_backoffSeconds);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_disposed) {
        connect();
      }
    });
  }

  void resetBackoff() {
    _backoffSeconds = 1;
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }
}
