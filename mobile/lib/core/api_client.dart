import 'dart:io';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'pinned_client.dart';

class ApiClient {
  final Dio dio;

  ApiClient({required this.dio});

  factory ApiClient.fromConfig({
    required String host,
    required int port,
    required String fingerprint,
    String? deviceSecret,
  }) {
    final baseUrl = 'https://$host:$port/api/v1';
    final dio = PinnedClient.createDio(
      baseUrl: baseUrl,
      expectedFingerprint: fingerprint,
      bearerToken: deviceSecret,
    );
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
    final id = clientId ?? const Uuid().v4();
    final encodedFileName = Uri.encodeComponent(fileName);

    final response = await dio.post<Map<String, dynamic>>(
      '/file',
      data: file.openRead(),
      options: Options(
        headers: {
          HttpHeaders.contentLengthHeader: length,
          HttpHeaders.contentTypeHeader: mimeType ?? 'application/octet-stream',
          'X-File-Name': encodedFileName,
          'X-Client-Id': id,
        },
      ),
      onSendProgress: onProgress,
    );

    return response.data ?? {};
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
