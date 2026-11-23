import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile/core/models.dart';
import 'package:mobile/data/secure_store.dart';
import 'package:mobile/features/share_receiver/share_receiver_screen.dart';
import 'package:mobile/services/transfer_service.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class _MockTransferService extends TransferService {
  final List<String> sentTexts = [];
  final List<String> sentFiles = [];
  bool shouldFail = false;
  String failMessage = 'Simulated network failure';

  _MockTransferService() : super(secureStore: SecureStore());

  @override
  Future<TransferItem> sendText(String content, {String kind = 'text'}) async {
    if (shouldFail) {
      throw Exception(failMessage);
    }
    sentTexts.add(content);
    return TransferItem(
      id: 'mock-text-id',
      direction: 'out',
      kind: kind,
      label: content,
      size: content.length,
      status: 'done',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<TransferItem> sendFile(File file, {String? fileName}) async {
    if (shouldFail) {
      throw Exception(failMessage);
    }
    sentFiles.add(fileName ?? file.path);
    final size = await file.length();
    return TransferItem(
      id: 'mock-file-id',
      direction: 'out',
      kind: 'file',
      label: fileName ?? file.path,
      size: size,
      status: 'done',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

void main() {
  group('ShareReceiverScreen Widget Tests', () {
    testWidgets('shows progress indicator and item name while transferring', (tester) async {
      final mockService = _MockTransferService();
      final sharedFiles = [
        SharedMediaFile(
          path: 'https://example.com/clipsync',
          type: SharedMediaType.url,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShareReceiverScreen(
              sharedFiles: sharedFiles,
              transferService: mockService,
              autoCloseDuration: const Duration(seconds: 10),
            ),
          ),
        ),
      );

      // Verify header and item label rendered
      expect(find.text('Sending to PC (1 of 1)'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('shows success checkmark and auto-dismisses', (tester) async {
      final mockService = _MockTransferService();
      bool closed = false;

      final sharedFiles = [
        SharedMediaFile(
          path: 'Hello from shared text',
          type: SharedMediaType.text,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShareReceiverScreen(
              sharedFiles: sharedFiles,
              transferService: mockService,
              onClose: () => closed = true,
              autoCloseDuration: const Duration(milliseconds: 300),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // After transfer finishes, success checkmark should display
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('Sent!'), findsOneWidget);
      expect(mockService.sentTexts, contains('Hello from shared text'));

      // Advance clock past autoCloseDuration (300ms)
      await tester.pump(const Duration(milliseconds: 350));
      expect(closed, isTrue);
    });

    testWidgets('handles multiple items sequentially', (tester) async {
      final mockService = _MockTransferService();

      final sharedFiles = [
        SharedMediaFile(path: 'Item 1 Text', type: SharedMediaType.text),
        SharedMediaFile(path: 'Item 2 Text', type: SharedMediaType.text),
        SharedMediaFile(path: 'https://clipsync.app', type: SharedMediaType.url),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShareReceiverScreen(
              sharedFiles: sharedFiles,
              transferService: mockService,
              autoCloseDuration: const Duration(seconds: 10),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('All 3 items sent!'), findsOneWidget);
      expect(mockService.sentTexts.length, equals(3));
      expect(mockService.sentTexts[0], equals('Item 1 Text'));
      expect(mockService.sentTexts[1], equals('Item 2 Text'));
      expect(mockService.sentTexts[2], equals('https://clipsync.app'));
    });

    testWidgets('rejects file > 50 MB with error message and Retry/Close buttons', (tester) async {
      final mockService = _MockTransferService();
      final tempDir = Directory.systemTemp.createTempSync('clipsync_m3_test_');
      final largeFile = File('${tempDir.path}/huge_video.mp4');

      // Create a 51 MB file instantly via truncateSync
      final raf = largeFile.openSync(mode: FileMode.write);
      raf.truncateSync(51 * 1024 * 1024);
      raf.closeSync();

      final sharedFiles = [
        SharedMediaFile(path: largeFile.path, type: SharedMediaType.video),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShareReceiverScreen(
              sharedFiles: sharedFiles,
              transferService: mockService,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Must display error icon, 50 MB rejection message, and buttons
      expect(find.byIcon(Icons.error), findsOneWidget);
      expect(find.textContaining('exceeds 50 MB limit'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      // Verify file was never sent
      expect(mockService.sentFiles, isEmpty);

      tempDir.deleteSync(recursive: true);
    });

    testWidgets('shows failure state on network error with Retry and Close actions', (tester) async {
      final mockService = _MockTransferService();
      mockService.shouldFail = true;
      mockService.failMessage = 'Host 192.168.1.100 unreachable';

      bool closed = false;
      final sharedFiles = [
        SharedMediaFile(path: 'Failing Text', type: SharedMediaType.text),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShareReceiverScreen(
              sharedFiles: sharedFiles,
              transferService: mockService,
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.error), findsOneWidget);
      expect(find.text('Host 192.168.1.100 unreachable'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      // Tap Close button
      await tester.tap(find.text('Close'));
      await tester.pump();
      expect(closed, isTrue);

      // Now test Retry button
      mockService.shouldFail = false;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('Sent!'), findsOneWidget);
      expect(mockService.sentTexts, contains('Failing Text'));
    });
  });

  group('Manifest and Native Kotlin Verification', () {
    test('AndroidManifest.xml contains required intent filters and activities', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue);
      final content = manifestFile.readAsStringSync();

      expect(content, contains('android.intent.action.SEND'));
      expect(content, contains('android.intent.action.SEND_MULTIPLE'));
      expect(content, contains('android:mimeType="text/plain"'));
      expect(content, contains('android:mimeType="image/*"'));
      expect(content, contains('android:mimeType="video/*"'));
      expect(content, contains('android:mimeType="*/*"'));

      expect(content, contains('.QuickSendActivity'));
      expect(content, contains('.ClipboardTileService'));
      expect(content, contains('android.service.quicksettings.action.QS_TILE'));
      expect(content, contains('android.permission.BIND_QUICK_SETTINGS_TILE'));
    });

    test('QuickSendActivity.kt reads primary clip and relaunches MainActivity', () {
      final file = File('android/app/src/main/kotlin/com/clipsync/mobile/QuickSendActivity.kt');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(content, contains('onWindowFocusChanged'));
      expect(content, contains('ClipboardManager'));
      expect(content, contains('primaryClip'));
      expect(content, contains('Intent.ACTION_SEND'));
      expect(content, contains('MainActivity::class.java'));
      expect(content, contains('finish()'));
    });

    test('ClipboardTileService.kt launches QuickSendActivity with PendingIntent on API 34+', () {
      final file = File('android/app/src/main/kotlin/com/clipsync/mobile/ClipboardTileService.kt');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(content, contains('TileService'));
      expect(content, contains('QuickSendActivity::class.java'));
      expect(content, contains('PendingIntent.getActivity'));
      expect(content, contains('startActivityAndCollapse'));
      expect(content, contains('Build.VERSION_CODES.UPSIDE_DOWN_CAKE'));
    });
  });
}
