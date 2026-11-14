import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../attendance/steadfast_lunch_service.dart';
import '../home_widget_service.dart';
import '../notification/notification_service.dart';
import 'wifi_monitor_service.dart';

@pragma('vm:entry-point')
void startLunchSentinelCallback() {
  FlutterForegroundTask.setTaskHandler(LunchSentinelTaskHandler());
}

class LunchSentinelTaskHandler extends TaskHandler {
  String? _lastNotifTitle;
  String? _lastNotifText;
  bool _isProcessing = false;

  void _updateForegroundNotification({
    required String title,
    required String text,
  }) {
    if (_lastNotifTitle == title && _lastNotifText == text) return;
    _lastNotifTitle = title;
    _lastNotifText = text;
    FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('LunchSentinelTaskHandler: started at $timestamp by ${starter.name}');
    await _checkLunchServingStatus();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _checkLunchServingStatus();
  }

  Future<void> _checkLunchServingStatus() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final now = DateTime.now();
      final today = now.toIso8601String().substring(0, 10);
      final prefs = await SharedPreferences.getInstance();

      // 1. Check if feature is enabled
      final isEnabled =
          prefs.getBool(NotificationConstants.prefLunchServingTrackingEnabled) ?? true;
      if (!isEnabled) {
        debugPrint('LunchSentinel: Disabled by user in settings. Stopping.');
        await FlutterForegroundTask.stopService();
        return;
      }

      // 2. Check window (12:20 PM - 1:45 PM)
      // Outside this window, terminate to preserve 100% battery
      final isLunchTime = (now.hour == 12 && now.minute >= 20) ||
          (now.hour == 13 && now.minute <= 45);
      if (!isLunchTime) {
        debugPrint('LunchSentinel: Outside lunch hours (${now.hour}:${now.minute}). Stopping.');
        await FlutterForegroundTask.stopService();
        return;
      }

      // 3. Check off-day or holiday
      final isClosed = await WifiMonitorService.instance.isOfficeClosedToday(now);
      if (isClosed) {
        debugPrint('LunchSentinel: Office closed today (off-day or holiday). Stopping.');
        await FlutterForegroundTask.stopService();
        return;
      }

      // 4. Query live serving status
      final serving = await SteadfastLunchService.instance.getServingStatus();
      if (serving == null) {
        debugPrint('LunchSentinel: Could not fetch serving status (network/auth). Retrying next tick.');
        return;
      }

      // If user did not book lunch today, no need to track
      if (!serving.booked) {
        debugPrint('LunchSentinel: Today is not booked for lunch. Stopping sentinel.');
        await FlutterForegroundTask.stopService();
        return;
      }

      final lastNotifiedDate =
          prefs.getString(NotificationConstants.prefLastNotifiedLunchStatusDate);
      final lastNotifiedStatus =
          prefs.getString(NotificationConstants.prefLastNotifiedLunchStatus);

      final statusKey = serving.status.toLowerCase();
      debugPrint('LunchSentinel: Current serving status: $statusKey (${serving.label})');

      // Update home screen widget
      await HomeWidgetService.updateWidget(lunchStatus: statusKey);

      // Update silent status bar notification
      _updateForegroundNotification(
        title: '🍱 Lunch Status: ${serving.bengaliStatusLabel}',
        text: serving.message.isNotEmpty
            ? serving.message
            : 'আজকের লাঞ্চের অবস্থা ট্র্যাক করা হচ্ছে...',
      );

      // 5. Trigger 'received' alert when car arrives at canteen
      if (serving.isReceived && !serving.isServed) {
        final alreadyNotifiedReceived =
            (lastNotifiedDate == today &&
             (lastNotifiedStatus == 'received' || lastNotifiedStatus == 'served'));
        if (!alreadyNotifiedReceived) {
          debugPrint('LunchSentinel: Food car arrived at office! Showing Received alert.');
          await prefs.setString(
            NotificationConstants.prefLastNotifiedLunchStatusDate,
            today,
          );
          await prefs.setString(
            NotificationConstants.prefLastNotifiedLunchStatus,
            'received',
          );
          await NotificationService.instance.showLunchReceivedNotification(
            time: serving.updatedAt,
            message: serving.message,
          );
        }
      }

      // 6. Trigger 'served' alert when food is ready to eat
      if (serving.isServed) {
        final alreadyNotifiedServed =
            (lastNotifiedDate == today && lastNotifiedStatus == 'served');
        if (!alreadyNotifiedServed) {
          debugPrint('LunchSentinel: Lunch is served! Showing Served alert.');
          await prefs.setString(
            NotificationConstants.prefLastNotifiedLunchStatusDate,
            today,
          );
          await prefs.setString(
            NotificationConstants.prefLastNotifiedLunchStatus,
            'served',
          );
          await NotificationService.instance.showLunchServedNotification(
            time: serving.updatedAt,
            message: serving.message,
          );
        }

        // GOAL ACHIEVED: Lunch is served! Auto-dismiss the service immediately!
        debugPrint('LunchSentinel: Lunch has been served! Goal achieved. Stopping sentinel.');
        await FlutterForegroundTask.stopService();
        return;
      }
    } catch (e) {
      debugPrint('LunchSentinel: Error checking serving status: $e');
    } finally {
      _isProcessing = false;
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('LunchSentinelTaskHandler: destroyed at $timestamp');
  }

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}
}

class LunchSentinelService {
  LunchSentinelService._();
  static final LunchSentinelService instance = LunchSentinelService._();

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: NotificationConstants.sentinelChannelId,
        channelName: NotificationConstants.sentinelChannelName,
        channelDescription: NotificationConstants.sentinelChannelDesc,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
        showBadge: false,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000), // check once every 60 seconds
        autoRunOnBoot: false,
        allowWakeLock: false,
        allowWifiLock: false,
      ),
    );
  }

  /// Starts the silent lunch serving sentinel
  Future<bool> startLunchSentinel() async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    final isEnabled =
        prefs.getBool(NotificationConstants.prefLunchServingTrackingEnabled) ?? true;
    if (!isEnabled) return false;

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastNotifiedDate =
        prefs.getString(NotificationConstants.prefLastNotifiedLunchStatusDate);
    final lastNotifiedStatus =
        prefs.getString(NotificationConstants.prefLastNotifiedLunchStatus);

    if (lastNotifiedDate == today && lastNotifiedStatus == 'served') {
      debugPrint('LunchSentinelService: Today lunch already served and notified. No sentinel needed.');
      return false;
    }

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) return true;

    final result = await FlutterForegroundTask.startService(
      serviceId: NotificationConstants.lunchServingSentinelServiceId,
      notificationTitle: '🍱 Steadfast Lunch Tracker Active',
      notificationText: 'Tracking food dispatch (Upcoming ➔ Received ➔ Served)...',
      callback: startLunchSentinelCallback,
    );
    debugPrint('LunchSentinelService: Started: $result');
    return true;
  }

  /// Manually stops the lunch serving sentinel
  Future<void> stopLunchSentinel() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      await FlutterForegroundTask.stopService();
      debugPrint('LunchSentinelService: Stopped.');
    }
  }

  /// Evaluates whether lunch sentinel should be triggered right now
  Future<void> checkAndTriggerLunchSentinelIfNeeded() async {
    final now = DateTime.now();
    final isLunchTime = (now.hour == 12 && now.minute >= 20) ||
        (now.hour == 13 && now.minute <= 45);
    if (!isLunchTime) return;

    final isClosed = await WifiMonitorService.instance.isOfficeClosedToday(now);
    if (isClosed) return;

    final prefs = await SharedPreferences.getInstance();
    final isEnabled =
        prefs.getBool(NotificationConstants.prefLunchServingTrackingEnabled) ?? true;
    if (!isEnabled) return;

    final today = now.toIso8601String().substring(0, 10);
    final lastNotifiedDate =
        prefs.getString(NotificationConstants.prefLastNotifiedLunchStatusDate);
    final lastNotifiedStatus =
        prefs.getString(NotificationConstants.prefLastNotifiedLunchStatus);
    if (lastNotifiedDate == today && lastNotifiedStatus == 'served') return;

    await startLunchSentinel();
  }
}
