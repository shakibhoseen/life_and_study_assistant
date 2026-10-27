import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../notification/notification_service.dart';
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
        // Initialize notifications and check Wi-Fi in background
        await NotificationService.instance.init();
        await WifiMonitorService.instance.checkCurrentWifiStatus();
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

      // Register periodic watchdog check (every 15 mins minimum by Android WorkManager)
      await Workmanager().registerPeriodicTask(
        'periodic-wifi-watchdog',
        backgroundTaskWifiCheck,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (e) {
      debugPrint('Error initializing Workmanager: $e');
    }
  }
}
