import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/notification_constants.dart';
import 'attendance/packly_attendance_service.dart';
import 'attendance/steadfast_lunch_service.dart';
import 'study_widget_service.dart';

class HomeWidgetService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.life_and_study_assistant/system_settings',
  );

  /// yyyy-MM-dd, matching what the native widget formats for "today".
  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Installs the one handler for this channel.
  ///
  /// There is a single MethodChannel for all native widget traffic, and
  /// setMethodCallHandler replaces rather than adds. Every service that wants
  /// a native call is routed from here; a second service calling
  /// setMethodCallHandler on this channel would quietly unhook the others.
  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onWidgetRefreshRequested') {
        debugPrint('HomeWidget: live refresh requested from native widget');
        await syncCurrentDataToWidget(fetchFromNetwork: true);
        return null;
      }
      await StudyWidgetService.handleNativeCall(call.method);
      return null;
    });
  }

  /// Which lunch status the widget should show, given what the refresh found.
  ///
  /// Pulled out as a function because this is where the widget went wrong: a
  /// live status was fetched and then discarded in favour of notification
  /// bookkeeping that nothing dated.
  ///
  /// [fetched] is this refresh's live answer and always wins. Failing that,
  /// the sentinel's last notified status counts only if it is from today.
  /// Otherwise the day starts where every day starts.
  @visibleForTesting
  static String resolveLunchStatus({
    required String? fetched,
    required String? notifiedStatus,
    required String? notifiedDate,
    required String todayIso,
  }) {
    if (fetched != null && fetched.isNotEmpty) return fetched;
    if (notifiedStatus != null &&
        notifiedStatus.isNotEmpty &&
        notifiedDate == todayIso) {
      return notifiedStatus;
    }
    return 'cooking';
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

      // getAttendanceStatus() writes prefLastCheckIn*/CheckOut* as it goes, so
      // its return value is genuinely not needed here. getServingStatus() does
      // not write anything — it only returns — so its result has to be carried
      // to the widget by hand. Dropping it was why pressing refresh fetched the
      // real lunch status and then displayed something else.
      SteadfastServingStatus? freshServing;
      if (fetchFromNetwork && !isSim) {
        try {
          await PacklyAttendanceService.instance.getAttendanceStatus();
        } catch (e) {
          debugPrint('HomeWidget: live attendance fetch failed: $e');
        }
        try {
          freshServing = await SteadfastLunchService.instance.getServingStatus(
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
      String? lunchStatusDate;

      final todayIso = _isoDate(DateTime.now());

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
        lunchStatusDate = todayIso;
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
        // Three sources, best first.
        //
        // prefLastNotifiedLunchStatus is not the current status: the lunch
        // sentinel writes it when it *sends a notification*, as bookkeeping so
        // it does not notify twice. It is only as fresh as the last alert, and
        // it keeps its value overnight — which is how a widget could sit on
        // "Served" at nine the next morning. It has always had a companion
        // date key; nothing here was reading it.
        final notifiedStatus =
            prefs.getString(NotificationConstants.prefLastNotifiedLunchStatus);
        final notifiedDate = prefs.getString(
          NotificationConstants.prefLastNotifiedLunchStatusDate,
        );

        lunchStatus = resolveLunchStatus(
          fetched: freshServing?.status,
          notifiedStatus: notifiedStatus,
          notifiedDate: notifiedDate,
          todayIso: todayIso,
        );
        lunchStatusDate = todayIso;
      }

      await updateWidget(
        checkInTime: checkInTime,
        checkInDate: checkInDate,
        isLate: isLate,
        checkOutTime: checkOutTime,
        checkOutDate: checkOutDate,
        lunchStatus: lunchStatus,
        lunchStatusDate: lunchStatusDate,
      );
    } catch (e) {
      debugPrint('HomeWidget: syncCurrentDataToWidget error: $e');
    }
  }

  /// Synchronizes current office & lunch data to native home screen widget
  /// A null argument means "leave whatever is there alone", because callers
  /// such as the lunch sentinel update one field without knowing the others.
  static Future<void> updateWidget({
    String? checkInTime,
    String? checkInDate,
    bool? isLate,
    String? checkOutTime,
    String? checkOutDate,
    String? lunchStatus,
    String? lunchStatusDate,
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
        // Stamped with the day it belongs to, so the widget can tell a status
        // it has not heard about today from one it has.
        await prefs.setString(
          'pref_last_lunch_status_date',
          lunchStatusDate ?? _isoDate(DateTime.now()),
        );
      }

      await _channel.invokeMethod('updateWidget');
      debugPrint('HomeWidget: updated widget data successfully ($timeStr)');
    } catch (e) {
      debugPrint('HomeWidget: could not update widget: $e');
    }
  }
}
