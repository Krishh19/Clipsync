import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/api_client.dart';
import 'package:mobile/services/transfer_service.dart';

void main() {
  group('TransferService Retry Policy', () {
    test('succeeds immediately on first attempt without retrying', () async {
      int calls = 0;
      final result = await TransferService.executeWithRetry(() async {
        calls++;
        return 'success';
      }, baseDelay: const Duration(milliseconds: 10));

      expect(result, equals('success'));
      expect(calls, equals(1));
    });

    test('retries network error and succeeds on 2nd attempt', () async {
      int calls = 0;
      final result = await TransferService.executeWithRetry(() async {
        calls++;
        if (calls == 1) {
          throw DioException(
            requestOptions: RequestOptions(path: '/text'),
            type: DioExceptionType.connectionError,
            error: 'Network connection refused',
          );
        }
        return 'recovered';
      }, baseDelay: const Duration(milliseconds: 10));

      expect(result, equals('recovered'));
      expect(calls, equals(2));
    });

    test('retries network error and succeeds on 3rd attempt (maxAttempts = 3)', () async {
      int calls = 0;
      final result = await TransferService.executeWithRetry(() async {
        calls++;
        if (calls < 3) {
          throw DioException(
            requestOptions: RequestOptions(path: '/file'),
            type: DioExceptionType.connectionTimeout,
            error: 'Timeout connecting to PC',
          );
        }
        return 'recovered on 3rd';
      }, baseDelay: const Duration(milliseconds: 10));

      expect(result, equals('recovered on 3rd'));
      expect(calls, equals(3));
    });

    test('fails after 3 attempts on continuous network errors', () async {
      int calls = 0;
      expect(
        () => TransferService.executeWithRetry(() async {
          calls++;
          throw DioException(
            requestOptions: RequestOptions(path: '/file'),
            type: DioExceptionType.connectionError,
            error: 'Host unreachable',
          );
        }, maxAttempts: 3, baseDelay: const Duration(milliseconds: 10)),
        throwsA(isA<DioException>()),
      );
      // Wait for attempts to complete
      await Future.delayed(const Duration(milliseconds: 100));
      expect(calls, equals(3));
    });

    test('never retries on 4xx client errors (e.g. 401 Unauthorized)', () async {
      int calls = 0;
      expect(
        () => TransferService.executeWithRetry(() async {
          calls++;
          throw DioException(
            requestOptions: RequestOptions(path: '/text'),
            response: Response(
              requestOptions: RequestOptions(path: '/text'),
              statusCode: 401,
              statusMessage: 'Unauthorized',
            ),
            type: DioExceptionType.badResponse,
          );
        }, baseDelay: const Duration(milliseconds: 10)),
        throwsA(predicate((e) => e is DioException && e.response?.statusCode == 401)),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      // Should NOT retry: called exactly once
      expect(calls, equals(1));
    });

    test('never retries on 413 Payload Too Large', () async {
      int calls = 0;
      expect(
        () => TransferService.executeWithRetry(() async {
          calls++;
          throw DioException(
            requestOptions: RequestOptions(path: '/file'),
            response: Response(
              requestOptions: RequestOptions(path: '/file'),
              statusCode: 413,
              statusMessage: 'Payload Too Large',
            ),
            type: DioExceptionType.badResponse,
          );
        }, baseDelay: const Duration(milliseconds: 10)),
        throwsA(predicate((e) => e is DioException && e.response?.statusCode == 413)),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      // Must not retry
      expect(calls, equals(1));
    });

    test('never retries on 400 Bad Request', () async {
      int calls = 0;
      expect(
        () => TransferService.executeWithRetry(() async {
          calls++;
          throw DioException(
            requestOptions: RequestOptions(path: '/text'),
            response: Response(
              requestOptions: RequestOptions(path: '/text'),
              statusCode: 400,
              statusMessage: 'Bad Request',
            ),
            type: DioExceptionType.badResponse,
          );
        }, baseDelay: const Duration(milliseconds: 10)),
        throwsA(predicate((e) => e is DioException && e.response?.statusCode == 400)),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(calls, equals(1));
    });
  });

  group('Client-Side Limit Enforcement', () {
    test('sendText rejects text > 1 MB before sending', () async {
      final client = ApiClient(dio: Dio());
      // Generate string slightly exceeding 1 MB (1,048,576 bytes)
      final hugeString = 'A' * (1024 * 1024 + 1);

      expect(
        () => client.sendText(content: hugeString),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('sendFile rejects file > 50 MB before sending', () async {
      final client = ApiClient(dio: Dio());
      // Create a temporary file and mock or set its length > 50 MB
      final tempDir = Directory.systemTemp.createTempSync('clipsync_test_');
      final testFile = File('${tempDir.path}/large.dat');
      // Create a file with sparse/dummy or simulated length check
      // For testing, write 100 bytes first
      testFile.writeAsBytesSync(List.filled(100, 0));

      // File under limit should not throw size ArgumentError (though network might fail)
      // Now test with file > 50 MB:
      final fakeLargeFile = _FakeLargeFile(testFile.path, 50 * 1024 * 1024 + 1);

      expect(
        () => client.sendFile(file: fakeLargeFile, fileName: 'large.dat'),
        throwsA(isA<ArgumentError>()),
      );

      tempDir.deleteSync(recursive: true);
    });
  });

  group('MIME Type Inference', () {
    test('correctly infers image types', () {
      expect(ApiClient.inferMimeType('photo.png'), equals('image/png'));
      expect(ApiClient.inferMimeType('photo.jpg'), equals('image/jpeg'));
      expect(ApiClient.inferMimeType('photo.jpeg'), equals('image/jpeg'));
      expect(ApiClient.inferMimeType('anim.gif'), equals('image/gif'));
      expect(ApiClient.inferMimeType('photo.webp'), equals('image/webp'));
    });

    test('correctly infers video types', () {
      expect(ApiClient.inferMimeType('clip.mp4'), equals('video/mp4'));
      expect(ApiClient.inferMimeType('clip.mov'), equals('video/quicktime'));
      expect(ApiClient.inferMimeType('clip.mkv'), equals('video/x-matroska'));
      expect(ApiClient.inferMimeType('clip.webm'), equals('video/webm'));
    });

    test('falls back to octet-stream for generic types', () {
      expect(ApiClient.inferMimeType('data.bin'), equals('application/octet-stream'));
    });
  });
}

class _FakeLargeFile implements File {
  final String _path;
  final int _fakeLength;

  _FakeLargeFile(this._path, this._fakeLength);

  @override
  String get path => _path;

  @override
  Future<int> length() async => _fakeLength;

  @override
  int lengthSync() => _fakeLength;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
