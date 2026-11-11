import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../attendance/packly_attendance_service.dart';
import '../notification/notification_service.dart';
import 'wifi_monitor_service.dart';
import 'workmanager_service.dart';

@pragma('vm:entry-point')
void startSentinelCallback() {
  FlutterForegroundTask.setTaskHandler(OfficeSentinelTaskHandler());
}

class OfficeSentinelTaskHandler extends TaskHandler {
  final NetworkInfo _networkInfo = NetworkInfo();
  final Connectivity _connectivity = Connectivity();
  DateTime? _lastInternetSync;
  DateTime? _lastDistanceAlert;
  DateTime? _lastReminderAlert;
  String? _lastNotifTitle;
  String? _lastNotifText;
  bool _isProcessing = false;

  void _updateForegroundNotification({
    required String title,
    required String text,
  }) {
    // Prevent spamming Android OS NotificationManager and vibrating if content is identical
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
    debugPrint('OfficeSentinelTaskHandler: started at $timestamp by ${starter.name}');
    await _checkSentinelCondition();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _checkSentinelCondition();
  }

  Future<bool> _hasRealInternet(SharedPreferences prefs) async {
    final isSim = prefs.getBool(NotificationConstants.prefPacklySimulationMode) ?? false;
    if (isSim) return true;
    try {
      final conn = await _connectivity.checkConnectivity();
      if (conn.contains(ConnectivityResult.none)) return false;
      final lookup = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkSentinelCondition() async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      final now = DateTime.now();
      final today = now.toIso8601String().substring(0, 10);
      final prefs = await SharedPreferences.getInstance();

      // Check weekly off-day or holiday
      final isClosed = await WifiMonitorService.instance.isOfficeClosedToday(now);
      if (isClosed) {
        debugPrint('OfficeSentinel: Office is closed today. Stopping sentinel.');
        await FlutterForegroundTask.stopService();
        return;
      }

      // Stop during deep night (11:00 PM to 8:00 AM)
      if (now.hour >= 23 || now.hour < 8) {
        debugPrint('OfficeSentinel: Night cutoff reached. Stopping sentinel.');
        await FlutterForegroundTask.stopService();
        return;
      }

      final autoIn = prefs.getBool(NotificationConstants.prefAutoCheckInEnabled) ?? true;
      final autoOut = prefs.getBool(NotificationConstants.prefAutoCheckOutEnabled) ?? true;

      final lastCheckInDate = prefs.getString(NotificationConstants.prefLastCheckInDate);
      final lastCheckInStatus = prefs.getString(NotificationConstants.prefLastCheckInStatus);
      final isAlreadyCheckedIn = lastCheckInDate == today &&
          (lastCheckInStatus == 'Punched' || lastCheckInStatus == 'Punched In');

      final lastCheckOutDate = prefs.getString(NotificationConstants.prefLastCheckOutDate);
      final isAlreadyCheckedOut = lastCheckOutDate == today;

      // RULE 1: If check-out is already recorded today, dismiss foreground task immediately!
      if (isAlreadyCheckedOut) {
        debugPrint('OfficeSentinel: Check-Out already completed today. Dismissing sentinel.');
        await FlutterForegroundTask.stopService();
        return;
      }

      final conn = await _connectivity.checkConnectivity();
      final hasInternet = !conn.contains(ConnectivityResult.none);
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

      // =========================================================================
      // 1. MORNING CRITICAL ARRIVAL WINDOW (8:40 AM - 10:00 AM)
      // Active strictly UNTIL check-in is complete!
      // =========================================================================
      final isMorningWindow = (now.hour == 8 && now.minute >= 40) ||
          (now.hour == 9) ||
          (now.hour == 10 && now.minute <= 0);

      if (isMorningWindow) {
        if (isAlreadyCheckedIn) {
          debugPrint('OfficeSentinel: Morning Check-In already done. Stopping morning sentinel.');
          await FlutterForegroundTask.stopService();
          await WorkmanagerService.instance.cancelSafetyWatchdog();
          return;
        }

        // Periodic internet verification (e.g. if user punched directly on physical biometric machine)
        final shouldSync = _lastInternetSync == null ||
            now.difference(_lastInternetSync!).inSeconds >= 45;
        if (hasInternet && shouldSync) {
          _lastInternetSync = now;
          try {
            final liveStatus = await PacklyAttendanceService.instance.getAttendanceStatus();
            if (liveStatus.isCheckedIn) {
              debugPrint('OfficeSentinel: Live portal confirms check-in already recorded (${liveStatus.checkInTime})!');
              await prefs.setString(NotificationConstants.prefLastCheckInDate, today);
              await prefs.setString(NotificationConstants.prefLastCheckInStatus, 'Punched In');
              if (liveStatus.checkInTime != null) {
                await prefs.setString(NotificationConstants.prefLastCheckInTime, liveStatus.checkInTime!);
              }
              debugPrint('OfficeSentinel: Morning punch verified. Stopping sentinel (Goal achieved ✓).');
              await FlutterForegroundTask.stopService();
              await WorkmanagerService.instance.cancelSafetyWatchdog();
              return;
            }
          } catch (e) {
            debugPrint('OfficeSentinel: Morning portal check error: $e');
          }
        }

        // When connected to Office Wi-Fi:
        if (isConnectedToOffice) {
          debugPrint('OfficeSentinel: Office Wi-Fi detected ($ssid)! Performing Check-In...');
          if (autoIn) {
            final res = await PacklyAttendanceService.instance.checkIn();
            if (res.success) {
              final timeStr =
                  '${(now.hour % 12 == 0 ? 12 : now.hour % 12).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';
              final isLate = (now.hour > 9) || (now.hour == 9 && now.minute >= 15);
              await NotificationService.instance.showOfficeCheckInSuccessNotification(
                time: timeStr,
                isLate: isLate,
              );
              debugPrint('OfficeSentinel: Check-in complete! Stopping morning sentinel (Goal achieved ✓).');
              await FlutterForegroundTask.stopService();
              await WorkmanagerService.instance.cancelSafetyWatchdog();
              return;
            }
          } else {
            final canRemind = _lastReminderAlert == null ||
                now.difference(_lastReminderAlert!).inMinutes >= 5;
            if (canRemind) {
              _lastReminderAlert = now;
              await NotificationService.instance.showOfficeCheckInReminder(
                officeSsid: ssid,
              );
            }
          }
        }
        return;
      }

      // =========================================================================
      // 2. EVENING CRITICAL DEPARTURE WINDOW (5:45 PM - 10:30 PM)
      // Active strictly UNTIL check-out is complete!
      // =========================================================================
      final isEveningWindow = (now.hour == 17 && now.minute >= 45) ||
          (now.hour >= 18 && now.hour <= 22) ||
          (now.hour == 22 && now.minute <= 30);

      if (isEveningWindow) {
        if (isAlreadyCheckedOut) {
          debugPrint('OfficeSentinel: Check-Out already completed today. Dismissing sentinel.');
          await FlutterForegroundTask.stopService();
          await WorkmanagerService.instance.cancelSafetyWatchdog();
          return;
        }

        // While user is connected to office Wi-Fi, duty is in progress inside office
        if (isConnectedToOffice) {
          _updateForegroundNotification(
            title: '🏢 Office Departure Sentinel Active',
            text: 'Connected to office network ($ssid). Monitoring 6:00 PM+ departure...',
          );
          return;
        }

        // User is DISCONNECTED from office Wi-Fi:
        // Step 1: Check if mobile internet / data is active & working.
        // If user is in room, elevator, or stairs with no mobile signal yet,
        // stay alive in foreground and keep polling every interval until internet is restored!
        final realInternet = await _hasRealInternet(prefs);
        if (!realInternet) {
          debugPrint(
            'OfficeSentinel: Disconnected from office Wi-Fi, but mobile internet is not yet reachable. Polling every interval to finalize checkout...',
          );
          _updateForegroundNotification(
            title: '📶 Wi-Fi বিচ্ছিন্ন - ইন্টারনেটের অপেক্ষা...',
            text: 'রুম/সিঁড়িতে সংযোগ বিচ্ছিন্ন। মোবাইল নেটওয়ার্ক সচল হওয়া মাত্রই চেক-আউট হবে...',
          );
          return;
        }

        // Step 2: Internet is online! Check via server: is check-out already recorded on the server today?
        try {
          final liveStatus = await PacklyAttendanceService.instance.getAttendanceStatus();
          if (liveStatus.isCheckedOut) {
            debugPrint('OfficeSentinel: Portal confirms check-out already completed (${liveStatus.checkOutTime}). Dismissing sentinel.');
            await prefs.setString(NotificationConstants.prefLastCheckOutDate, today);
            if (liveStatus.checkOutTime != null) {
              await prefs.setString(NotificationConstants.prefLastCheckOutTime, liveStatus.checkOutTime!);
            }
            await NotificationService.instance.cancelCheckOutReminder();
            await FlutterForegroundTask.stopService();
            await WorkmanagerService.instance.cancelSafetyWatchdog();
            return;
          }
        } catch (e) {
          debugPrint('OfficeSentinel: Live portal checkout verify error: $e');
        }

        // Step 3: Wi-Fi disconnected, internet is active, and checkout NOT done yet on server:
        // Subcase A: Before 6:00 PM (Early Out)
        // Rule: NEVER auto check-out without asking before 6:00 PM! Ask the user!
        if (now.hour < 18) {
          final shouldAlert = _lastDistanceAlert == null ||
              now.difference(_lastDistanceAlert!).inMinutes >= 5;
          if (shouldAlert) {
            _lastDistanceAlert = now;
            debugPrint('OfficeSentinel: Disconnected before 6:00 PM. Asking user for early departure.');
            await NotificationService.instance.showOfficeCheckOutReminder(isEarly: true);
            _updateForegroundNotification(
              title: '⚠️ Early Departure Alert (Before 6 PM)',
              text: 'অফিস সময় ৬:০০ টা পর্যন্ত। বের হলে ট্যাপ করে চেক-আউট দিন।',
            );
          }
          return;
        }

        // Subcase B: At or after 6:00 PM (Normal / Overtime Departure)
        debugPrint('OfficeSentinel: 6:00 PM+ departure detected. Evaluating distance...');

        // Measure distance from office
        double distance = 0.0;
        Position? pos;
        try {
          final perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
            pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: Duration(seconds: 8),
              ),
            );
            final officeLat = prefs.getDouble(NotificationConstants.prefOfficeLatitude) ?? 23.7925;
            final officeLng = prefs.getDouble(NotificationConstants.prefOfficeLongitude) ?? 90.4078;
            distance = Geolocator.distanceBetween(
              pos.latitude,
              pos.longitude,
              officeLat,
              officeLng,
            );
            debugPrint('OfficeSentinel: Distance to office: ${distance.toStringAsFixed(1)}m');
          }
        } catch (e) {
          debugPrint('OfficeSentinel: Geolocator distance error: $e');
        }

        // Rule for after 6:00 PM:
        // If distance > 400m (user far from office):
        // DO NOT auto-punch blindly! ASK the user with urgent loud alert!
        if (distance > 400.0) {
          final shouldAlert = _lastDistanceAlert == null ||
              now.difference(_lastDistanceAlert!).inMinutes >= 3;
          if (shouldAlert) {
            _lastDistanceAlert = now;
            debugPrint('OfficeSentinel: User is FAR from office (${distance.toStringAsFixed(1)}m)! Triggering urgent alarm alert.');
            await NotificationService.instance.showUrgentDepartureWarningNotification(
              distanceMeters: distance,
            );
            _updateForegroundNotification(
              title: '🚨 জরুরি সতর্কতা: চেক-আউট দেননি!',
              text: 'অফিস থেকে দূরে সরে গেছেন। এখনই চেক-আউট পাঞ্চ করুন।',
            );
          }
        } else {
          // If distance <= 400m (user is near office building gate / door as Wi-Fi drops):
          // Auto check-out is safe and authorized!
          if (autoOut) {
            debugPrint('OfficeSentinel: Performing Safe Auto Check-Out at office exit...');
            final res = await PacklyAttendanceService.instance.checkOut(
              latitude: pos?.latitude,
              longitude: pos?.longitude,
            );
            if (res.success) {
              final timeStr =
                  '${(now.hour % 12 == 0 ? 12 : now.hour % 12).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';
              await NotificationService.instance.showOfficeCheckOutSuccessNotification(
                time: timeStr,
              );
              debugPrint('OfficeSentinel: Auto Check-out recorded! Stopping sentinel (Until Checked Out achieved ✓).');
              await FlutterForegroundTask.stopService();
              await WorkmanagerService.instance.cancelSafetyWatchdog();
              return;
            }
          } else {
            final canRemind = _lastReminderAlert == null ||
                now.difference(_lastReminderAlert!).inMinutes >= 5;
            if (canRemind) {
              _lastReminderAlert = now;
              await NotificationService.instance.showOfficeCheckOutReminder();
            }
          }
        }
        return;
      }

      // =========================================================================
      // OUTSIDE BOTH CRITICAL WINDOWS (Midday work 10:01 AM - 5:44 PM or Night sleep):
      // Keep phone clean and battery saved.
      // =========================================================================
      debugPrint('OfficeSentinel: Outside arrival/departure windows. Stopping sentinel.');
      await FlutterForegroundTask.stopService();
    } finally {
      _isProcessing = false;
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
      await WorkmanagerService.instance.cancelSafetyWatchdog();
    } else if (id == 'check_out_now') {
      await PacklyAttendanceService.instance.checkOut();
      await FlutterForegroundTask.stopService();
      await WorkmanagerService.instance.cancelSafetyWatchdog();
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

  /// Starts the active sentinel for the workday & evening departure (stops automatically as soon as checked out)
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
      notificationTitle: '🏢 Office Sentinel: Duty In Progress',
      notificationText: 'Active until check-out is complete. Monitoring departure & Wi-Fi...',
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

  /// Evaluates current state and launches sentinel if check-in or check-out is pending
  Future<void> checkAndTriggerSentinelIfNeeded() async {
    final now = DateTime.now();

    // Check if off-day or holiday
    if (await WifiMonitorService.instance.isOfficeClosedToday(now)) return;

    final prefs = await SharedPreferences.getInstance();
    final autoIn = prefs.getBool(NotificationConstants.prefAutoCheckInEnabled) ?? true;
    final autoOut = prefs.getBool(NotificationConstants.prefAutoCheckOutEnabled) ?? true;

    final today = now.toIso8601String().substring(0, 10);
    final lastCheckInDate = prefs.getString(NotificationConstants.prefLastCheckInDate);
    final lastCheckInStatus = prefs.getString(NotificationConstants.prefLastCheckInStatus);
    final isCheckedIn = lastCheckInDate == today &&
        (lastCheckInStatus == 'Punched' || lastCheckInStatus == 'Punched In');

    final lastCheckOutDate = prefs.getString(NotificationConstants.prefLastCheckOutDate);
    final isCheckedOut = lastCheckOutDate == today;

    // Do not run during deep night (11:00 PM to 8:00 AM)
    if (now.hour >= 23 || now.hour < 8) return;

    // 1. Morning critical arrival window: 8:40 AM to 10:00 AM (runs strictly UNTIL check-in is complete)
    final isMorningTime = (now.hour == 8 && now.minute >= 40) ||
        (now.hour == 9) ||
        (now.hour == 10 && now.minute <= 0);
    if (autoIn && isMorningTime) {
      if (isCheckedIn) {
        debugPrint('OfficeSentinel: Morning punch already completed. Ensuring watchdog cancelled.');
        await stopSentinel();
        await WorkmanagerService.instance.cancelSafetyWatchdog();
        return;
      }
      await startMorningSentinel();
      unawaited(WorkmanagerService.instance.scheduleSafetyWatchdog(delay: const Duration(minutes: 15)));
      return;
    }

    // 2. Evening critical departure window: 5:45 PM (17:45) to 10:30 PM (22:30) (runs strictly UNTIL checkout complete)
    final isEveningTime = (now.hour == 17 && now.minute >= 45) ||
        (now.hour >= 18 && now.hour <= 22) ||
        (now.hour == 22 && now.minute <= 30);
    if (autoOut && isEveningTime) {
      if (isCheckedOut) {
        debugPrint('OfficeSentinel: Evening checkout already completed. Ensuring watchdog cancelled.');
        await stopSentinel();
        await WorkmanagerService.instance.cancelSafetyWatchdog();
        return;
      }
      await startEveningSentinel();
      unawaited(WorkmanagerService.instance.scheduleSafetyWatchdog(delay: const Duration(minutes: 15)));
      return;
    }
  }
}
