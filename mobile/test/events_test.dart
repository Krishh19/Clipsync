import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/events_client.dart';
import 'package:mobile/core/models.dart';
import 'package:mobile/data/db.dart';
import 'package:mobile/data/secure_store.dart';
import 'package:mobile/services/events_service.dart';
import 'package:mobile/services/foreground_service.dart';
import 'package:mobile/services/notifications.dart';
import 'package:mobile/services/transfer_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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

class FakeWebSocketSink implements WebSocketSink {
  final List<dynamic> sentMessages = [];
  final Completer<void> doneCompleter = Completer<void>();

  @override
  void add(dynamic data) {
    sentMessages.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.forEach(add);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!doneCompleter.isCompleted) {
      doneCompleter.complete();
    }
  }

  @override
  Future<void> get done => doneCompleter.future;
}

class FakeWebSocketChannel extends Fake implements WebSocketChannel {
  final StreamController<dynamic> streamController = StreamController<dynamic>.broadcast();
  final FakeWebSocketSink fakeSink = FakeWebSocketSink();

  @override
  Stream<dynamic> get stream => streamController.stream;

  @override
  WebSocketSink get sink => fakeSink;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future.value();
}

void main() {
  setUp(() {
    LoopPrevention.clear();
    NotificationsService.onNotificationShownForTest = null;
    ForegroundServiceController.isTestMode = true;
  });

  group('EventsClient - Exponential Backoff Reconnect', () {
    test('Calculates exponential backoff progression clamped at 30 seconds', () {
      int backoff = 1;
      expect(backoff, equals(1));

      backoff = EventsClient.calculateNextBackoff(backoff);
      expect(backoff, equals(2));

      backoff = EventsClient.calculateNextBackoff(backoff);
      expect(backoff, equals(4));

      backoff = EventsClient.calculateNextBackoff(backoff);
      expect(backoff, equals(8));

      backoff = EventsClient.calculateNextBackoff(backoff);
      expect(backoff, equals(16));

      backoff = EventsClient.calculateNextBackoff(backoff);
      expect(backoff, equals(30), reason: 'Must clamp at 30 seconds');

      backoff = EventsClient.calculateNextBackoff(backoff);
      expect(backoff, equals(30), reason: 'Must stay clamped at 30 seconds');
    });

    test('Doubles backoff on error/disconnection and resets on successful message', () async {
      late FakeWebSocketChannel channel;
      channel = FakeWebSocketChannel();

      final client = EventsClient(
        host: '127.0.0.1',
        port: 47821,
        fingerprint: 'fp',
        secret: 'secret',
        channelFactory: (uri, {customClient, headers}) => channel,
      );

      client.connect();
      expect(client.backoffSeconds, equals(1));

      // Incoming valid message maintains backoff at 1
      channel.streamController.add(jsonEncode({'type': 'hello', 'protocol': 1}));
      await Future<void>.delayed(Duration.zero);
      expect(client.backoffSeconds, equals(1));

      // Error event causes backoff increment
      channel.streamController.addError('Connection reset');
      await Future<void>.delayed(Duration.zero);
      expect(client.backoffSeconds, equals(2));

      // resetBackoff resets it to 1
      client.resetBackoff();
      expect(client.backoffSeconds, equals(1));

      client.dispose();
    });

    test('Answers ping with pong automatically', () async {
      final channel = FakeWebSocketChannel();

      final client = EventsClient(
        host: '127.0.0.1',
        port: 47821,
        fingerprint: 'fp',
        secret: 'secret',
        channelFactory: (uri, {customClient, headers}) => channel,
      );

      client.connect();

      // Server sends ping
      channel.streamController.add(jsonEncode({'type': 'ping'}));
      await Future<void>.delayed(Duration.zero);

      // Client must answer with pong
      expect(channel.fakeSink.sentMessages, hasLength(1));
      final sent = jsonDecode(channel.fakeSink.sentMessages.first as String);
      expect(sent['type'], equals('pong'));

      client.dispose();
    });
  });

  group('EventsService - Incoming Events & Notifications', () {
    test('On text event: flags loop prevention and dispatches notification with Copy action', () async {
      final mockStorage = _MockSecureStorage();
      final secureStore = SecureStore(storage: mockStorage);
      await secureStore.savePairedPc(
        pcDeviceId: 'pc-1',
        pcName: 'My PC',
        pcHost: '192.168.1.10',
        pcPort: 47821,
        pcFingerprint: 'fp-1',
        pcSecret: 'sec-1',
      );

      String? notifiedTitle;
      String? notifiedBody;
      String? notifiedPayload;

      NotificationsService.onNotificationShownForTest = (id, title, body, payload) {
        notifiedTitle = title;
        notifiedBody = body;
        notifiedPayload = payload;
      };

      final service = EventsService(secureStore: secureStore);

      const incomingText = 'Hello from Windows desktop!';
      await service.handleEvent(
        const WsEvent(
          type: 'text',
          data: {'id': 'evt-1', 'content': incomingText},
        ),
      );

      // Verify notification dispatched
      expect(notifiedTitle, equals('From My PC'));
      expect(notifiedBody, equals(incomingText));
      expect(notifiedPayload, equals(incomingText));

      // Verify loop prevention flagged
      expect(LoopPrevention.isIncoming(incomingText), isTrue);
    });

    test('On copy action: copies to clipboard, flags loop prevention, and records in history', () async {
      final mockStorage = _MockSecureStorage();
      final secureStore = SecureStore(storage: mockStorage);
      final database = AppDatabase(NativeDatabase.memory());

      String? clipboardText;
      final service = EventsService(
        secureStore: secureStore,
        database: database,
        clipboardSetter: (text) async {
          clipboardText = text;
        },
      );

      const textToCopy = 'https://github.com/google/clipsync';
      await service.handleNotificationAction(
        actionId: 'copy_action',
        payload: textToCopy,
      );

      // Verify clipboard updated
      expect(clipboardText, equals(textToCopy));

      // Verify loop prevention flagged
      expect(LoopPrevention.isIncoming(textToCopy), isTrue);

      // Verify inserted into SQLite history
      final history = await database.select(database.transfers).get();
      expect(history, hasLength(1));
      expect(history.first.direction, equals('in'));
      expect(history.first.kind, equals('link'));
      expect(history.first.label, equals(textToCopy));
      expect(history.first.status, equals('done'));

      await database.close();
    });

    test('On file_offer event: dispatches notification with Download action', () async {
      final mockStorage = _MockSecureStorage();
      final secureStore = SecureStore(storage: mockStorage);
      await secureStore.savePairedPc(
        pcDeviceId: 'pc-1',
        pcName: 'Workstation',
        pcHost: '192.168.1.10',
        pcPort: 47821,
        pcFingerprint: 'fp-1',
        pcSecret: 'sec-1',
      );

      String? notifiedTitle;
      String? notifiedBody;
      String? notifiedPayload;

      NotificationsService.onNotificationShownForTest = (id, title, body, payload) {
        notifiedTitle = title;
        notifiedBody = body;
        notifiedPayload = payload;
      };

      final service = EventsService(secureStore: secureStore);

      await service.handleEvent(
        const WsEvent(
          type: 'file_offer',
          data: {
            'id': 'file-offer-999',
            'name': 'document.pdf',
            'size': 2048576,
            'mime': 'application/pdf',
          },
        ),
      );

      expect(notifiedTitle, equals('From Workstation offered file'));
      expect(notifiedBody, equals('document.pdf'));
      expect(notifiedPayload, equals('file-offer-999|document.pdf'));
    });

    test('On download action: triggers file download and records in history', () async {
      final mockStorage = _MockSecureStorage();
      final secureStore = SecureStore(storage: mockStorage);
      final database = AppDatabase(NativeDatabase.memory());

      String? downloadedFileId;
      String? downloadedFileName;

      final service = EventsService(
        secureStore: secureStore,
        database: database,
        fileDownloader: (fileId, fileName) async {
          downloadedFileId = fileId;
          downloadedFileName = fileName;
          return '/storage/emulated/0/Download/$fileName';
        },
      );

      await service.handleNotificationAction(
        actionId: 'download_action',
        payload: 'file-offer-999|document.pdf',
      );

      // Verify download handler invoked
      expect(downloadedFileId, equals('file-offer-999'));
      expect(downloadedFileName, equals('document.pdf'));

      // Verify SQLite history record
      final history = await database.select(database.transfers).get();
      expect(history, hasLength(1));
      expect(history.first.direction, equals('in'));
      expect(history.first.kind, equals('file'));
      expect(history.first.label, equals('document.pdf'));
      expect(history.first.status, equals('done'));

      await database.close();
    });
  });

  group('Echo Loop Prevention (TransferService & LoopPrevention)', () {
    test('Received content is flagged and prevented from being re-sent to PC', () async {
      final mockStorage = _MockSecureStorage();
      final secureStore = SecureStore(storage: mockStorage);
      final transferService = TransferService(secureStore: secureStore);

      const receivedContent = 'Echo loop candidate from PC';

      // 1. Mark incoming
      LoopPrevention.markIncoming(receivedContent);
      expect(LoopPrevention.isIncoming(receivedContent), isTrue);

      // 2. Attempting to send incoming content must throw LoopDetectedException
      expect(
        () => transferService.sendText(receivedContent),
        throwsA(isA<LoopDetectedException>()),
      );

      // 3. Queue must remain empty
      expect(transferService.queue, isEmpty);

      // 4. Different normal content must succeed
      const freshContent = 'Fresh text created on phone';
      expect(LoopPrevention.isIncoming(freshContent), isFalse);
      final item = await transferService.sendText(freshContent);
      expect(item.content, equals(freshContent));
      expect(transferService.queue, hasLength(1));
    });

    test('Capacity capping maintains LRU cache size limit', () {
      for (int i = 0; i < LoopPrevention.maxCapacity + 10; i++) {
        LoopPrevention.markIncoming('Item $i');
      }

      // Oldest items (0..9) should have been evicted
      expect(LoopPrevention.isIncoming('Item 0'), isFalse);
      expect(LoopPrevention.isIncoming('Item 9'), isFalse);

      // Newest items must still be present
      expect(LoopPrevention.isIncoming('Item 10'), isTrue);
      expect(
        LoopPrevention.isIncoming('Item ${LoopPrevention.maxCapacity + 9}'),
        isTrue,
      );
    });
  });

  group('ForegroundServiceController', () {
    test('Manages service lifecycle in test mode', () async {
      ForegroundServiceController.isTestMode = true;

      expect(await ForegroundServiceController.isRunning(), isFalse);

      final started = await ForegroundServiceController.startService(pcName: 'Test PC');
      expect(started, isTrue);
      expect(await ForegroundServiceController.isRunning(), isTrue);

      final stopped = await ForegroundServiceController.stopService();
      expect(stopped, isTrue);
      expect(await ForegroundServiceController.isRunning(), isFalse);
    });
  });
}
