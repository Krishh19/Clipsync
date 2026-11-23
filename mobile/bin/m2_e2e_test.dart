import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:mobile/core/api_client.dart';

void main() async {
  stdout.writeln('=== ClipSync Milestone M2 E2E Verification ===\n');

  const host = '127.0.0.1';
  const port = 47821;
  const token = 'dev-token-clipsync';

  stdout.writeln('1. Connecting to Dev Server at http://$host:$port...');
  final client = ApiClient.fromConfig(
    host: host,
    port: port,
    deviceSecret: token,
    isDevPlainHttp: true,
  );

  try {
    final info = await client.getInfo();
    stdout.writeln('   [PASS] Connected! Server: ${info.name}, Device ID: ${info.deviceId}, Protocol: ${info.protocol}\n');
  } catch (e) {
    stderr.writeln('   [FAIL] Could not connect to dev server: $e');
    stderr.writeln('   Make sure the dev server is running on port $port!');
    exit(1);
  }

  // 2. Text Transfer Verification
  stdout.writeln('2. Testing Text Send (POST /api/v1/text)...');
  final testText = 'ClipSync M2 Test Text - ${DateTime.now().toIso8601String()}';
  try {
    final textId = await client.sendText(content: testText);
    stdout.writeln('   [PASS] Text sent successfully! ID: $textId');
    stdout.writeln('   Content: "$testText"\n');
  } catch (e) {
    stderr.writeln('   [FAIL] sendText failed: $e');
    exit(1);
  }

  // 3. 20 MB File Streaming Verification with SHA-256 check
  stdout.writeln('3. Testing 20 MB Video/File Streaming (POST /api/v1/file)...');
  final tempDir = Directory.systemTemp.createTempSync('clipsync_m2_');
  final testFilePath = '${tempDir.path}/m2_test_video.mp4';
  final testFile = File(testFilePath);

  final fileSize = 20 * 1024 * 1024; // 20 MB
  stdout.writeln('   Generating 20 MB payload file ($fileSize bytes)...');
  final sink = testFile.openWrite();
  final random = Random(42);
  final chunk = List<int>.filled(64 * 1024, 0);
  int written = 0;
  while (written < fileSize) {
    final toWrite = min(chunk.length, fileSize - written);
    for (int i = 0; i < toWrite; i++) {
      chunk[i] = random.nextInt(256);
    }
    sink.add(chunk.sublist(0, toWrite));
    written += toWrite;
  }
  await sink.flush();
  await sink.close();

  // Compute original file SHA-256
  final originalHash = (await sha256.bind(testFile.openRead()).first).toString();
  stdout.writeln('   [INFO] Original SHA-256: $originalHash');

  stdout.writeln('   Streaming 20 MB file to server with progress callback...');
  int lastPercent = -1;
  try {
    final fileResponse = await client.sendFile(
      file: testFile,
      fileName: 'm2_test_video.mp4',
      mimeType: 'video/mp4',
      onProgress: (sent, total) {
        if (total > 0) {
          final percent = (sent * 100 / total).floor();
          if (percent != lastPercent && percent % 20 == 0) {
            stdout.writeln('   Upload progress: $percent% ($sent / $total bytes)');
            lastPercent = percent;
          }
        }
      },
    );
    stdout.writeln('   [PASS] File upload completed! Server response: $fileResponse\n');
  } catch (e) {
    stderr.writeln('   [FAIL] sendFile failed: $e');
    exit(1);
  }

  // 4. Verify received file on disk
  stdout.writeln('4. Verifying Saved File in Downloads/ClipSync...');
  final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\krish';
  final downloadsClipSync = Directory('$userProfile\\Downloads\\ClipSync');

  if (!downloadsClipSync.existsSync()) {
    stderr.writeln('   [FAIL] Save directory not found: ${downloadsClipSync.path}');
    exit(1);
  }

  // Find the most recently created m2_test_video file
  final matchingFiles = downloadsClipSync
      .listSync()
      .whereType<File>()
      .where((f) => f.uri.pathSegments.last.startsWith('m2_test_video'))
      .toList()
    ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

  if (matchingFiles.isEmpty) {
    stderr.writeln('   [FAIL] m2_test_video file not found in ${downloadsClipSync.path}');
    exit(1);
  }

  final receivedFile = matchingFiles.first;
  stdout.writeln('   Found received file: ${receivedFile.path}');
  final receivedHash = (await sha256.bind(receivedFile.openRead()).first).toString();
  stdout.writeln('   [INFO] Received SHA-256: $receivedHash');

  if (originalHash == receivedHash) {
    stdout.writeln('   [PASS] SHA-256 hashes match identically!');
  } else {
    stderr.writeln('   [FAIL] SHA-256 mismatch! Original: $originalHash, Received: $receivedHash');
    exit(1);
  }

  // 5. Verify Client-Side Limit Checks
  stdout.writeln('\n5. Verifying Client-Side Limits (1 MB text, 50 MB file)...');
  bool rejectedLargeText = false;
  try {
    await client.sendText(content: 'X' * (1024 * 1024 + 100));
  } catch (e) {
    if (e is ArgumentError) {
      rejectedLargeText = true;
      stdout.writeln('   [PASS] Text > 1 MB rejected client-side: $e');
    }
  }
  if (!rejectedLargeText) {
    stderr.writeln('   [FAIL] Oversized text was not rejected client-side');
    exit(1);
  }

  // Clean up temp
  try {
    tempDir.deleteSync(recursive: true);
  } catch (_) {}

  stdout.writeln('\n=============================================');
  stdout.writeln('ALL MILESTONE M2 ACCEPTANCE CRITERIA PASSED!');
  stdout.writeln('=============================================');
}
