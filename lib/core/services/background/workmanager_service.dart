import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../config/notification_constants.dart';
import '../home_widget_service.dart';
import '../study_widget_service.dart';
import '../../database/app_database.dart';
import '../notification/notification_service.dart';
import 'office_sentinel_service.dart';
import 'wifi_monitor_service.dart';

const String backgroundTaskWifiCheck =
    'com.example.life_and_study_assistant.wifi_check';
const String backgroundTaskDailyMeal =
    'com.example.life_and_study_assistant.daily_meal';
const String backgroundTaskWidgetSync =
    'com.example.life_and_study_assistant.widget_sync';
const String backgroundTaskStudyWidgetSync =
    'com.example.life_and_study_assistant.study_widget_sync';

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
        await NotificationService.instance.scheduleDailyLunchCutoffReminder();
        break;

      case backgroundTaskWidgetSync:
        await NotificationService.instance.init();
        await HomeWidgetService.syncCurrentDataToWidget(fetchFromNetwork: true);
        break;

      case backgroundTaskStudyWidgetSync:
        // Refreshing a study widget with the app closed. This isolate has no
        // provider scope, so it opens the database itself and closes it again
        // — the sync only reads, so sharing the file with a running app is
        // safe, and SQLite serialises the rest.
        final db = AppDatabase();
        try {
          await StudyWidgetService.syncStudyData(db);
        } finally {
          await db.close();
        }
        // Chain the next one from here rather than using a periodic task, so
        // it lands at a time of day rather than every N hours from whenever
        // the app happened to start.
        await WorkmanagerService.instance.scheduleDailyStudyRefresh();
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
  /// Eliminates 24/7 periodic polling to conserve 100% battery during midday and night.
  /// Tasks are only invoked dynamically in the 2 critical windows via Foreground Sentinel + chained fail-safe.
  Future<void> syncWatchdogWithPrefs() async {
    try {
      // Cancel legacy 24/7 periodic task permanently from OS scheduler
      await cancelWifiWatchdog();

      final prefs = await SharedPreferences.getInstance();
      final autoIn =
          prefs.getBool(NotificationConstants.prefAutoCheckInEnabled) ?? true;
      final lateWarn =
          prefs.getBool(NotificationConstants.prefLateWarningEnabled) ?? true;
      final autoOut =
          prefs.getBool(NotificationConstants.prefAutoCheckOutEnabled) ?? true;

      if (!autoIn && !lateWarn && !autoOut) {
        debugPrint(
          'Workmanager: All office background automations disabled by user. Cancelling safety watchdog.',
        );
        await cancelSafetyWatchdog();
      }
    } catch (e) {
      debugPrint('Error syncing watchdog with prefs: $e');
    }
  }

  /// Completely cancels the legacy periodic watchdog task from Android WorkManager / OS scheduler
  Future<void> cancelWifiWatchdog() async {
    try {
      await Workmanager().cancelByUniqueName('periodic-wifi-watchdog');
      debugPrint('Workmanager: periodic-wifi-watchdog cancelled from OS scheduler.');
    } catch (e) {
      debugPrint('Workmanager: failed to cancel periodic-wifi-watchdog: $e');
    }
  }

  /// Schedules a 15-minute fail-safe one-off task in WorkManager.
  /// The hour the study widgets roll over, local time.
  ///
  /// Early enough that the countdown and the question of the day have already
  /// changed before the phone is picked up, late enough not to be part of the
  /// midnight crowd of jobs every app on the device schedules.
  static const int dailyRefreshHour = 5;

  /// How long from [now] until the next [dailyRefreshHour].
  ///
  /// Pulled out because the edges are easy to get wrong: at exactly 5 AM the
  /// answer is tomorrow, not zero, and after 5 AM it has to cross midnight
  /// rather than going negative.
  @visibleForTesting
  static Duration delayUntilNextDailyRefresh(DateTime now) {
    var next = DateTime(now.year, now.month, now.day, dailyRefreshHour);
    if (!next.isAfter(now)) {
      next = DateTime(now.year, now.month, now.day + 1, dailyRefreshHour);
    }
    return next.difference(now);
  }

  /// Refreshes the study widgets once a day, in the background.
  ///
  /// Study figures move while the user is in the app, and the app already
  /// refreshes on launch and on resume, so nothing here needs to poll. What
  /// does need a nudge is the calendar turning over: "৩ দিন বাকি" becoming
  /// "২ দিন বাকি", and a new question for the day, neither of which should
  /// wait for the app to be opened.
  ///
  /// So: one deferrable WorkManager job a day. Not an exact alarm, which
  /// would wake the device, and not a periodic task, which cannot be aimed at
  /// a time of day. Android is free to batch it with other work and to hold
  /// it back in Doze — a date rollover arriving a little late is not worth a
  /// battery complaint.
  Future<void> scheduleDailyStudyRefresh() async {
    try {
      final delay = delayUntilNextDailyRefresh(DateTime.now());
      await Workmanager().registerOneOffTask(
        'study-widget-daily-refresh',
        backgroundTaskStudyWidgetSync,
        initialDelay: delay,
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      debugPrint(
        'Workmanager: study widget refresh in ${delay.inMinutes} minutes.',
      );
    } catch (e) {
      debugPrint('Workmanager: scheduleDailyStudyRefresh error: $e');
    }
  }

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

  /// Completely cancels the 15-minute fail-safe safety watchdog task from Android WorkManager.
  /// Called immediately once check-in or check-out is complete so zero tasks remain in OS queue.
  Future<void> cancelSafetyWatchdog() async {
    try {
      await Workmanager().cancelByUniqueName('sentinel-failsafe-watchdog');
      debugPrint('Workmanager: safety watchdog cancelled from OS scheduler.');
    } catch (e) {
      debugPrint('Workmanager: failed to cancel safety watchdog: $e');
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
