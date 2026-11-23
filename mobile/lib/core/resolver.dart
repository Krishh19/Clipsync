import 'dart:async';
import 'dart:convert';
import 'package:nsd/nsd.dart' as nsd;

import 'api_client.dart';
import 'models.dart';

class ResolvedHost {
  final String host;
  final int port;
  final String deviceId;
  final String name;

  const ResolvedHost({
    required this.host,
    required this.port,
    required this.deviceId,
    required this.name,
  });
}

class PcResolver {
  /// Resolves the PC address per SPEC Section 10:
  /// (1) Try last known host and port with GET /info (1.5s timeout)
  /// (2) mDNS lookup for _clipsync._tcp matching targetDeviceId (5s timeout)
  /// (3) Returns null if not found
  static Future<ResolvedHost?> resolvePc({
    required String targetDeviceId,
    required String fingerprint,
    String? cachedHost,
    int? cachedPort,
  }) async {
    // 1. Try cached host and port
    if (cachedHost != null && cachedPort != null) {
      final info = await _probeHost(cachedHost, cachedPort, fingerprint);
      if (info != null && info.deviceId == targetDeviceId) {
        return ResolvedHost(
          host: cachedHost,
          port: cachedPort,
          deviceId: info.deviceId,
          name: info.name,
        );
      }
    }

    // 2. mDNS discovery for 5 seconds
    try {
      final discovery =
          await nsd.startDiscovery('_clipsync._tcp', autoResolve: true);
      final completer = Completer<ResolvedHost?>();

      void checkService(nsd.Service service) async {
        final host = service.host;
        final port = service.port;
        if (host == null || port == null) return;

        // Verify TXT record id if present
        final txtIdBytes = service.txt?['id'];
        if (txtIdBytes != null) {
          final txtId = utf8.decode(txtIdBytes, allowMalformed: true);
          if (txtId != targetDeviceId) {
            return;
          }
        }

        // Verify via /info
        final info = await _probeHost(host, port, fingerprint);
        if (info != null && info.deviceId == targetDeviceId) {
          if (!completer.isCompleted) {
            completer.complete(ResolvedHost(
              host: host,
              port: port,
              deviceId: info.deviceId,
              name: info.name,
            ));
          }
        }
      }

      discovery.addServiceListener((service, status) {
        if (status == nsd.ServiceStatus.found) {
          checkService(service);
        }
      });

      for (final s in discovery.services) {
        checkService(s);
      }

      final timer = Timer(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });

      final result = await completer.future;
      timer.cancel();
      await nsd.stopDiscovery(discovery);
      return result;
    } catch (_) {
      return null;
    }
  }

  static Future<ServerInfo?> _probeHost(
    String host,
    int port,
    String fingerprint,
  ) async {
    try {
      final client = ApiClient.fromConfig(
        host: host,
        port: port,
        fingerprint: fingerprint,
      );
      return await client
          .getInfo()
          .timeout(const Duration(milliseconds: 1500));
    } catch (_) {
      return null;
    }
  }
}
