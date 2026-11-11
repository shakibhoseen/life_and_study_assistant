import 'dart:async';
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

@pragma('vm:entry-point')
void startSentinelCallback() {
  FlutterForegroundTask.setTaskHandler(OfficeSentinelTaskHandler());
}

class OfficeSentinelTaskHandler extends TaskHandler {
  final NetworkInfo _networkInfo = NetworkInfo();
  final Connectivity _connectivity = Connectivity();
  DateTime? _lastInternetSync;
  DateTime? _lastDistanceAlert;
  bool _isProcessing = false;

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

      final autoIn = prefs.getBool(NotificationConstants.prefAutoCheckInEnabled) ?? true;
      final autoOut = prefs.getBool(NotificationConstants.prefAutoCheckOutEnabled) ?? true;

      final lastCheckInDate = prefs.getString(NotificationConstants.prefLastCheckInDate);
      final lastCheckInStatus = prefs.getString(NotificationConstants.prefLastCheckInStatus);
      final isAlreadyCheckedIn = lastCheckInDate == today &&
          (lastCheckInStatus == 'Punched' || lastCheckInStatus == 'Punched In');

      final lastCheckOutDate = prefs.getString(NotificationConstants.prefLastCheckOutDate);
      final isAlreadyCheckedOut = lastCheckOutDate == today;

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
      // 1. MORNING CRITICAL WINDOW (8:35 AM - 10:30 AM): Active until checked in
      // =========================================================================
      if ((now.hour == 8 && now.minute >= 35) || (now.hour == 9) || (now.hour == 10 && now.minute <= 30)) {
        if (isAlreadyCheckedIn) {
          debugPrint('OfficeSentinel: Morning Check-In already done today. Stopping sentinel.');
          await FlutterForegroundTask.stopService();
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
              debugPrint('OfficeSentinel: Live portal confirms check-in already recorded (${liveStatus.checkInTime})! Stopping sentinel.');
              await prefs.setString(NotificationConstants.prefLastCheckInDate, today);
              await prefs.setString(NotificationConstants.prefLastCheckInStatus, 'Punched In');
              if (liveStatus.checkInTime != null) {
                await prefs.setString(NotificationConstants.prefLastCheckInTime, liveStatus.checkInTime!);
              }
              await FlutterForegroundTask.stopService();
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
              debugPrint('OfficeSentinel: Check-in complete! Stopping sentinel (Until Checked In achieved ✓).');
              await FlutterForegroundTask.stopService();
              return;
            }
          } else {
            await NotificationService.instance.showOfficeCheckInReminder(
              officeSsid: ssid,
            );
          }
        }
      }

      // =========================================================================
      // 2. EVENING CRITICAL DEPARTURE WINDOW (5:45 PM - 10:30 PM): Active until checked out
      // =========================================================================
      if ((now.hour == 17 && now.minute >= 45) || (now.hour >= 18 && now.hour <= 22) || (now.hour == 22 && now.minute <= 30)) {
        if (isAlreadyCheckedOut) {
          debugPrint('OfficeSentinel: Evening Check-Out already recorded today. Stopping sentinel.');
          await FlutterForegroundTask.stopService();
          return;
        }

        // Check via internet whether checkout is already recorded on the server
        if (hasInternet && !isConnectedToOffice) {
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
              return;
            }
          } catch (e) {
            debugPrint('OfficeSentinel: Live portal checkout verify error: $e');
          }
        }

        // If disconnected from office Wi-Fi at/after 6:00 PM (departure detected):
        if (now.hour >= 18 && !isConnectedToOffice) {
          debugPrint('OfficeSentinel: Disconnected from office Wi-Fi after 6:00 PM. Evaluating location & departure...');

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

          // Case A: User has moved FAR away from office (e.g. > 400m)
          // DO NOT auto check out blindly without asking! Give urgent loud alert asking user to confirm!
          if (distance > 400.0) {
            final shouldAlert = _lastDistanceAlert == null ||
                now.difference(_lastDistanceAlert!).inMinutes >= 3;
            if (shouldAlert) {
              _lastDistanceAlert = now;
              debugPrint('OfficeSentinel: User is FAR from office (${distance.toStringAsFixed(1)}m)! Triggering urgent alarm alert.');
              await NotificationService.instance.showUrgentDepartureWarningNotification(
                distanceMeters: distance,
              );
              FlutterForegroundTask.updateService(
                notificationTitle: '🚨 জরুরি সতর্কতা: চেক-আউট দেননি!',
                notificationText: 'অফিস থেকে দূরে সরে গেছেন। এখনই চেক-আউট পাঞ্চ করুন।',
              );
            }
          } else {
            // Case B: User is right at the building boundary / exit (distance <= 400m)
            if (autoOut) {
              debugPrint('OfficeSentinel: Performing Safe Auto Check-Out...');
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
                debugPrint('OfficeSentinel: Check-out recorded! Stopping sentinel (Until Checked Out achieved ✓).');
                await FlutterForegroundTask.stopService();
                return;
              }
            } else {
              await NotificationService.instance.showOfficeCheckOutReminder();
            }
          }
        }
      }

      // Outside active office hours (Night 10:35 PM to Morning 8:35 AM)
      if ((now.hour < 8 || (now.hour == 8 && now.minute < 35)) ||
          (now.hour > 22 || (now.hour == 22 && now.minute > 30))) {
        debugPrint('OfficeSentinel: Outside active office hours. Stopping sentinel.');
        await FlutterForegroundTask.stopService();
      }
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

    final today = now.toIso8601String().substring(0, 10);
    final lastCheckInDate = prefs.getString(NotificationConstants.prefLastCheckInDate);
    final lastCheckInStatus = prefs.getString(NotificationConstants.prefLastCheckInStatus);
    final isCheckedIn = lastCheckInDate == today &&
        (lastCheckInStatus == 'Punched' || lastCheckInStatus == 'Punched In');

    final lastCheckOutDate = prefs.getString(NotificationConstants.prefLastCheckOutDate);
    final isCheckedOut = lastCheckOutDate == today;

    // 1. Morning window: 8:35 AM to 10:30 AM (runs until checked in)
    final isMorningTime = (now.hour == 8 && now.minute >= 35) ||
        (now.hour == 9) ||
        (now.hour == 10 && now.minute <= 30);
    if (autoIn && isMorningTime && !isCheckedIn) {
      await startMorningSentinel();
      return;
    }

    // 2. Evening window: 5:45 PM (17:45) to 10:30 PM (22:30) (runs until checked out)
    final isEveningTime = (now.hour == 17 && now.minute >= 45) ||
        (now.hour >= 18 && now.hour <= 22) ||
        (now.hour == 22 && now.minute <= 30);
    if (autoOut && isEveningTime && !isCheckedOut) {
      await startEveningSentinel();
      return;
    }
  }
}
