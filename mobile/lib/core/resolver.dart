import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:nsd/nsd.dart' as nsd;

import '../data/secure_store.dart';
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedHost &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          deviceId == other.deviceId &&
          name == other.name;

  @override
  int get hashCode =>
      host.hashCode ^ port.hashCode ^ deviceId.hashCode ^ name.hashCode;

  @override
  String toString() => 'ResolvedHost($host:$port, id=$deviceId, name=$name)';
}

/// Represents an mDNS discovered service candidate
class DiscoveredService {
  final String? host;
  final int? port;
  final Map<String, Uint8List?>? txt;
  final String? name;

  const DiscoveredService({
    this.host,
    this.port,
    this.txt,
    this.name,
  });

  /// Convenience constructor for testing with String TXT records
  factory DiscoveredService.fromTxtStrings({
    String? host,
    int? port,
    String? name,
    Map<String, String>? txtStrings,
  }) {
    final Map<String, Uint8List?>? txt = txtStrings?.map(
      (k, v) => MapEntry(k, Uint8List.fromList(utf8.encode(v))),
    );
    return DiscoveredService(
      host: host,
      port: port,
      name: name,
      txt: txt,
    );
  }

  /// Extracts the 'id' field from mDNS TXT record if present
  String? get txtDeviceId {
    final bytes = txt?['id'];
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true).trim();
  }

  /// Extracts the 'name' field from mDNS TXT record if present
  String? get txtDeviceName {
    final bytes = txt?['name'];
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true).trim();
  }
}

typedef HostProbe = Future<ServerInfo?> Function(
  String host,
  int port,
  String fingerprint,
);

typedef MdnsDiscoveryStream = Stream<DiscoveredService> Function({
  Duration timeout,
});

class PcResolver {
  /// Resolves the PC address per SPEC Section 10:
  /// Stage 1: Try cached host & port with GET /info (1.5s timeout)
  /// Stage 2: mDNS lookup for _clipsync._tcp matching targetDeviceId (5s timeout)
  ///          On discovery, verify via GET /info and automatically update SecureStore.
  /// Stage 3: Returns null if not found (offline / manual fallback)
  static Future<ResolvedHost?> resolvePc({
    required String targetDeviceId,
    required String fingerprint,
    String? cachedHost,
    int? cachedPort,
    SecureStore? secureStore,
    Duration stage1Timeout = const Duration(milliseconds: 1500),
    Duration stage2Timeout = const Duration(seconds: 5),
    HostProbe? probeHost,
    MdnsDiscoveryStream? mdnsStream,
  }) async {
    final probe = probeHost ?? _defaultProbeHost;

    String? hostToTry = cachedHost;
    int? portToTry = cachedPort;

    // Load cached credentials from secureStore if not explicitly passed
    if (secureStore != null) {
      hostToTry ??= await secureStore.getPcHost();
      portToTry ??= await secureStore.getPcPort();
    }

    // ==========================================
    // Stage 1: Try cached host & port (1.5s timeout)
    // ==========================================
    if (hostToTry != null && hostToTry.isNotEmpty && portToTry != null && portToTry > 0) {
      try {
        final info = await probe(hostToTry, portToTry, fingerprint)
            .timeout(stage1Timeout);
        if (info != null && info.deviceId == targetDeviceId) {
          return ResolvedHost(
            host: hostToTry,
            port: portToTry,
            deviceId: info.deviceId,
            name: info.name,
          );
        }
      } catch (_) {
        // Stage 1 probe failed or timed out; continue to Stage 2
      }
    }

    // ==========================================
    // Stage 2: mDNS discovery for _clipsync._tcp (5s timeout)
    // ==========================================
    try {
      final streamBuilder = mdnsStream ?? _defaultMdnsStream;
      final stream = streamBuilder(timeout: stage2Timeout);

      final completer = Completer<ResolvedHost?>();
      StreamSubscription<DiscoveredService>? subscription;
      Timer? timer;
      int activeProbes = 0;
      bool isStreamDone = false;

      void checkDone() {
        if (isStreamDone && activeProbes == 0 && !completer.isCompleted) {
          timer?.cancel();
          subscription?.cancel();
          completer.complete(null);
        }
      }

      timer = Timer(stage2Timeout, () {
        if (!completer.isCompleted) {
          subscription?.cancel();
          completer.complete(null);
        }
      });

      subscription = stream.listen(
        (service) async {
          if (completer.isCompleted) return;

          final host = service.host;
          final port = service.port;
          if (host == null || port == null || port <= 0) return;

          // Check TXT record id if present
          final txtId = service.txtDeviceId;
          if (txtId != null && txtId.isNotEmpty && txtId != targetDeviceId) {
            // Different device advertised in TXT, ignore
            return;
          }

          activeProbes++;
          try {
            final info = await probe(host, port, fingerprint).timeout(stage1Timeout);
            if (!completer.isCompleted && info != null && info.deviceId == targetDeviceId) {
              timer?.cancel();
              subscription?.cancel();

              // Automatically update cached host and port in secure store
              if (secureStore != null) {
                try {
                  await secureStore.updateHostAndPort(pcHost: host, pcPort: port);
                } catch (_) {}
              }

              completer.complete(ResolvedHost(
                host: host,
                port: port,
                deviceId: info.deviceId,
                name: info.name,
              ));
              return;
            }
          } catch (_) {
            // Probe failed for this service
          } finally {
            activeProbes--;
            checkDone();
          }
        },
        onError: (_) {
          // Transient error on discovery stream; let timer handle overall timeout
        },
        onDone: () {
          isStreamDone = true;
          checkDone();
        },
        cancelOnError: false,
      );

      final result = await completer.future;
      return result;
    } catch (_) {
      // Stage 3 fallback
      return null;
    }
  }

  static Future<ServerInfo?> _defaultProbeHost(
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
      return await client.getInfo();
    } catch (_) {
      return null;
    }
  }

  static Stream<DiscoveredService> _defaultMdnsStream({
    Duration timeout = const Duration(seconds: 5),
  }) {
    late StreamController<DiscoveredService> controller;
    nsd.Discovery? discovery;

    controller = StreamController<DiscoveredService>(
      onListen: () async {
        try {
          discovery =
              await nsd.startDiscovery('_clipsync._tcp', autoResolve: true);
          discovery?.addServiceListener((service, status) {
            if (status == nsd.ServiceStatus.found && !controller.isClosed) {
              controller.add(DiscoveredService(
                host: service.host,
                port: service.port,
                txt: service.txt,
                name: service.name,
              ));
            }
          });

          for (final s in discovery?.services ?? <nsd.Service>[]) {
            if (!controller.isClosed) {
              controller.add(DiscoveredService(
                host: s.host,
                port: s.port,
                txt: s.txt,
                name: s.name,
              ));
            }
          }
        } catch (e) {
          if (!controller.isClosed) {
            controller.addError(e);
          }
        }
      },
      onCancel: () async {
        if (discovery != null) {
          try {
            await nsd.stopDiscovery(discovery!);
          } catch (_) {}
        }
      },
    );

    return controller.stream;
  }
}
