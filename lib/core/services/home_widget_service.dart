import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/notification_constants.dart';
import 'attendance/packly_attendance_service.dart';
import 'attendance/steadfast_lunch_service.dart';

class HomeWidgetService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.life_and_study_assistant/system_settings',
  );

  /// Initializes MethodChannel listener for widget actions (such as 1-tap refresh).
  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onWidgetRefreshRequested') {
        debugPrint('HomeWidget: live refresh requested from native widget');
        await syncCurrentDataToWidget(fetchFromNetwork: true);
      }
    });
  }

  /// Synchronizes current office & lunch data to native home screen widget.
  /// If [fetchFromNetwork] is true, calls live services to fetch fresh data.
  static Future<void> syncCurrentDataToWidget({
    bool fetchFromNetwork = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isSim =
          prefs.getBool(NotificationConstants.prefPacklySimulationMode) ?? false;

      if (fetchFromNetwork && !isSim) {
        try {
          await PacklyAttendanceService.instance.getAttendanceStatus();
        } catch (e) {
          debugPrint('HomeWidget: live attendance fetch failed: $e');
        }
        try {
          await SteadfastLunchService.instance.getServingStatus(
            forceRefresh: true,
          );
        } catch (e) {
          debugPrint('HomeWidget: live lunch status fetch failed: $e');
        }
      }

      String? checkInDate;
      String? checkInTime;
      bool? isLate;
      String? checkOutDate;
      String? checkOutTime;
      String? lunchStatus;

      if (isSim) {
        checkInDate =
            prefs.getString(NotificationConstants.prefSimulatedCheckInDate);
        checkInTime =
            prefs.getString(NotificationConstants.prefSimulatedCheckInTime);
        isLate =
            prefs.getBool(NotificationConstants.prefSimulatedCheckInIsLate);
        checkOutDate =
            prefs.getString(NotificationConstants.prefSimulatedCheckOutDate);
        checkOutTime =
            prefs.getString(NotificationConstants.prefSimulatedCheckOutTime);
        lunchStatus =
            prefs.getString(NotificationConstants.prefSimulatedServingStatus);
      } else {
        checkInDate =
            prefs.getString(NotificationConstants.prefLastCheckInDate);
        checkInTime =
            prefs.getString(NotificationConstants.prefLastCheckInTime);
        isLate =
            prefs.getBool(NotificationConstants.prefLastCheckInIsLate);
        checkOutDate =
            prefs.getString(NotificationConstants.prefLastCheckOutDate);
        checkOutTime =
            prefs.getString(NotificationConstants.prefLastCheckOutTime);
        lunchStatus =
            prefs.getString(NotificationConstants.prefLastNotifiedLunchStatus);
      }

      await updateWidget(
        checkInTime: checkInTime,
        checkInDate: checkInDate,
        isLate: isLate,
        checkOutTime: checkOutTime,
        checkOutDate: checkOutDate,
        lunchStatus: lunchStatus,
      );
    } catch (e) {
      debugPrint('HomeWidget: syncCurrentDataToWidget error: $e');
    }
  }

  /// Synchronizes current office & lunch data to native home screen widget
  static Future<void> updateWidget({
    String? checkInTime,
    String? checkInDate,
    bool? isLate,
    String? checkOutTime,
    String? checkOutDate,
    String? lunchStatus,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
      final timeStr =
          '${hour12.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';

      await prefs.setString('widget_last_sync_time', timeStr);

      if (checkInTime != null) {
        await prefs.setString('pref_last_check_in_time', checkInTime);
      }
      if (checkInDate != null) {
        await prefs.setString('pref_last_check_in_date', checkInDate);
      }
      if (isLate != null) {
        await prefs.setBool('pref_last_check_in_is_late', isLate);
      }
      if (checkOutTime != null) {
        await prefs.setString('pref_last_check_out_time', checkOutTime);
      }
      if (checkOutDate != null) {
        await prefs.setString('pref_last_check_out_date', checkOutDate);
      }
      if (lunchStatus != null) {
        await prefs.setString('pref_last_notified_lunch_status', lunchStatus);
      }

      await _channel.invokeMethod('updateWidget');
      debugPrint('HomeWidget: updated widget data successfully ($timeStr)');
    } catch (e) {
      debugPrint('HomeWidget: could not update widget: $e');
    }
  }
}
