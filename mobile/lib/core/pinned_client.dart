import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Factory for certificate-pinned HttpClient and Dio instances
class PinnedClient {
  /// Builds a raw [HttpClient] that verifies the server's DER certificate SHA-256 fingerprint.
  static HttpClient createHttpClient(String expectedFingerprint) {
    final client = HttpClient(
      context: SecurityContext(withTrustedRoots: false),
    );
    final normalizedExpected =
        expectedFingerprint.replaceAll(':', '').replaceAll(' ', '').toLowerCase();

    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
      final certDer = cert.der;
      final digest = sha256.convert(certDer);
      final actualFingerprint = digest.toString().toLowerCase();
      return actualFingerprint == normalizedExpected;
    };

    return client;
  }

  /// Builds a [Dio] instance configured with certificate pinning and optional bearer auth.
  static Dio createDio({
    required String baseUrl,
    required String expectedFingerprint,
    String? bearerToken,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 30),
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        headers: {
          if (bearerToken != null && bearerToken.isNotEmpty)
            'Authorization': 'Bearer $bearerToken',
        },
      ),
    );

    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => createHttpClient(expectedFingerprint),
    );

    return dio;
  }
}
