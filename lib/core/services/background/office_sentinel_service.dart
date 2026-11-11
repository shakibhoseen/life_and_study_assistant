import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../attendance/packly_attendance_service.dart';
import '../notification/notification_service.dart';
import 'wifi_monitor_service.dart';

@pragma('vm:entry-point')
void startSentinelCallback() {
  FlutterForegroundTask.setTaskHandler(OfficeSentinelTaskHandler());
}

class OfficeSentinelTaskHandler extends TaskHandler {
  final NetworkInfo _networkInfo = NetworkInfo();
  final Connectivity _connectivity = Connectivity();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('OfficeSentinelTaskHandler: started at $timestamp by ${starter.name}');
    await _checkSentinelCondition();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _checkSentinelCondition();
  }

  Future<void> _checkSentinelCondition() async {
    final now = DateTime.now();
    final today = now.toIso8601String().substring(0, 10);
    final prefs = await SharedPreferences.getInstance();

    final lastCheckInDate = prefs.getString(NotificationConstants.prefLastCheckInDate);
    final lastCheckInStatus = prefs.getString(NotificationConstants.prefLastCheckInStatus);
    final isAlreadyCheckedIn = lastCheckInDate == today &&
        (lastCheckInStatus == 'Punched' || lastCheckInStatus == 'Punched In');

    final lastCheckOutDate = prefs.getString(NotificationConstants.prefLastCheckOutDate);
    final isAlreadyCheckedOut = lastCheckOutDate == today;

    // Check weekly off-day or holiday
    final isClosed = await WifiMonitorService.instance.isOfficeClosedToday(now);
    if (isClosed) {
      debugPrint('OfficeSentinel: Office is closed today. Stopping sentinel.');
      await FlutterForegroundTask.stopService();
      return;
    }

    // 1. MORNING CRITICAL WINDOW (8:45 AM - 9:30 AM): Active until checked in
    if (now.hour == 8 && now.minute >= 45 || now.hour == 9 && now.minute <= 30) {
      if (isAlreadyCheckedIn) {
        debugPrint('OfficeSentinel: Morning Check-In already done today. Stopping sentinel.');
        await FlutterForegroundTask.stopService();
        return;
      }

      // Check Wi-Fi
      final conn = await _connectivity.checkConnectivity();
      if (conn.contains(ConnectivityResult.wifi)) {
        String? ssid;
        try {
          ssid = await _networkInfo.getWifiName();
          if (ssid != null) {
            ssid = ssid.replaceAll('"', '').trim();
          }
        } catch (_) {}

        final configuredSsid = prefs.getString(NotificationConstants.prefOfficeWifiSsid) ??
            'ZaviSoft, Secreat Star, SecretStar';

        if (WifiMonitorService.isOfficeNetwork(ssid, configuredSsid)) {
          debugPrint('OfficeSentinel: Office Wi-Fi detected ($ssid)! Performing Check-In...');
          final res = await PacklyAttendanceService.instance.checkIn();
          if (res.success) {
            final timeStr =
                '${(now.hour % 12 == 0 ? 12 : now.hour % 12).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';
            final isLate = (now.hour > 9) || (now.hour == 9 && now.minute >= 15);
            await NotificationService.instance.showOfficeCheckInSuccessNotification(
              time: timeStr,
              isLate: isLate,
            );
            debugPrint('OfficeSentinel: Check-in complete! Stopping sentinel (Until Checked In achieved ✓).');
            await FlutterForegroundTask.stopService();
            return;
          }
        }
      }
    }

    // 2. EVENING CRITICAL DEPARTURE WINDOW (5:45 PM - 7:00 PM): Active until checked out
    if (now.hour == 17 && now.minute >= 45 || now.hour == 18 || now.hour == 19 && now.minute <= 15) {
      if (isAlreadyCheckedOut) {
        debugPrint('OfficeSentinel: Evening Check-Out already recorded today. Stopping sentinel.');
        await FlutterForegroundTask.stopService();
        return;
      }

      // Once past 6:00 PM, check if user disconnected from Office Wi-Fi
      if (now.hour >= 18) {
        final conn = await _connectivity.checkConnectivity();
        final isWifi = conn.contains(ConnectivityResult.wifi);
        String? ssid;
        if (isWifi) {
          try {
            ssid = await _networkInfo.getWifiName();
            if (ssid != null) ssid = ssid.replaceAll('"', '').trim();
          } catch (_) {}
        }

        final configuredSsid = prefs.getString(NotificationConstants.prefOfficeWifiSsid) ??
            'ZaviSoft, Secreat Star, SecretStar';
        final isConnectedToOffice = isWifi && WifiMonitorService.isOfficeNetwork(ssid, configuredSsid);

        // If disconnected from office Wi-Fi at/after 6:00 PM
        if (!isConnectedToOffice) {
          debugPrint('OfficeSentinel: Office Wi-Fi disconnected after 6 PM! User left office. Submitting Check-Out...');
          final res = await PacklyAttendanceService.instance.checkOut();
          if (res.success) {
            final timeStr =
                '${(now.hour % 12 == 0 ? 12 : now.hour % 12).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';
            await NotificationService.instance.showOfficeCheckOutSuccessNotification(
              time: timeStr,
            );
            debugPrint('OfficeSentinel: Check-out recorded! Stopping sentinel (Until Checked Out achieved ✓).');
            await FlutterForegroundTask.stopService();
            return;
          }
        }
      }
    }

    // Outside critical windows
    if ((now.hour < 8 || (now.hour == 8 && now.minute < 45)) ||
        (now.hour > 19 || (now.hour == 19 && now.minute > 15))) {
      debugPrint('OfficeSentinel: Outside critical office windows. Stopping sentinel.');
      await FlutterForegroundTask.stopService();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('OfficeSentinelTaskHandler: destroyed at $timestamp');
  }

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) async {
    if (id == 'check_in_now') {
      await PacklyAttendanceService.instance.checkIn();
      await FlutterForegroundTask.stopService();
    } else if (id == 'check_out_now') {
      await PacklyAttendanceService.instance.checkOut();
      await FlutterForegroundTask.stopService();
    }
  }
}

class OfficeSentinelService {
  OfficeSentinelService._();
  static final OfficeSentinelService instance = OfficeSentinelService._();

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: NotificationConstants.officeChannelId,
        channelName: NotificationConstants.officeChannelName,
        channelDescription: 'High-precision office arrival and departure sentinel',
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.DEFAULT,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000), // check every 5 seconds
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Starts the active sentinel for the morning window (stops automatically as soon as checked in)
  Future<bool> startMorningSentinel() async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastCheckInDate = prefs.getString(NotificationConstants.prefLastCheckInDate);
    final lastCheckInStatus = prefs.getString(NotificationConstants.prefLastCheckInStatus);

    if (lastCheckInDate == today &&
        (lastCheckInStatus == 'Punched' || lastCheckInStatus == 'Punched In')) {
      debugPrint('OfficeSentinelService: Already checked in today. No morning sentinel needed.');
      return false;
    }

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) return true;

    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: '🏢 Office Arrival Sentinel Active',
      notificationText: 'Detecting office Wi-Fi for instant 9:15 AM on-time check-in...',
      callback: startSentinelCallback,
    );
    debugPrint('OfficeSentinelService: Morning sentinel started: ${result.toString()}');
    return true;
  }

  /// Starts the active sentinel for the evening window (stops automatically as soon as checked out)
  Future<bool> startEveningSentinel() async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastCheckOutDate = prefs.getString(NotificationConstants.prefLastCheckOutDate);

    if (lastCheckOutDate == today) {
      debugPrint('OfficeSentinelService: Already checked out today. No evening sentinel needed.');
      return false;
    }

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) return true;

    final result = await FlutterForegroundTask.startService(
      serviceId: 257,
      notificationTitle: '🏢 Office Departure Sentinel Active',
      notificationText: 'Monitoring office departure for instant 6:00 PM check-out...',
      callback: startSentinelCallback,
    );
    debugPrint('OfficeSentinelService: Evening sentinel started: ${result.toString()}');
    return true;
  }

  /// Stops the active sentinel manually
  Future<void> stopSentinel() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      await FlutterForegroundTask.stopService();
      debugPrint('OfficeSentinelService: Sentinel manually stopped.');
    }
  }

  /// Evaluates current time and launches morning/evening sentinel if inside critical windows
  Future<void> checkAndTriggerSentinelIfNeeded() async {
    final now = DateTime.now();

    // Check if off-day or holiday
    if (await WifiMonitorService.instance.isOfficeClosedToday(now)) return;

    final prefs = await SharedPreferences.getInstance();
    final autoIn = prefs.getBool(NotificationConstants.prefAutoCheckInEnabled) ?? true;
    final autoOut = prefs.getBool(NotificationConstants.prefAutoCheckOutEnabled) ?? true;

    // Morning window: 8:50 AM to 9:20 AM
    if (autoIn && (now.hour == 8 && now.minute >= 50 || now.hour == 9 && now.minute <= 20)) {
      await startMorningSentinel();
      return;
    }

    // Evening window: 5:45 PM to 6:45 PM
    if (autoOut && (now.hour == 17 && now.minute >= 45 || now.hour == 18 && now.minute <= 45)) {
      await startEveningSentinel();
      return;
    }
  }
}
