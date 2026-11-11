import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../config/notification_constants.dart';
import '../notification/notification_service.dart';
import 'office_sentinel_service.dart';
import 'wifi_monitor_service.dart';

const String backgroundTaskWifiCheck =
    'com.example.life_and_study_assistant.wifi_check';
const String backgroundTaskDailyMeal =
    'com.example.life_and_study_assistant.daily_meal';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('Native background WorkManager task triggered: $task');

    switch (task) {
      case backgroundTaskWifiCheck:
        // Initialize notifications and check Wi-Fi & attendance cutoff in background
        await NotificationService.instance.init();
        await WifiMonitorService.instance.checkCurrentWifiStatus();
        await WifiMonitorService.instance.checkLateCutoffWarning();
        await OfficeSentinelService.instance.init();
        await OfficeSentinelService.instance.checkAndTriggerSentinelIfNeeded();
        break;

      case backgroundTaskDailyMeal:
        await NotificationService.instance.init();
        await NotificationService.instance.scheduleDailyDinnerReminder();
        break;
    }

    return Future.value(true);
  });
}

class WorkmanagerService {
  WorkmanagerService._();
  static final WorkmanagerService instance = WorkmanagerService._();

  Future<void> init() async {
    try {
      await Workmanager().initialize(callbackDispatcher);
      await syncWatchdogWithPrefs();
    } catch (e) {
      debugPrint('Error initializing Workmanager: $e');
    }
  }

  /// Syncs background task registration with user settings preferences.
  /// If all office background automations are disabled, the task is completely removed from Android OS JobScheduler.
  Future<void> syncWatchdogWithPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoIn =
          prefs.getBool(NotificationConstants.prefAutoCheckInEnabled) ?? true;
      final lateWarn =
          prefs.getBool(NotificationConstants.prefLateWarningEnabled) ?? true;
      final autoOut =
          prefs.getBool(NotificationConstants.prefAutoCheckOutEnabled) ?? true;

      if (!autoIn && !lateWarn && !autoOut) {
        debugPrint(
          'Workmanager: All office background automations disabled by user. Cancelling periodic task.',
        );
        await cancelWifiWatchdog();
      } else {
        await registerWifiWatchdog();
      }
    } catch (e) {
      debugPrint('Error syncing watchdog with prefs: $e');
    }
  }

  /// Registers the 15-minute periodic watchdog task in Android WorkManager / JobScheduler
  Future<void> registerWifiWatchdog() async {
    try {
      await Workmanager().registerPeriodicTask(
        'periodic-wifi-watchdog',
        backgroundTaskWifiCheck,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(networkType: NetworkType.connected),
      );
      debugPrint('Workmanager: periodic-wifi-watchdog registered.');
    } catch (e) {
      debugPrint('Workmanager: failed to register periodic-wifi-watchdog: $e');
    }
  }

  /// Completely cancels the periodic watchdog task from Android WorkManager / OS scheduler
  Future<void> cancelWifiWatchdog() async {
    try {
      await Workmanager().cancelByUniqueName('periodic-wifi-watchdog');
      debugPrint('Workmanager: periodic-wifi-watchdog cancelled from OS scheduler.');
    } catch (e) {
      debugPrint('Workmanager: failed to cancel periodic-wifi-watchdog: $e');
    }
  }

  /// Schedules a 15-minute fail-safe one-off task in WorkManager.
  /// If the foreground sentinel is killed by the user or OS while attendance is pending,
  /// this safety task wakes up, checks status, and revives the sentinel.
  Future<void> scheduleSafetyWatchdog({Duration delay = const Duration(minutes: 15)}) async {
    try {
      await Workmanager().registerOneOffTask(
        'sentinel-failsafe-watchdog',
        backgroundTaskWifiCheck,
        initialDelay: delay,
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      debugPrint('Workmanager: 15-minute fail-safe safety watchdog scheduled.');
    } catch (e) {
      debugPrint('Workmanager: scheduleSafetyWatchdog error: $e');
    }
  }

  /// Cancels all background tasks registered in WorkManager
  Future<void> cancelAll() async {
    try {
      await Workmanager().cancelAll();
      debugPrint('Workmanager: all background tasks cancelled.');
    } catch (e) {
      debugPrint('Workmanager: failed to cancelAll: $e');
    }
  }
}
