/// Data model and parser for clipsync://pair?... QR payloads
class PairQrPayload {
  final String host;
  final int port;
  final String token;
  final String fingerprint;
  final String serverDeviceId;
  final String serverName;

  static final RegExp _hex64Regex = RegExp(r'^[0-9a-fA-F]{64}$');

  const PairQrPayload({
    required this.host,
    required this.port,
    required this.token,
    required this.fingerprint,
    required this.serverDeviceId,
    required this.serverName,
  });

  /// Parses a raw clipsync://pair URI into [PairQrPayload].
  /// Returns null if URI is malformed, scheme is wrong, required query parameters
  /// are missing, port is invalid, or fingerprint is not a valid 64-char hex SHA-256.
  static PairQrPayload? tryParse(String rawUri) {
    try {
      final uri = Uri.parse(rawUri.trim());
      if (uri.scheme.toLowerCase() != 'clipsync' || uri.host.toLowerCase() != 'pair') {
        return null;
      }

      final q = uri.queryParameters;
      final host = q['host']?.trim();
      final portStr = q['port']?.trim();
      final token = q['token']?.trim();
      final fp = q['fp']?.trim();
      final id = q['id']?.trim();
      final rawName = q['name']?.trim();

      if (host == null || host.isEmpty ||
          portStr == null || portStr.isEmpty ||
          token == null || token.isEmpty ||
          fp == null || fp.isEmpty ||
          id == null || id.isEmpty ||
          rawName == null || rawName.isEmpty) {
        return null;
      }

      final port = int.tryParse(portStr);
      if (port == null || port <= 0 || port > 65535) {
        return null;
      }

      final normalizedFp = fp.replaceAll(':', '').replaceAll(' ', '').toLowerCase();
      if (!_hex64Regex.hasMatch(normalizedFp)) {
        return null; // Not a valid 64-character SHA-256 hex string
      }

      final name = Uri.decodeComponent(rawName);

      return PairQrPayload(
        host: host,
        port: port,
        token: token,
        fingerprint: normalizedFp,
        serverDeviceId: id,
        serverName: name,
      );
    } catch (_) {
      return null;
    }
  }

  String toUriString() {
    return 'clipsync://pair?host=$host&port=$port&token=$token&fp=$fingerprint&id=$serverDeviceId&name=${Uri.encodeComponent(serverName)}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PairQrPayload &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          token == other.token &&
          fingerprint == other.fingerprint &&
          serverDeviceId == other.serverDeviceId &&
          serverName == other.serverName;

  @override
  int get hashCode =>
      host.hashCode ^
      port.hashCode ^
      token.hashCode ^
      fingerprint.hashCode ^
      serverDeviceId.hashCode ^
      serverName.hashCode;
}

class PairResult {
  final bool success;
  final String? error;
  final String? serverName;
  final String? serverDeviceId;

  const PairResult.success({
    required this.serverName,
    required this.serverDeviceId,
  })  : success = true,
        error = null;

  const PairResult.failure(this.error)
      : success = false,
        serverName = null,
        serverDeviceId = null;
}
