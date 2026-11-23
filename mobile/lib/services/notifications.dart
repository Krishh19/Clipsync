import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationsService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String channelId = 'clipsync_channel';
  static const String channelName = 'ClipSync Notifications';
  static const String channelDescription = 'ClipSync incoming content notifications';

  /// Hook for testing notification dispatch without Android OS
  static void Function(int id, String title, String? body, String? payload)?
      onNotificationShownForTest;

  static Future<void> initialize({
    void Function(NotificationResponse response)? onNotificationTapped,
  }) async {
    const androidInitSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInitSettings);

    await _notificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: onNotificationTapped,
    );
  }

  static Future<void> showTextReceived({
    required int id,
    required String senderName,
    required String text,
  }) async {
    final preview = text.length > 80 ? '${text.substring(0, 80)}...' : text;
    onNotificationShownForTest?.call(id, 'From $senderName', preview, text);

    const androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('copy_action', 'Copy', showsUserInterface: false),
      ],
    );

    const details = NotificationDetails(android: androidDetails);
    try {
      await _notificationsPlugin.show(
        id: id,
        title: 'From $senderName',
        body: preview,
        notificationDetails: details,
        payload: text,
      );
    } catch (_) {
      // In test or headless environment without native notification manager
    }
  }

  static Future<void> showFileOffer({
    required int id,
    required String senderName,
    required String fileName,
    required String fileId,
    int? size,
  }) async {
    final payload = '$fileId|$fileName';
    onNotificationShownForTest?.call(id, 'From $senderName offered file', fileName, payload);

    const androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('download_action', 'Download', showsUserInterface: true),
      ],
    );

    const details = NotificationDetails(android: androidDetails);
    try {
      await _notificationsPlugin.show(
        id: id,
        title: 'From $senderName offered file',
        body: fileName,
        notificationDetails: details,
        payload: payload,
      );
    } catch (_) {
      // In test or headless environment without native notification manager
    }
  }
}
