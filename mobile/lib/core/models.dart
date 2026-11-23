import 'dart:convert';

/// Represents parsed QR code data from clipsync://pair?...
class PairQrPayload {
  final String host;
  final int port;
  final String token;
  final String fingerprint;
  final String serverDeviceId;
  final String serverName;

  const PairQrPayload({
    required this.host,
    required this.port,
    required this.token,
    required this.fingerprint,
    required this.serverDeviceId,
    required this.serverName,
  });

  static PairQrPayload? tryParse(String rawUri) {
    try {
      final uri = Uri.parse(rawUri);
      if (uri.scheme != 'clipsync' || uri.host != 'pair') {
        return null;
      }
      final q = uri.queryParameters;
      final host = q['host'];
      final portStr = q['port'];
      final token = q['token'];
      final fp = q['fp'];
      final id = q['id'];
      final name = q['name'];

      if (host == null ||
          portStr == null ||
          token == null ||
          fp == null ||
          id == null ||
          name == null) {
        return null;
      }

      final port = int.tryParse(portStr);
      if (port == null || port <= 0 || port > 65535) {
        return null;
      }

      return PairQrPayload(
        host: host,
        port: port,
        token: token,
        fingerprint: fp.toLowerCase(),
        serverDeviceId: id,
        serverName: Uri.decodeComponent(name),
      );
    } catch (_) {
      return null;
    }
  }

  String toUriString() {
    return 'clipsync://pair?host=$host&port=$port&token=$token&fp=$fingerprint&id=$serverDeviceId&name=${Uri.encodeComponent(serverName)}';
  }
}

/// Information returned by GET /api/v1/info
class ServerInfo {
  final String name;
  final String deviceId;
  final int protocol;

  const ServerInfo({
    required this.name,
    required this.deviceId,
    required this.protocol,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    return ServerInfo(
      name: json['name'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
      protocol: json['protocol'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'device_id': deviceId,
        'protocol': protocol,
      };
}

/// Response returned by POST /api/v1/pair
class PairResponse {
  final String deviceSecret;
  final String serverDeviceId;
  final String serverName;

  const PairResponse({
    required this.deviceSecret,
    required this.serverDeviceId,
    required this.serverName,
  });

  factory PairResponse.fromJson(Map<String, dynamic> json) {
    return PairResponse(
      deviceSecret: json['device_secret'] as String? ?? '',
      serverDeviceId: json['server_device_id'] as String? ?? '',
      serverName: json['server_name'] as String? ?? '',
    );
  }
}

/// Item transferred or queued
class TransferItem {
  final String id;
  final String direction; // 'in' or 'out'
  final String kind; // 'text', 'link', 'image', 'video', 'file'
  final String label;
  final int size;
  final String status; // 'queued', 'sending', 'done', 'failed'
  final String? error;
  final int createdAt;

  const TransferItem({
    required this.id,
    required this.direction,
    required this.kind,
    required this.label,
    required this.size,
    required this.status,
    this.error,
    required this.createdAt,
  });

  TransferItem copyWith({
    String? status,
    String? error,
  }) {
    return TransferItem(
      id: id,
      direction: direction,
      kind: kind,
      label: label,
      size: size,
      status: status ?? this.status,
      error: error ?? this.error,
      createdAt: createdAt,
    );
  }
}

/// WebSocket incoming event
class WsEvent {
  final String type;
  final Map<String, dynamic> data;

  const WsEvent({required this.type, required this.data});

  factory WsEvent.fromJsonString(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final type = decoded['type'] as String? ?? 'unknown';
    return WsEvent(type: type, data: decoded);
  }
}
