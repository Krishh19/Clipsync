import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/api_client.dart';
import 'package:mobile/core/models.dart';
import 'package:mobile/core/pinned_client.dart';
import 'package:mobile/data/secure_store.dart';
import 'package:mobile/services/pairing_service.dart';

class _MockSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final memberName = invocation.memberName;
    if (memberName == #read) {
      final key = invocation.namedArguments[#key] as String;
      return Future.value(_store[key]);
    }
    if (memberName == #write) {
      final key = invocation.namedArguments[#key] as String;
      final value = invocation.namedArguments[#value] as String?;
      if (value != null) {
        _store[key] = value;
      } else {
        _store.remove(key);
      }
      return Future.value();
    }
    if (memberName == #delete) {
      final key = invocation.namedArguments[#key] as String;
      _store.remove(key);
      return Future.value();
    }
    return super.noSuchMethod(invocation);
  }
}

class _MockApiClient extends Fake implements ApiClient {
  ServerInfo infoResponse = const ServerInfo(
    name: 'KRISHH-PC',
    deviceId: 'server-uuid-1234',
    protocol: 1,
  );
  PairResponse pairResponse = const PairResponse(
    deviceSecret: 'base64url-device-secret-5678',
    serverDeviceId: 'server-uuid-1234',
    serverName: 'KRISHH-PC',
  );
  bool pairCalled = false;
  bool unpairCalled = false;
  int? throwPairStatusCode;
  String? throwPairErrorMessage;

  @override
  Future<ServerInfo> getInfo() async {
    return infoResponse;
  }

  @override
  Future<PairResponse> pair({
    required String token,
    required String deviceId,
    required String deviceName,
    String platform = 'android',
  }) async {
    pairCalled = true;
    if (throwPairStatusCode != null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/pair'),
        response: Response(
          requestOptions: RequestOptions(path: '/pair'),
          statusCode: throwPairStatusCode,
          data: throwPairErrorMessage != null
              ? {
                  'error': {
                    'code': 'invalid_token',
                    'message': throwPairErrorMessage,
                  }
                }
              : null,
        ),
      );
    }
    return pairResponse;
  }

  @override
  Future<void> unpair() async {
    unpairCalled = true;
  }
}

void main() {
  const validFp = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

  group('PairQrPayload URI Parser', () {
    test('parses standard clipsync://pair URI correctly', () {
      const uri =
          'clipsync://pair?host=192.168.1.50&port=47821&token=abcdef123456&fp=$validFp&id=server-id-99&name=KRISHH-DESKTOP';

      final payload = PairQrPayload.tryParse(uri);
      expect(payload, isNotNull);
      expect(payload!.host, equals('192.168.1.50'));
      expect(payload.port, equals(47821));
      expect(payload.token, equals('abcdef123456'));
      expect(payload.fingerprint, equals(validFp));
      expect(payload.serverDeviceId, equals('server-id-99'));
      expect(payload.serverName, equals('KRISHH-DESKTOP'));
    });

    test('decodes URL-encoded server name', () {
      const uri =
          'clipsync://pair?host=10.0.0.5&port=47821&token=tok123&fp=$validFp&id=srv-1&name=Alice%27s%20Work%20PC';

      final payload = PairQrPayload.tryParse(uri);
      expect(payload, isNotNull);
      expect(payload!.serverName, equals("Alice's Work PC"));
    });

    test('case-insensitive scheme and fingerprint normalization', () {
      final uppercaseFp = validFp.toUpperCase();
      final uri =
          'CLIPSYNC://PAIR?host=192.168.1.50&port=47821&token=tok&fp=$uppercaseFp&id=id1&name=PC';

      final payload = PairQrPayload.tryParse(uri);
      expect(payload, isNotNull);
      expect(payload!.fingerprint, equals(validFp)); // normalized to lowercase
    });

    test('rejects wrong schemes or host', () {
      expect(PairQrPayload.tryParse('http://pair?host=1.1.1.1'), isNull);
      expect(PairQrPayload.tryParse('https://pair?host=1.1.1.1'), isNull);
      expect(PairQrPayload.tryParse('clipsync://other?host=1.1.1.1'), isNull);
    });

    test('rejects missing parameters', () {
      // Missing token
      expect(
        PairQrPayload.tryParse(
          'clipsync://pair?host=192.168.1.50&port=47821&fp=$validFp&id=id1&name=PC',
        ),
        isNull,
      );
      // Missing host
      expect(
        PairQrPayload.tryParse(
          'clipsync://pair?port=47821&token=tok&fp=$validFp&id=id1&name=PC',
        ),
        isNull,
      );
      // Missing fp
      expect(
        PairQrPayload.tryParse(
          'clipsync://pair?host=192.168.1.50&port=47821&token=tok&id=id1&name=PC',
        ),
        isNull,
      );
    });

    test('rejects invalid ports', () {
      expect(
        PairQrPayload.tryParse(
          'clipsync://pair?host=1.1.1.1&port=0&token=tok&fp=$validFp&id=id1&name=PC',
        ),
        isNull,
      );
      expect(
        PairQrPayload.tryParse(
          'clipsync://pair?host=1.1.1.1&port=65536&token=tok&fp=$validFp&id=id1&name=PC',
        ),
        isNull,
      );
      expect(
        PairQrPayload.tryParse(
          'clipsync://pair?host=1.1.1.1&port=invalid&token=tok&fp=$validFp&id=id1&name=PC',
        ),
        isNull,
      );
    });

    test('rejects invalid fingerprints (not 64 hex chars)', () {
      // 63 chars
      expect(
        PairQrPayload.tryParse(
          'clipsync://pair?host=1.1.1.1&port=47821&token=tok&fp=${validFp.substring(1)}&id=id1&name=PC',
        ),
        isNull,
      );
      // 65 chars
      expect(
        PairQrPayload.tryParse(
          'clipsync://pair?host=1.1.1.1&port=47821&token=tok&fp=${validFp}a&id=id1&name=PC',
        ),
        isNull,
      );
      // Non-hex chars ('zz')
      final badFp = 'zz${validFp.substring(2)}';
      expect(
        PairQrPayload.tryParse(
          'clipsync://pair?host=1.1.1.1&port=47821&token=tok&fp=$badFp&id=id1&name=PC',
        ),
        isNull,
      );
    });

    test('toUriString generates valid round-trip URI', () {
      const payload = PairQrPayload(
        host: '192.168.1.200',
        port: 47821,
        token: 'token123',
        fingerprint: validFp,
        serverDeviceId: 'dev-id-1',
        serverName: 'Bob PC',
      );
      final uriString = payload.toUriString();
      final roundTrip = PairQrPayload.tryParse(uriString);
      expect(roundTrip, equals(payload));
    });
  });

  group('PinnedClient Certificate Verification', () {
    test('verifies matching certificate DER bytes', () {
      final sampleDerBytes = utf8.encode('Sample X.509 DER Certificate Content');
      final expectedHash = sha256.convert(sampleDerBytes).toString();

      final result = PinnedClient.verifyCertificateBytes(sampleDerBytes, expectedHash);
      expect(result, isTrue);
    });

    test('verifies case-insensitively and ignores colons', () {
      final sampleDerBytes = utf8.encode('Test Certificate');
      final rawHash = sha256.convert(sampleDerBytes).toString();
      // Add colons like AA:BB:CC:...
      final colonHash = rawHash.toUpperCase().replaceAllMapped(
            RegExp(r'.{2}'),
            (m) => '${m.group(0)}:',
          );

      final result = PinnedClient.verifyCertificateBytes(sampleDerBytes, colonHash);
      expect(result, isTrue);
    });

    test('rejects mismatched certificate bytes', () {
      final certA = utf8.encode('Certificate A');
      final certB = utf8.encode('Certificate B');
      final hashB = sha256.convert(certB).toString();

      final result = PinnedClient.verifyCertificateBytes(certA, hashB);
      expect(result, isFalse);
    });
  });

  group('PairingService Handshake Flow', () {
    test('successfully executes pairing handshake and stores credentials', () async {
      final mockStorage = _MockSecureStorage();
      final secureStore = SecureStore(storage: mockStorage);
      final mockClient = _MockApiClient();

      final service = PairingService(
        secureStore: secureStore,
        clientFactory: ({
          required String host,
          required int port,
          required String fingerprint,
          String? deviceSecret,
        }) =>
            mockClient,
      );

      const payload = PairQrPayload(
        host: '192.168.1.100',
        port: 47821,
        token: 'token-one-time-123',
        fingerprint: validFp,
        serverDeviceId: 'server-uuid-1234',
        serverName: 'KRISHH-PC',
      );

      final result = await service.pairWithPayload(payload, phoneName: 'Pixel 8');

      expect(result.success, isTrue);
      expect(result.serverName, equals('KRISHH-PC'));
      expect(result.serverDeviceId, equals('server-uuid-1234'));
      expect(mockClient.pairCalled, isTrue);

      // Verify credentials stored in SecureStore
      expect(await secureStore.getPcHost(), equals('192.168.1.100'));
      expect(await secureStore.getPcPort(), equals(47821));
      expect(await secureStore.getPcFingerprint(), equals(validFp));
      expect(await secureStore.getPcSecret(), equals('base64url-device-secret-5678'));
      expect(await secureStore.getPcDeviceId(), equals('server-uuid-1234'));
      expect(await secureStore.isPaired(), isTrue);
    });

    test('aborts pairing when server device_id mismatches QR payload', () async {
      final mockStorage = _MockSecureStorage();
      final secureStore = SecureStore(storage: mockStorage);
      final mockClient = _MockApiClient();
      // Server returns different ID
      mockClient.infoResponse = const ServerInfo(
        name: 'Imposter-PC',
        deviceId: 'different-server-id',
        protocol: 1,
      );

      final service = PairingService(
        secureStore: secureStore,
        clientFactory: ({
          required String host,
          required int port,
          required String fingerprint,
          String? deviceSecret,
        }) =>
            mockClient,
      );

      const payload = PairQrPayload(
        host: '192.168.1.100',
        port: 47821,
        token: 'tok',
        fingerprint: validFp,
        serverDeviceId: 'expected-server-id',
        serverName: 'KRISHH-PC',
      );

      final result = await service.pairWithPayload(payload);

      expect(result.success, isFalse);
      expect(result.error, contains('device ID mismatch'));
      // POST /pair must NOT have been called
      expect(mockClient.pairCalled, isFalse);
      expect(await secureStore.isPaired(), isFalse);
    });

    test('handles 401 invalid or expired pairing token', () async {
      final mockStorage = _MockSecureStorage();
      final secureStore = SecureStore(storage: mockStorage);
      final mockClient = _MockApiClient();
      mockClient.throwPairStatusCode = 401;
      mockClient.throwPairErrorMessage = 'Token has expired';

      final service = PairingService(
        secureStore: secureStore,
        clientFactory: ({
          required String host,
          required int port,
          required String fingerprint,
          String? deviceSecret,
        }) =>
            mockClient,
      );

      const payload = PairQrPayload(
        host: '192.168.1.100',
        port: 47821,
        token: 'expired-token',
        fingerprint: validFp,
        serverDeviceId: 'server-uuid-1234',
        serverName: 'KRISHH-PC',
      );

      final result = await service.pairWithPayload(payload);

      expect(result.success, isFalse);
      expect(result.error, contains('Token has expired'));
      expect(await secureStore.isPaired(), isFalse);
    });

    test('unpair calls remote endpoint and clears credentials', () async {
      final mockStorage = _MockSecureStorage();
      final secureStore = SecureStore(storage: mockStorage);
      await secureStore.savePairedPc(
        pcDeviceId: 'server-1',
        pcName: 'PC 1',
        pcHost: '192.168.1.1',
        pcPort: 47821,
        pcFingerprint: validFp,
        pcSecret: 'sec-1',
      );
      expect(await secureStore.isPaired(), isTrue);

      final mockClient = _MockApiClient();
      final service = PairingService(
        secureStore: secureStore,
        clientFactory: ({
          required String host,
          required int port,
          required String fingerprint,
          String? deviceSecret,
        }) =>
            mockClient,
      );

      await service.unpair();

      expect(mockClient.unpairCalled, isTrue);
      expect(await secureStore.isPaired(), isFalse);
      expect(await secureStore.getPcSecret(), isNull);
    });
  });
}
