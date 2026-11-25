import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/pairing_models.dart';
import '../data/secure_store.dart';

class PairingService {
  final SecureStore secureStore;
  final ApiClient Function({
    required String host,
    required int port,
    required String fingerprint,
    String? deviceSecret,
  })? clientFactory;

  PairingService({
    required this.secureStore,
    this.clientFactory,
  });

  /// Executes the 4-step pairing handshake per docs/SPEC.md Section 7, 8 & 10:
  /// 1. Pinned TLS connection to GET /info with certificate fingerprint pinning.
  /// 2. Verify server device_id matches QR payload.
  /// 3. POST /pair with token, selfDeviceId, deviceName, platform.
  /// 4. Store long-lived device secret and PC info in SecureStorage.
  Future<PairResult> pairWithPayload(
    PairQrPayload payload, {
    String phoneName = 'Android Phone',
  }) async {
    try {
      final client = _createClient(
        host: payload.host,
        port: payload.port,
        fingerprint: payload.fingerprint,
      );

      // Step 1: Probe /info with certificate pinning
      final info = await client.getInfo();

      // Step 2: Verify server device ID if provided in payload
      if (payload.serverDeviceId.isNotEmpty &&
          info.deviceId.isNotEmpty &&
          info.deviceId != payload.serverDeviceId) {
        return PairResult.failure(
          'Server device ID mismatch: expected ${payload.serverDeviceId}, got ${info.deviceId}',
        );
      }

      // Step 3: Get or create self device ID
      final selfId = await secureStore.getOrCreateSelfDeviceId();

      // Step 4: POST /pair exchanging one-time token for device secret
      final pairResponse = await client.pair(
        token: payload.token,
        deviceId: selfId,
        deviceName: phoneName,
        platform: 'android',
      );

      if (pairResponse.deviceSecret.isEmpty) {
        return const PairResult.failure('Server returned empty device secret');
      }

      final serverName = pairResponse.serverName.isNotEmpty
          ? pairResponse.serverName
          : (info.name.isNotEmpty ? info.name : payload.serverName);

      final serverDeviceId = pairResponse.serverDeviceId.isNotEmpty
          ? pairResponse.serverDeviceId
          : (info.deviceId.isNotEmpty ? info.deviceId : payload.serverDeviceId);

      // Step 5: Securely save credentials
      await secureStore.savePairedPc(
        pcDeviceId: serverDeviceId,
        pcName: serverName,
        pcHost: payload.host,
        pcPort: payload.port,
        pcFingerprint: payload.fingerprint,
        pcSecret: pairResponse.deviceSecret,
      );

      return PairResult.success(
        serverName: serverName,
        serverDeviceId: serverDeviceId,
      );
    } catch (e) {
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final errorData = e.response?.data;
        if (statusCode == 401) {
          final msg = errorData is Map && errorData['error'] is Map
              ? errorData['error']['message'] as String?
              : 'Invalid or expired pairing token';
          return PairResult.failure(msg ?? 'Pairing failed: 401 Unauthorized');
        }
        if (statusCode == 429) {
          return const PairResult.failure('Too many pairing attempts. Please wait 1 minute.');
        }
        final errStr = '${e.message ?? ''} ${e.error ?? ''}';
        if (errStr.contains('No route to host') || errStr.contains('errno = 113')) {
          return PairResult.failure(
            'Cannot reach PC at ${payload.host}:${payload.port} (No route to host).\n'
            '• Ensure Phone & PC are on the same Wi-Fi (no Guest Wi-Fi / AP isolation)\n'
            '• Set Windows Wi-Fi to Private or allow ClipSync in Windows Firewall\n'
            '• Disable any active VPN on phone or PC',
          );
        }
        if (e.type == DioExceptionType.connectionTimeout || errStr.contains('timed out')) {
          return PairResult.failure(
            'Connection timed out to ${payload.host}:${payload.port}. '
            'Check that Windows Firewall allows TCP port ${payload.port}.',
          );
        }
        if (errStr.contains('Connection refused')) {
          return PairResult.failure(
            'Connection refused at ${payload.host}:${payload.port}. '
            'Make sure ClipSync Desktop is running.',
          );
        }
      }
      return PairResult.failure(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Unpairs the phone: sends DELETE /pair to PC and clears local credentials
  Future<void> unpair() async {
    try {
      final host = await secureStore.getPcHost();
      final port = await secureStore.getPcPort();
      final fp = await secureStore.getPcFingerprint();
      final secret = await secureStore.getPcSecret();

      if (host != null && port != null && fp != null && secret != null) {
        final client = _createClient(
          host: host,
          port: port,
          fingerprint: fp,
          deviceSecret: secret,
        );
        await client.unpair();
      }
    } catch (_) {
      // Best-effort remote unpair
    } finally {
      await secureStore.clearPairedPc();
    }
  }

  ApiClient _createClient({
    required String host,
    required int port,
    required String fingerprint,
    String? deviceSecret,
  }) {
    if (clientFactory != null) {
      return clientFactory!(
        host: host,
        port: port,
        fingerprint: fingerprint,
        deviceSecret: deviceSecret,
      );
    }
    return ApiClient.fromConfig(
      host: host,
      port: port,
      fingerprint: fingerprint,
      deviceSecret: deviceSecret,
    );
  }
}
