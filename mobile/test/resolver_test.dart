import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/models.dart';
import 'package:mobile/core/resolver.dart';
import 'package:mobile/data/secure_store.dart';

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

void main() {
  const targetId = 'target-pc-uuid-1234';
  const targetFp = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

  group('PcResolver - Stage 1 (Cached Host)', () {
    test('Cached host works -> returns immediately without searching mDNS', () async {
      bool mdnsSearched = false;
      int probeCallCount = 0;

      Future<ServerInfo?> mockProbe(String host, int port, String fp) async {
        probeCallCount++;
        if (host == '192.168.1.50' && port == 47821) {
          return const ServerInfo(
            name: 'KRISHH-DESKTOP',
            deviceId: targetId,
            protocol: 1,
          );
        }
        return null;
      }

      Stream<DiscoveredService> mockMdns({Duration? timeout}) {
        mdnsSearched = true;
        return const Stream.empty();
      }

      final resolved = await PcResolver.resolvePc(
        targetDeviceId: targetId,
        fingerprint: targetFp,
        cachedHost: '192.168.1.50',
        cachedPort: 47821,
        probeHost: mockProbe,
        mdnsStream: mockMdns,
      );

      expect(resolved, isNotNull);
      expect(resolved!.host, equals('192.168.1.50'));
      expect(resolved.port, equals(47821));
      expect(resolved.deviceId, equals(targetId));
      expect(resolved.name, equals('KRISHH-DESKTOP'));
      expect(probeCallCount, equals(1));
      expect(mdnsSearched, isFalse, reason: 'Stage 1 hit must not trigger mDNS discovery');
    });

    test('Loads cached credentials automatically from SecureStore if not passed', () async {
      final mockStorage = _MockSecureStorage();
      final secureStore = SecureStore(storage: mockStorage);
      await secureStore.savePairedPc(
        pcDeviceId: targetId,
        pcName: 'KRISHH-LAPTOP',
        pcHost: '192.168.1.75',
        pcPort: 47822,
        pcFingerprint: targetFp,
        pcSecret: 'test-secret',
      );

      Future<ServerInfo?> mockProbe(String host, int port, String fp) async {
        if (host == '192.168.1.75' && port == 47822) {
          return const ServerInfo(
            name: 'KRISHH-LAPTOP',
            deviceId: targetId,
            protocol: 1,
          );
        }
        return null;
      }

      final resolved = await PcResolver.resolvePc(
        targetDeviceId: targetId,
        fingerprint: targetFp,
        secureStore: secureStore,
        probeHost: mockProbe,
        mdnsStream: ({Duration? timeout}) => const Stream.empty(),
      );

      expect(resolved, isNotNull);
      expect(resolved!.host, equals('192.168.1.75'));
      expect(resolved.port, equals(47822));
      expect(resolved.deviceId, equals(targetId));
    });
  });

  group('PcResolver - Stage 2 (mDNS Fallback & SecureStore Update)', () {
    test('Cached host fails (IP changed) -> falls back to mDNS, discovers new IP, and updates SecureStore', () async {
      final mockStorage = _MockSecureStorage();
      final secureStore = SecureStore(storage: mockStorage);
      // Old IP stored from prior session
      await secureStore.savePairedPc(
        pcDeviceId: targetId,
        pcName: 'KRISHH-PC',
        pcHost: '192.168.1.50',
        pcPort: 47821,
        pcFingerprint: targetFp,
        pcSecret: 'secret-token',
      );

      // Probe: fails on old IP (connection refused), succeeds on new IP
      Future<ServerInfo?> mockProbe(String host, int port, String fp) async {
        if (host == '192.168.1.50') {
          throw Exception('Connection refused');
        }
        if (host == '192.168.1.188' && port == 47825) {
          return const ServerInfo(
            name: 'KRISHH-PC-NEW',
            deviceId: targetId,
            protocol: 1,
          );
        }
        return null;
      }

      // mDNS discovers new service on .188:47825
      Stream<DiscoveredService> mockMdns({Duration? timeout}) {
        return Stream.fromIterable([
          DiscoveredService.fromTxtStrings(
            host: '192.168.1.188',
            port: 47825,
            name: 'KRISHH-PC',
            txtStrings: {'id': targetId, 'v': '1'},
          ),
        ]);
      }

      final resolved = await PcResolver.resolvePc(
        targetDeviceId: targetId,
        fingerprint: targetFp,
        secureStore: secureStore,
        probeHost: mockProbe,
        mdnsStream: mockMdns,
        stage1Timeout: const Duration(milliseconds: 100),
        stage2Timeout: const Duration(milliseconds: 500),
      );

      // Verify resolved host matches new IP & port
      expect(resolved, isNotNull);
      expect(resolved!.host, equals('192.168.1.188'));
      expect(resolved.port, equals(47825));
      expect(resolved.deviceId, equals(targetId));
      expect(resolved.name, equals('KRISHH-PC-NEW'));

      // Verify SecureStore was automatically updated with new host & port
      expect(await secureStore.getPcHost(), equals('192.168.1.188'));
      expect(await secureStore.getPcPort(), equals(47825));
      // Secret and fingerprint must remain intact
      expect(await secureStore.getPcSecret(), equals('secret-token'));
      expect(await secureStore.getPcFingerprint(), equals(targetFp));
    });

    test('Discovers service when TXT record has no id but /info probe matches', () async {
      Future<ServerInfo?> mockProbe(String host, int port, String fp) async {
        if (host == '192.168.1.99' && port == 47821) {
          return const ServerInfo(
            name: 'MATCHING-PC',
            deviceId: targetId,
            protocol: 1,
          );
        }
        return null;
      }

      Stream<DiscoveredService> mockMdns({Duration? timeout}) {
        return Stream.fromIterable([
          const DiscoveredService(
            host: '192.168.1.99',
            port: 47821,
            name: 'Some Service',
            txt: null, // No TXT record
          ),
        ]);
      }

      final resolved = await PcResolver.resolvePc(
        targetDeviceId: targetId,
        fingerprint: targetFp,
        cachedHost: '192.168.1.2', // will fail probe
        cachedPort: 47821,
        probeHost: mockProbe,
        mdnsStream: mockMdns,
        stage1Timeout: const Duration(milliseconds: 100),
        stage2Timeout: const Duration(milliseconds: 500),
      );

      expect(resolved, isNotNull);
      expect(resolved!.host, equals('192.168.1.99'));
      expect(resolved.deviceId, equals(targetId));
    });
  });

  group('PcResolver - Stage 3 (Fallback & Filtering)', () {
    test('Both cached and mDNS fail -> returns null within timeout', () async {
      Future<ServerInfo?> mockProbe(String host, int port, String fp) async {
        return null;
      }

      Stream<DiscoveredService> mockMdns({Duration? timeout}) {
        // Yields service that fails probe
        return Stream.fromIterable([
          DiscoveredService.fromTxtStrings(
            host: '192.168.1.200',
            port: 47821,
            txtStrings: {'id': targetId},
          ),
        ]);
      }

      final resolved = await PcResolver.resolvePc(
        targetDeviceId: targetId,
        fingerprint: targetFp,
        cachedHost: '192.168.1.10',
        cachedPort: 47821,
        probeHost: mockProbe,
        mdnsStream: mockMdns,
        stage1Timeout: const Duration(milliseconds: 50),
        stage2Timeout: const Duration(milliseconds: 100),
      );

      expect(resolved, isNull);
    });

    test('Empty mDNS stream -> returns null after stream completes', () async {
      final resolved = await PcResolver.resolvePc(
        targetDeviceId: targetId,
        fingerprint: targetFp,
        probeHost: (h, p, f) async => null,
        mdnsStream: ({Duration? timeout}) => const Stream.empty(),
        stage1Timeout: const Duration(milliseconds: 50),
        stage2Timeout: const Duration(milliseconds: 100),
      );

      expect(resolved, isNull);
    });

    test('mDNS TXT id filtering ignores other devices on the network', () async {
      final probedHosts = <String>[];

      Future<ServerInfo?> mockProbe(String host, int port, String fp) async {
        probedHosts.add(host);
        if (host == '192.168.1.150') {
          return const ServerInfo(
            name: 'MY-TARGET-PC',
            deviceId: targetId,
            protocol: 1,
          );
        }
        return null;
      }

      Stream<DiscoveredService> mockMdns({Duration? timeout}) {
        return Stream.fromIterable([
          // Device 1: different device ID in TXT
          DiscoveredService.fromTxtStrings(
            host: '192.168.1.110',
            port: 47821,
            txtStrings: {'id': 'someone-elses-device-id'},
          ),
          // Device 2: another different device ID in TXT
          DiscoveredService.fromTxtStrings(
            host: '192.168.1.120',
            port: 47821,
            txtStrings: {'id': 'another-foreign-id'},
          ),
          // Device 3: our target device
          DiscoveredService.fromTxtStrings(
            host: '192.168.1.150',
            port: 47821,
            txtStrings: {'id': targetId},
          ),
        ]);
      }

      final resolved = await PcResolver.resolvePc(
        targetDeviceId: targetId,
        fingerprint: targetFp,
        probeHost: mockProbe,
        mdnsStream: mockMdns,
        stage1Timeout: const Duration(milliseconds: 100),
        stage2Timeout: const Duration(milliseconds: 500),
      );

      expect(resolved, isNotNull);
      expect(resolved!.host, equals('192.168.1.150'));
      expect(resolved.deviceId, equals(targetId));

      // Must NOT have probed .110 or .120 because their TXT id did not match targetId
      expect(probedHosts, contains('192.168.1.150'));
      expect(probedHosts, isNot(contains('192.168.1.110')));
      expect(probedHosts, isNot(contains('192.168.1.120')));
    });

    test('Rejects service if /info returns a different device_id than target', () async {
      Future<ServerInfo?> mockProbe(String host, int port, String fp) async {
        return const ServerInfo(
          name: 'IMPOSTER-PC',
          deviceId: 'imposter-uuid',
          protocol: 1,
        );
      }

      Stream<DiscoveredService> mockMdns({Duration? timeout}) {
        return Stream.fromIterable([
          const DiscoveredService(
            host: '192.168.1.80',
            port: 47821,
          ),
        ]);
      }

      final resolved = await PcResolver.resolvePc(
        targetDeviceId: targetId,
        fingerprint: targetFp,
        probeHost: mockProbe,
        mdnsStream: mockMdns,
        stage1Timeout: const Duration(milliseconds: 50),
        stage2Timeout: const Duration(milliseconds: 100),
      );

      expect(resolved, isNull);
    });
  });

  group('ResolvedHost & DiscoveredService Data Model Tests', () {
    test('ResolvedHost equality and toString', () {
      const r1 = ResolvedHost(
        host: '192.168.1.10',
        port: 47821,
        deviceId: 'id-1',
        name: 'PC-1',
      );
      const r2 = ResolvedHost(
        host: '192.168.1.10',
        port: 47821,
        deviceId: 'id-1',
        name: 'PC-1',
      );
      const r3 = ResolvedHost(
        host: '192.168.1.20',
        port: 47821,
        deviceId: 'id-1',
        name: 'PC-1',
      );

      expect(r1, equals(r2));
      expect(r1.hashCode, equals(r2.hashCode));
      expect(r1, isNot(equals(r3)));
      expect(r1.toString(), contains('192.168.1.10:47821'));
    });

    test('DiscoveredService extracts txt fields properly', () {
      final s = DiscoveredService.fromTxtStrings(
        host: '10.0.0.5',
        port: 47821,
        txtStrings: {
          'id': 'my-device-id',
          'name': 'My Computer',
          'v': '1',
          'fp': 'e3b0c44298fc1c14',
        },
      );

      expect(s.txtDeviceId, equals('my-device-id'));
      expect(s.txtDeviceName, equals('My Computer'));
    });
  });
}
