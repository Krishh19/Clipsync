import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Manages the Android foreground service per docs/SPEC.md Section 10:
/// Foreground service type `specialUse` with justification string,
/// keeping WebSocket connection alive to receive PC-to-phone events in background.
class ForegroundServiceController {
  static bool _initialized = false;
  static bool _isSimulatedRunning = false;

  /// Hook to override foreground task execution for tests/headless environments
  static bool isTestMode = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    if (isTestMode) {
      _initialized = true;
      return;
    }

    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'clipsync_foreground_channel',
          channelName: 'ClipSync Background Service',
          channelDescription:
              'Keeps ClipSync connected to PC for clipboard sync and transfers',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
      _initialized = true;
    } catch (_) {
      // Platform channel error in non-Android or testing environments
    }
  }

  /// Starts the foreground service with `specialUse` type
  static Future<bool> startService({String pcName = 'ClipSync PC'}) async {
    await initialize();
    if (isTestMode) {
      _isSimulatedRunning = true;
      return true;
    }

    try {
      if (await FlutterForegroundTask.isRunningService) {
        return true;
      }

      final result = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.specialUse],
        notificationTitle: 'ClipSync Active',
        notificationText: 'Connected to $pcName to receive clips and files',
        notificationIcon: null,
      );
      return result is ServiceRequestSuccess;
    } catch (_) {
      return false;
    }
  }

  /// Stops the foreground service
  static Future<bool> stopService() async {
    if (isTestMode) {
      _isSimulatedRunning = false;
      return true;
    }

    try {
      final result = await FlutterForegroundTask.stopService();
      return result is ServiceRequestSuccess;
    } catch (_) {
      return false;
    }
  }

  /// Returns whether the foreground service is active
  static Future<bool> isRunning() async {
    if (isTestMode) {
      return _isSimulatedRunning;
    }
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }
}
