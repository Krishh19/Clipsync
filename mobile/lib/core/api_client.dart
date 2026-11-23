import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'pinned_client.dart';

class ApiClient {
  static const int maxTextSizeBytes = 1024 * 1024; // 1 MB limit per SPEC
  static const int maxFileSizeBytes = 50 * 1024 * 1024; // 50 MB limit per SPEC

  final Dio dio;

  ApiClient({required this.dio});

  factory ApiClient.fromConfig({
    required String host,
    required int port,
    String? fingerprint,
    String? deviceSecret,
    bool isDevPlainHttp = false,
  }) {
    final scheme = isDevPlainHttp ? 'http' : 'https';
    final baseUrl = '$scheme://$host:$port/api/v1';
    final Dio dio;
    if (isDevPlainHttp || fingerprint == null || fingerprint.isEmpty || fingerprint == 'dev') {
      dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            if (deviceSecret != null && deviceSecret.isNotEmpty)
              'Authorization': 'Bearer $deviceSecret',
          },
        ),
      );
    } else {
      dio = PinnedClient.createDio(
        baseUrl: baseUrl,
        expectedFingerprint: fingerprint,
        bearerToken: deviceSecret,
      );
    }
    return ApiClient(dio: dio);
  }

  /// GET /api/v1/info
  Future<ServerInfo> getInfo() async {
    final response = await dio.get<Map<String, dynamic>>('/info');
    return ServerInfo.fromJson(response.data ?? {});
  }

  /// POST /api/v1/pair
  Future<PairResponse> pair({
    required String token,
    required String deviceId,
    required String deviceName,
    String platform = 'android',
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      '/pair',
      data: {
        'token': token,
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
      },
    );
    return PairResponse.fromJson(response.data ?? {});
  }

  /// DELETE /api/v1/pair
  Future<void> unpair() async {
    await dio.delete('/pair');
  }

  /// POST /api/v1/text
  Future<String> sendText({
    required String content,
    String kind = 'text',
    String? clientId,
  }) async {
    final bytes = utf8.encode(content);
    if (bytes.length > maxTextSizeBytes) {
      throw ArgumentError(
        'Text size (${bytes.length} bytes) exceeds maximum limit of 1 MB',
      );
    }
    final id = clientId ?? const Uuid().v4();
    final response = await dio.post<Map<String, dynamic>>(
      '/text',
      data: {
        'kind': kind,
        'content': content,
        'client_id': id,
      },
    );
    return response.data?['id'] as String? ?? id;
  }

  /// POST /api/v1/file
  Future<Map<String, dynamic>> sendFile({
    required File file,
    required String fileName,
    String? mimeType,
    String? clientId,
    void Function(int sent, int total)? onProgress,
  }) async {
    final length = await file.length();
    if (length > maxFileSizeBytes) {
      throw ArgumentError(
        'File size ($length bytes) exceeds maximum limit of 50 MB',
      );
    }
    final id = clientId ?? const Uuid().v4();
    final encodedFileName = Uri.encodeComponent(fileName);

    final response = await dio.post<Map<String, dynamic>>(
      '/file',
      data: file.openRead(),
      options: Options(
        headers: {
          HttpHeaders.contentLengthHeader: length,
          HttpHeaders.contentTypeHeader: mimeType ?? inferMimeType(fileName),
          'X-File-Name': encodedFileName,
          'X-Client-Id': id,
        },
      ),
      onSendProgress: onProgress,
    );

    return response.data ?? {};
  }

  static String inferMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  /// GET /api/v1/files/{id}
  Future<void> downloadFile({
    required String fileId,
    required String destinationPath,
    void Function(int received, int total)? onProgress,
  }) async {
    await dio.download(
      '/files/$fileId',
      destinationPath,
      onReceiveProgress: onProgress,
    );
  }
}
