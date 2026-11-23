import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Manages sensitive paired PC secrets and identifiers via FlutterSecureStorage
class SecureStore {
  static const _keySelfDeviceId = 'self.device_id';
  static const _keyPcDeviceId = 'pc.device_id';
  static const _keyPcName = 'pc.name';
  static const _keyPcHost = 'pc.host';
  static const _keyPcPort = 'pc.port';
  static const _keyPcFingerprint = 'pc.fingerprint';
  static const _keyPcSecret = 'pc.secret';
  static const _keyIsDevMode = 'pc.dev_mode';

  final FlutterSecureStorage _storage;

  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
            );

  Future<String> getOrCreateSelfDeviceId() async {
    String? id = await _storage.read(key: _keySelfDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await _storage.write(key: _keySelfDeviceId, value: id);
    }
    return id;
  }

  Future<String?> getPcDeviceId() => _storage.read(key: _keyPcDeviceId);
  Future<String?> getPcName() => _storage.read(key: _keyPcName);
  Future<String?> getPcHost() => _storage.read(key: _keyPcHost);
  Future<int?> getPcPort() async {
    final str = await _storage.read(key: _keyPcPort);
    return str != null ? int.tryParse(str) : null;
  }

  Future<String?> getPcFingerprint() => _storage.read(key: _keyPcFingerprint);
  Future<String?> getPcSecret() => _storage.read(key: _keyPcSecret);
  Future<bool> isDevMode() async {
    final v = await _storage.read(key: _keyIsDevMode);
    return v == 'true';
  }

  Future<void> setDevMode(bool isDev) async {
    await _storage.write(key: _keyIsDevMode, value: isDev.toString());
  }

  Future<void> saveDevConfig({
    String host = '127.0.0.1',
    int port = 47821,
    String token = 'dev-token-clipsync',
  }) async {
    await Future.wait([
      _storage.write(key: _keyPcHost, value: host),
      _storage.write(key: _keyPcPort, value: port.toString()),
      _storage.write(key: _keyPcSecret, value: token),
      _storage.write(key: _keyPcName, value: 'Dev PC ($host:$port)'),
      _storage.write(key: _keyPcDeviceId, value: 'dev-pc-id'),
      _storage.write(key: _keyPcFingerprint, value: 'dev'),
      _storage.write(key: _keyIsDevMode, value: 'true'),
    ]);
  }

  Future<bool> isPaired() async {
    final secret = await getPcSecret();
    final host = await getPcHost();
    return secret != null && secret.isNotEmpty && host != null && host.isNotEmpty;
  }

  Future<void> savePairedPc({
    required String pcDeviceId,
    required String pcName,
    required String pcHost,
    required int pcPort,
    required String pcFingerprint,
    required String pcSecret,
  }) async {
    await Future.wait([
      _storage.write(key: _keyPcDeviceId, value: pcDeviceId),
      _storage.write(key: _keyPcName, value: pcName),
      _storage.write(key: _keyPcHost, value: pcHost),
      _storage.write(key: _keyPcPort, value: pcPort.toString()),
      _storage.write(key: _keyPcFingerprint, value: pcFingerprint),
      _storage.write(key: _keyPcSecret, value: pcSecret),
    ]);
  }

  Future<void> updateHostAndPort({
    required String pcHost,
    required int pcPort,
  }) async {
    await Future.wait([
      _storage.write(key: _keyPcHost, value: pcHost),
      _storage.write(key: _keyPcPort, value: pcPort.toString()),
    ]);
  }

  Future<void> clearPairedPc() async {
    await Future.wait([
      _storage.delete(key: _keyPcDeviceId),
      _storage.delete(key: _keyPcName),
      _storage.delete(key: _keyPcHost),
      _storage.delete(key: _keyPcPort),
      _storage.delete(key: _keyPcFingerprint),
      _storage.delete(key: _keyPcSecret),
    ]);
  }
}
