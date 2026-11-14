import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/notification_constants.dart';
import '../../../../core/services/attendance/packly_attendance_service.dart';
import '../../../../core/services/attendance/steadfast_lunch_service.dart';

// ==========================================
// 1. STEADFAST LUNCH STATE & NOTIFIER
// ==========================================

class LunchState {
  final bool isLoading;
  final bool isToggling;
  final SteadfastMealCalendar? calendar;
  final bool? todayBooked;
  final bool? tomorrowBooked;
  final String? lastSyncTime;
  final String? errorMessage;
  final String selectedMonth;

  const LunchState({
    this.isLoading = false,
    this.isToggling = false,
    this.calendar,
    this.todayBooked,
    this.tomorrowBooked,
    this.lastSyncTime,
    this.errorMessage,
    required this.selectedMonth,
  });

  LunchState copyWith({
    bool? isLoading,
    bool? isToggling,
    SteadfastMealCalendar? calendar,
    bool? todayBooked,
    bool? tomorrowBooked,
    String? lastSyncTime,
    String? errorMessage,
    String? selectedMonth,
  }) {
    return LunchState(
      isLoading: isLoading ?? this.isLoading,
      isToggling: isToggling ?? this.isToggling,
      calendar: calendar ?? this.calendar,
      todayBooked: todayBooked ?? this.todayBooked,
      tomorrowBooked: tomorrowBooked ?? this.tomorrowBooked,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      errorMessage: errorMessage,
      selectedMonth: selectedMonth ?? this.selectedMonth,
    );
  }
}

class LunchNotifier extends Notifier<LunchState> {
  @override
  LunchState build() {
    final now = DateTime.now();
    final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    // Asynchronously load cached status on startup
    _loadInitialCache();

    return LunchState(selectedMonth: currentMonth);
  }

  Future<void> _loadInitialCache() async {
    final prefs = await SharedPreferences.getInstance();
    final todayBooked = prefs.getBool(
      NotificationConstants.prefLunchLastKnownTodayBooked,
    );
    final tomorrowBooked = prefs.getBool(
      NotificationConstants.prefLunchLastKnownTomorrowBooked,
    );
    final lastSync = prefs.getString(
      NotificationConstants.prefLunchLastSyncTime,
    );

    state = state.copyWith(
      todayBooked: todayBooked,
      tomorrowBooked: tomorrowBooked,
      lastSyncTime: lastSync,
    );
  }

  /// Synchronize meal calendar and update today/tomorrow states
  Future<void> syncCalendar({String? month, bool forceRefresh = false}) async {
    final targetMonth = month ?? state.selectedMonth;
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final calendar = await SteadfastLunchService.instance.getMealCalendar(
        month: targetMonth,
        forceRefresh: forceRefresh,
      );

      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));
      final todayStr = now.toIso8601String().substring(0, 10);
      final tomorrowStr = tomorrow.toIso8601String().substring(0, 10);

      final todayMeal = calendar?.findDay(todayStr);
      final tomorrowMeal = calendar?.findDay(tomorrowStr);

      final prefs = await SharedPreferences.getInstance();
      if (todayMeal != null) {
        await prefs.setBool(
          NotificationConstants.prefLunchLastKnownTodayBooked,
          todayMeal.booked,
        );
      }
      if (tomorrowMeal != null) {
        await prefs.setBool(
          NotificationConstants.prefLunchLastKnownTomorrowBooked,
          tomorrowMeal.booked,
        );
      }

      final nowIso = DateTime.now().toIso8601String();
      await prefs.setString(
        NotificationConstants.prefLunchLastSyncTime,
        nowIso,
      );

      state = state.copyWith(
        isLoading: false,
        calendar: calendar,
        todayBooked: todayMeal?.booked ?? state.todayBooked,
        tomorrowBooked: tomorrowMeal?.booked ?? state.tomorrowBooked,
        lastSyncTime: nowIso,
        selectedMonth: targetMonth,
      );
    } catch (e) {
      debugPrint('LunchNotifier: syncCalendar error: $e');
      state = state.copyWith(isLoading: false, errorMessage: '$e');
    }
  }

  /// Toggles tomorrow's meal booking (ON or OFF)
  Future<SteadfastToggleResult> toggleTomorrowMeal({
    bool? forceSimulate,
  }) async {
    state = state.copyWith(isToggling: true, errorMessage: null);
    try {
      final res = await SteadfastLunchService.instance.toggleTomorrowMeal(
        forceSimulate: forceSimulate,
      );

      if (res.success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(
          NotificationConstants.prefLunchLastKnownTomorrowBooked,
          res.isBooked,
        );

        // Update local calendar days if loaded
        SteadfastMealCalendar? updatedCal = res.calendar ?? state.calendar;
        if (updatedCal != null && res.calendar == null) {
          final updatedDays = updatedCal.days.map((d) {
            if (d.date == res.targetDate) {
              return SteadfastDayMeal(
                date: d.date,
                state: d.state,
                afterCutoff: d.afterCutoff,
                booked: res.isBooked,
                meal: res.isBooked ? 'Lunch' : null,
                holiday: d.holiday,
              );
            }
            return d;
          }).toList();

          updatedCal = SteadfastMealCalendar(
            month: updatedCal.month,
            label: updatedCal.label,
            cutoff: updatedCal.cutoff,
            eligible: updatedCal.eligible,
            bookedCount: updatedDays.where((d) => d.booked).length,
            days: updatedDays,
          );
        }

        state = state.copyWith(
          isToggling: false,
          tomorrowBooked: res.isBooked,
          calendar: updatedCal,
        );
      } else {
        state = state.copyWith(isToggling: false, errorMessage: res.message);
      }
      return res;
    } catch (e) {
      state = state.copyWith(isToggling: false, errorMessage: '$e');
      return SteadfastToggleResult(
        success: false,
        message: '$e',
        targetDate: '',
        isBooked: false,
      );
    }
  }

  /// Toggles a specific date's meal booking in the calendar
  Future<SteadfastToggleResult> toggleDayMeal({
    required String date,
    required bool book,
    bool? forceSimulate,
  }) async {
    state = state.copyWith(isToggling: true, errorMessage: null);
    try {
      final res = await SteadfastLunchService.instance.toggleMealDate(
        date: date,
        book: book,
        forceSimulate: forceSimulate,
      );

      if (res.success) {
        final tomorrowStr = DateTime.now()
            .add(const Duration(days: 1))
            .toIso8601String()
            .substring(0, 10);
        if (date == tomorrowStr) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(
            NotificationConstants.prefLunchLastKnownTomorrowBooked,
            book,
          );
          state = state.copyWith(tomorrowBooked: book);
        }

        SteadfastMealCalendar? updatedCal = res.calendar ?? state.calendar;
        if (updatedCal != null && res.calendar == null) {
          final updatedDays = updatedCal.days.map((d) {
            if (d.date == date) {
              return SteadfastDayMeal(
                date: d.date,
                state: d.state,
                afterCutoff: d.afterCutoff,
                booked: book,
                meal: book ? 'Lunch' : null,
                holiday: d.holiday,
              );
            }
            return d;
          }).toList();

          updatedCal = SteadfastMealCalendar(
            month: updatedCal.month,
            label: updatedCal.label,
            cutoff: updatedCal.cutoff,
            eligible: updatedCal.eligible,
            bookedCount: updatedDays.where((d) => d.booked).length,
            days: updatedDays,
          );
        }

        state = state.copyWith(isToggling: false, calendar: updatedCal);
      } else {
        state = state.copyWith(isToggling: false, errorMessage: res.message);
      }
      return res;
    } catch (e) {
      state = state.copyWith(isToggling: false, errorMessage: '$e');
      return SteadfastToggleResult(
        success: false,
        message: '$e',
        targetDate: date,
        isBooked: !book,
      );
    }
  }

  /// Ping the server, sync details and update state
  Future<SteadfastLunchPingResult> ping() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await SteadfastLunchService.instance.ping();
      if (res.success) {
        state = state.copyWith(
          isLoading: false,
          todayBooked: res.todayBooked ?? state.todayBooked,
          tomorrowBooked: res.tomorrowBooked ?? state.tomorrowBooked,
        );
        // Refresh calendar in background
        syncCalendar(forceRefresh: true);
      } else {
        state = state.copyWith(isLoading: false, errorMessage: res.message);
      }
      return res;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: '$e');
      return SteadfastLunchPingResult(success: false, message: '$e');
    }
  }

  void setMonth(String month) {
    if (state.selectedMonth != month) {
      state = state.copyWith(selectedMonth: month);
      syncCalendar(month: month);
    }
  }
}

final lunchProvider = NotifierProvider<LunchNotifier, LunchState>(
  LunchNotifier.new,
);

// ==========================================
// 2. PACKLY ATTENDANCE STATE & NOTIFIER
// ==========================================

class AttendanceState {
  final bool isLoading;
  final PacklyAttendanceStatus? status;
  final PacklyHoliday? todayHoliday;
  final String? lastCheckInTime;
  final String? lastCheckOutTime;
  final bool isLate;
  final bool isSimulationMode;
  final String bannerMode;

  const AttendanceState({
    this.isLoading = false,
    this.status,
    this.todayHoliday,
    this.lastCheckInTime,
    this.lastCheckOutTime,
    this.isLate = false,
    this.isSimulationMode = false,
    this.bannerMode = 'contextual',
  });

  AttendanceState copyWith({
    bool? isLoading,
    PacklyAttendanceStatus? status,
    PacklyHoliday? todayHoliday,
    String? lastCheckInTime,
    String? lastCheckOutTime,
    bool clearCheckOutTime = false,
    bool clearCheckInTime = false,
    bool? isLate,
    bool? isSimulationMode,
    String? bannerMode,
  }) {
    return AttendanceState(
      isLoading: isLoading ?? this.isLoading,
      status: status ?? this.status,
      todayHoliday: todayHoliday ?? this.todayHoliday,
      lastCheckInTime: clearCheckInTime
          ? null
          : (lastCheckInTime ?? this.lastCheckInTime),
      lastCheckOutTime: clearCheckOutTime
          ? null
          : (lastCheckOutTime ?? this.lastCheckOutTime),
      isLate: isLate ?? this.isLate,
      isSimulationMode: isSimulationMode ?? this.isSimulationMode,
      bannerMode: bannerMode ?? this.bannerMode,
    );
  }
}

class AttendanceNotifier extends Notifier<AttendanceState> {
  @override
  AttendanceState build() {
    _loadSavedStatus();
    return const AttendanceState();
  }

  Future<void> _loadSavedStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final holiday = await PacklyAttendanceService.instance.getHolidayForDate(
      DateTime.now(),
    );
    final bannerMode =
        prefs.getString(NotificationConstants.prefOfficeBannerMode) ??
        'contextual';
    final isSim =
        prefs.getBool(NotificationConstants.prefPacklySimulationMode) ?? false;

    String? inTime;
    String? outTime;
    bool isLate = false;

    if (isSim) {
      final simDate = prefs.getString(
        NotificationConstants.prefSimulatedCheckInDate,
      );
      if (simDate == today) {
        inTime = prefs.getString(
          NotificationConstants.prefSimulatedCheckInTime,
        );
        outTime = prefs.getString(
          NotificationConstants.prefSimulatedCheckOutTime,
        );
        isLate =
            prefs.getBool(NotificationConstants.prefSimulatedCheckInIsLate) ??
            false;
      }
    } else {
      final lastCheckInDate = prefs.getString(
        NotificationConstants.prefLastCheckInDate,
      );
      if (lastCheckInDate == today) {
        inTime = prefs.getString(NotificationConstants.prefLastCheckInTime);
        final lastOutDate = prefs.getString(
          NotificationConstants.prefLastCheckOutDate,
        );
        outTime = (lastOutDate == today)
            ? prefs.getString(NotificationConstants.prefLastCheckOutTime)
            : null;
        isLate =
            prefs.getBool(NotificationConstants.prefLastCheckInIsLate) ?? false;
      }
    }

    state = state.copyWith(
      todayHoliday: holiday,
      bannerMode: bannerMode,
      isSimulationMode: isSim,
      lastCheckInTime: inTime,
      lastCheckOutTime: outTime,
      clearCheckOutTime: outTime == null,
      isLate: isLate,
    );

    // Sync live from portal in background
    syncLiveAttendance();
  }

  Future<void> syncLiveAttendance() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final isSim =
          prefs.getBool(NotificationConstants.prefPacklySimulationMode) ??
          false;
      final status = await PacklyAttendanceService.instance
          .getAttendanceStatus();

      state = state.copyWith(
        isLoading: false,
        status: status,
        isSimulationMode: isSim,
        lastCheckInTime:
            status.checkInTime ?? (isSim ? state.lastCheckInTime : null),
        lastCheckOutTime: status.checkOutTime,
        clearCheckOutTime: status.checkOutTime == null,
        isLate: status.isLate,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<PacklyResult> checkIn({bool? forceSimulate}) async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await PacklyAttendanceService.instance.checkIn(
        forceSimulate: forceSimulate,
      );
      state = state.copyWith(
        isLoading: false,
        status: res.status ?? state.status,
        lastCheckInTime: res.status?.checkInTime ?? state.lastCheckInTime,
        isLate: res.status?.isLate ?? state.isLate,
      );
      return res;
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return PacklyResult(success: false, message: '$e');
    }
  }

  Future<PacklyResult> checkOut({bool? forceSimulate}) async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await PacklyAttendanceService.instance.checkOut(
        forceSimulate: forceSimulate,
      );
      state = state.copyWith(
        isLoading: false,
        status: res.status ?? state.status,
        lastCheckOutTime: res.status?.checkOutTime ?? state.lastCheckOutTime,
      );
      return res;
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return PacklyResult(success: false, message: '$e');
    }
  }

  Future<void> setSimulationMode(bool isSim) async {
    state = state.copyWith(isSimulationMode: isSim);
    if (!isSim) {
      await PacklyAttendanceService.instance.clearSimulationData();
      state = state.copyWith(clearCheckOutTime: true);
    }
    await syncLiveAttendance();
  }
}

final officeAttendanceProvider =
    NotifierProvider<AttendanceNotifier, AttendanceState>(
      AttendanceNotifier.new,
    );
