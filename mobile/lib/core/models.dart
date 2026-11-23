import 'dart:convert';
export 'loop_prevention.dart';
export 'pairing_models.dart';

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
  final String? content; // for text
  final String? filePath; // for file
  final int size;
  final String status; // 'queued', 'sending', 'done', 'failed'
  final double progress; // 0.0 to 1.0
  final String? error;
  final int createdAt;

  const TransferItem({
    required this.id,
    required this.direction,
    required this.kind,
    required this.label,
    this.content,
    this.filePath,
    required this.size,
    required this.status,
    this.progress = 0.0,
    this.error,
    required this.createdAt,
  });

  TransferItem copyWith({
    String? status,
    double? progress,
    String? error,
  }) {
    return TransferItem(
      id: id,
      direction: direction,
      kind: kind,
      label: label,
      content: content,
      filePath: filePath,
      size: size,
      status: status ?? this.status,
      progress: progress ?? this.progress,
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
