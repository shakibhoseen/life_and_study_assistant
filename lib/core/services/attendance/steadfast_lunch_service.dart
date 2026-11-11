import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';

class SteadfastDayMeal {
  final String date;
  final String state;
  final bool afterCutoff;
  final bool booked;
  final String? meal;
  final String? holiday;

  const SteadfastDayMeal({
    required this.date,
    required this.state,
    required this.afterCutoff,
    required this.booked,
    this.meal,
    this.holiday,
  });

  factory SteadfastDayMeal.fromJson(Map<String, dynamic> json) {
    return SteadfastDayMeal(
      date: json['date']?.toString() ?? '',
      state: json['state']?.toString() ?? 'editable',
      afterCutoff: json['after_cutoff'] == true,
      booked: json['booked'] == true,
      meal: json['meal']?.toString(),
      holiday: json['holiday']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'state': state,
        'after_cutoff': afterCutoff,
        'booked': booked,
        'meal': meal,
        'holiday': holiday,
      };

  bool get isEditable => state == 'editable' && !afterCutoff;
}

class SteadfastMealCalendar {
  final String month;
  final String label;
  final String cutoff;
  final bool eligible;
  final int bookedCount;
  final List<SteadfastDayMeal> days;

  const SteadfastMealCalendar({
    required this.month,
    required this.label,
    required this.cutoff,
    required this.eligible,
    required this.bookedCount,
    required this.days,
  });

  factory SteadfastMealCalendar.fromJson(Map<String, dynamic> json) {
    final daysList = (json['days'] as List<dynamic>?)
            ?.map((d) => SteadfastDayMeal.fromJson(d as Map<String, dynamic>))
            .toList() ??
        [];

    return SteadfastMealCalendar(
      month: json['month']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      cutoff: json['cutoff']?.toString() ?? '6:00 PM',
      eligible: json['eligible'] == true,
      bookedCount: (json['booked'] as num?)?.toInt() ?? 0,
      days: daysList,
    );
  }

  SteadfastDayMeal? findDay(String date) {
    for (final d in days) {
      if (d.date == date) return d;
    }
    return null;
  }
}

class SteadfastLunchPingResult {
  final bool success;
  final String message;
  final String? userName;
  final String? employeeCode;
  final String? department;
  final bool? todayBooked;
  final bool? tomorrowBooked;
  final String? cutoffTime;

  const SteadfastLunchPingResult({
    required this.success,
    required this.message,
    this.userName,
    this.employeeCode,
    this.department,
    this.todayBooked,
    this.tomorrowBooked,
    this.cutoffTime,
  });
}

class SteadfastToggleResult {
  final bool success;
  final String message;
  final String targetDate;
  final bool isBooked;
  final SteadfastMealCalendar? calendar;

  const SteadfastToggleResult({
    required this.success,
    required this.message,
    required this.targetDate,
    required this.isBooked,
    this.calendar,
  });
}

class SteadfastLunchService {
  SteadfastLunchService._internal();
  static final SteadfastLunchService instance = SteadfastLunchService._internal();

  static const String baseUrl = 'https://lunch.steadfastcourier.xyz';
  static const String defaultEmail = 'shakibhossen100@gmail.com';
  static const String defaultPassword = 'Shakib100\$';

  final Map<String, String> _cookies = {};
  String? _xsrfToken;
  String? _inertiaVersion;
  DateTime? _lastLoginTime;
  SteadfastMealCalendar? _cachedCalendar;

  void _extractCookies(http.Response response) {
    final rawSetCookie = response.headers['set-cookie'];
    if (rawSetCookie == null || rawSetCookie.isEmpty) return;

    final cookieParts = rawSetCookie.split(RegExp(r',(?=\s*[A-Za-z0-9_\-]+=)'));
    for (final part in cookieParts) {
      final keyVal = part.split(';').first.trim();
      final eqIdx = keyVal.indexOf('=');
      if (eqIdx != -1) {
        final key = keyVal.substring(0, eqIdx).trim();
        final val = keyVal.substring(eqIdx + 1).trim();
        if (key.isNotEmpty) {
          _cookies[key] = val;
          if (key == 'XSRF-TOKEN') {
            _xsrfToken = Uri.decodeComponent(val);
          }
        }
      }
    }
  }

  Map<String, String> _buildHeaders([Map<String, String>? extra]) {
    final cookieHeader = _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      'Accept': 'application/json',
      'Origin': baseUrl,
      'Referer': '$baseUrl/my-meals',
      'X-Requested-With': 'XMLHttpRequest',
    };
    if (cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }
    if (_xsrfToken != null && _xsrfToken!.isNotEmpty) {
      headers['X-XSRF-TOKEN'] = _xsrfToken!;
    }
    if (extra != null) {
      headers.addAll(extra);
    }
    return headers;
  }

  /// Logs in to Steadfast Lunch Portal using Inertia protocol
  Future<bool> login({
    String? email,
    String? password,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _lastLoginTime != null &&
        DateTime.now().difference(_lastLoginTime!).inHours < 4 &&
        _cookies.containsKey('corporate-lunch-session')) {
      return true;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final loginEmail = email ??
          prefs.getString(NotificationConstants.prefLunchEmail) ??
          defaultEmail;
      final loginPassword = password ??
          prefs.getString(NotificationConstants.prefLunchPassword) ??
          defaultPassword;

      final client = http.Client();
      try {
        // 1. GET /login to extract initial cookies, XSRF token, and Inertia version
        final getResp = await client.get(
          Uri.parse('$baseUrl/login'),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
          },
        );
        _extractCookies(getResp);

        final pageHtml = getResp.body;
        final pageMatch = RegExp(
          r'<script data-page="app" type="application/json">(.*?)</script>',
          dotAll: true,
        ).firstMatch(pageHtml);

        if (pageMatch != null) {
          try {
            final pageJson = jsonDecode(pageMatch.group(1)!) as Map;
            _inertiaVersion = pageJson['version']?.toString();
          } catch (e) {
            debugPrint('SteadfastLunch: Could not parse Inertia version: $e');
          }
        }

        // 2. POST /login via Inertia
        final postHeaders = _buildHeaders({
          'Content-Type': 'application/json',
          'X-Inertia': 'true',
          'Referer': '$baseUrl/login',
        });
        if (_inertiaVersion != null) {
          postHeaders['X-Inertia-Version'] = _inertiaVersion!;
        }

        final postResp = await client.post(
          Uri.parse('$baseUrl/login'),
          headers: postHeaders,
          body: jsonEncode({
            'email': loginEmail,
            'password': loginPassword,
            'remember': true,
          }),
        );
        _extractCookies(postResp);

        if (postResp.statusCode == 200 ||
            postResp.statusCode == 302 ||
            (postResp.statusCode == 409 &&
                postResp.headers['x-inertia-location']?.contains('dashboard') == true)) {
          _lastLoginTime = DateTime.now();
          debugPrint('SteadfastLunch: Login successful for $loginEmail');
          return true;
        }

        debugPrint('SteadfastLunch: Login failed with HTTP status ${postResp.statusCode}');
        return false;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('SteadfastLunch: Login exception: $e');
      return false;
    }
  }

  /// Pings the lunch portal, tests credentials, and synchronizes today/tomorrow meal status
  Future<SteadfastLunchPingResult> ping({String? email, String? password}) async {
    final prefs = await SharedPreferences.getInstance();
    final isSim = prefs.getBool(NotificationConstants.prefPacklySimulationMode) ?? false;

    if (isSim) {
      return const SteadfastLunchPingResult(
        success: true,
        message: '[TEST MODE] Connected to Steadfast Lunch Portal (Mock)',
        userName: 'Shakib Hossen (Simulation)',
        employeeCode: '4482',
        department: '2nd Floor (Zavisoft)',
        todayBooked: true,
        tomorrowBooked: false,
        cutoffTime: '6:00 PM',
      );
    }

    final loggedIn = await login(email: email, password: password, forceRefresh: true);
    if (!loggedIn) {
      return const SteadfastLunchPingResult(
        success: false,
        message: 'Steadfast Lunch login failed! Please check email and password in Settings.',
      );
    }

    try {
      final calendar = await getMealCalendar(forceRefresh: true);
      if (calendar == null) {
        return const SteadfastLunchPingResult(
          success: true,
          message: 'Login successful, but meal calendar could not be loaded.',
          userName: 'Shakib Hossen',
          employeeCode: '4482',
        );
      }

      final today = DateTime.now();
      final tomorrow = today.add(const Duration(days: 1));
      final todayStr = today.toIso8601String().substring(0, 10);
      final tomorrowStr = tomorrow.toIso8601String().substring(0, 10);

      final todayMeal = calendar.findDay(todayStr);
      final tomorrowMeal = calendar.findDay(tomorrowStr);

      await prefs.setBool(
        NotificationConstants.prefLunchLastKnownTodayBooked,
        todayMeal?.booked ?? false,
      );
      await prefs.setBool(
        NotificationConstants.prefLunchLastKnownTomorrowBooked,
        tomorrowMeal?.booked ?? false,
      );
      await prefs.setString(
        NotificationConstants.prefLunchLastSyncTime,
        DateTime.now().toIso8601String(),
      );

      return SteadfastLunchPingResult(
        success: true,
        message: 'Steadfast Lunch portal connected! (Live Active)',
        userName: 'Shakib Hossen',
        employeeCode: '4482',
        department: '2nd Floor (Zavisoft)',
        todayBooked: todayMeal?.booked,
        tomorrowBooked: tomorrowMeal?.booked,
        cutoffTime: calendar.cutoff,
      );
    } catch (e) {
      return SteadfastLunchPingResult(
        success: false,
        message: 'Error fetching meal details: $e',
      );
    }
  }

  /// Fetches meal calendar for given month (e.g. '2026-11')
  Future<SteadfastMealCalendar?> getMealCalendar({
    String? month,
    bool forceRefresh = false,
  }) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return null;

    final now = DateTime.now();
    final targetMonth =
        month ?? '${now.year}-${now.month.toString().padLeft(2, '0')}';

    if (!forceRefresh &&
        _cachedCalendar != null &&
        _cachedCalendar!.month == targetMonth) {
      return _cachedCalendar;
    }

    final loggedIn = await login();
    if (!loggedIn) return null;

    try {
      final client = http.Client();
      try {
        final uri = Uri.parse('$baseUrl/api/v1/profile/meal-calendar?month=$targetMonth');
        final resp = await client.get(
          uri,
          headers: _buildHeaders({
            'Content-Type': 'application/json',
          }),
        );
        _extractCookies(resp);

        if (resp.statusCode == 200) {
          final decoded = jsonDecode(resp.body);
          if (decoded is Map && decoded['data'] is Map) {
            _cachedCalendar = SteadfastMealCalendar.fromJson(
              decoded['data'] as Map<String, dynamic>,
            );
            return _cachedCalendar;
          }
        }
        debugPrint('SteadfastLunch: Calendar fetch returned HTTP ${resp.statusCode}');
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('SteadfastLunch: getMealCalendar error: $e');
    }

    return null;
  }

  /// Returns meal information for tomorrow
  Future<SteadfastDayMeal?> getTomorrowMealStatus() async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final tomorrowDateStr = tomorrow.toIso8601String().substring(0, 10);
    final monthStr = tomorrowDateStr.substring(0, 7);

    final calendar = await getMealCalendar(month: monthStr);
    return calendar?.findDay(tomorrowDateStr);
  }

  /// Returns meal information for today
  Future<SteadfastDayMeal?> getTodayMealStatus() async {
    final today = DateTime.now();
    final todayDateStr = today.toIso8601String().substring(0, 10);
    final monthStr = todayDateStr.substring(0, 7);

    final calendar = await getMealCalendar(month: monthStr);
    return calendar?.findDay(todayDateStr);
  }

  /// Toggles tomorrow's meal booking (ON or OFF)
  Future<SteadfastToggleResult> toggleTomorrowMeal({bool? forceSimulate}) async {
    final prefs = await SharedPreferences.getInstance();
    final isSim = (forceSimulate == true) ||
        (prefs.getBool(NotificationConstants.prefPacklySimulationMode) ?? false);

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final tomorrowDateStr = tomorrow.toIso8601String().substring(0, 10);

    if (isSim) {
      final currentBooked =
          prefs.getBool(NotificationConstants.prefLunchLastKnownTomorrowBooked) ?? false;
      return toggleMealDate(
        date: tomorrowDateStr,
        book: !currentBooked,
        forceSimulate: forceSimulate,
      );
    }

    final current = await getTomorrowMealStatus();
    final shouldBook = !(current?.booked ?? false);

    return toggleMealDate(
      date: tomorrowDateStr,
      book: shouldBook,
      forceSimulate: forceSimulate,
    );
  }

  /// Toggles meal booking for a specific date (e.g. '2026-11-12')
  Future<SteadfastToggleResult> toggleMealDate({
    required String date,
    required bool book,
    bool? forceSimulate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final isSim = (forceSimulate == true) ||
        (prefs.getBool(NotificationConstants.prefPacklySimulationMode) ?? false);

    if (isSim) {
      debugPrint('SteadfastLunch: Toggling $date in SIMULATION MODE.');
      await Future.delayed(const Duration(milliseconds: 800));

      final tomorrowStr = DateTime.now()
          .add(const Duration(days: 1))
          .toIso8601String()
          .substring(0, 10);
      if (date == tomorrowStr) {
        await prefs.setBool(
          NotificationConstants.prefLunchLastKnownTomorrowBooked,
          book,
        );
      }

      return SteadfastToggleResult(
        success: true,
        message: book
            ? '[TEST MODE] Tomorrow’s lunch successfully booked! (Lunch ON)'
            : '[TEST MODE] Tomorrow’s lunch cancelled! (Lunch OFF)',
        targetDate: date,
        isBooked: book,
      );
    }

    final targetMonth = date.substring(0, 7);
    final calendar = await getMealCalendar(month: targetMonth, forceRefresh: true);
    if (calendar == null) {
      return SteadfastToggleResult(
        success: false,
        message: 'Could not fetch current meal calendar from server.',
        targetDate: date,
        isBooked: !book,
      );
    }

    final targetDay = calendar.findDay(date);
    if (targetDay != null && targetDay.afterCutoff) {
      return SteadfastToggleResult(
        success: false,
        message: 'Cannot modify meal! Cutoff time (6:00 PM) for $date has already passed.',
        targetDate: date,
        isBooked: targetDay.booked,
      );
    }

    // Collect currently booked dates
    final bookedSet = calendar.days
        .where((d) => d.booked)
        .map((d) => d.date)
        .toSet();

    if (book) {
      bookedSet.add(date);
    } else {
      bookedSet.remove(date);
    }

    final sortedDates = bookedSet.toList()..sort();

    try {
      final client = http.Client();
      try {
        final putUrl = Uri.parse('$baseUrl/api/v1/profile/meal-calendar');
        final putBody = jsonEncode({
          'month': targetMonth,
          'dates': sortedDates,
        });

        final resp = await client.put(
          putUrl,
          headers: _buildHeaders({
            'Content-Type': 'application/json',
          }),
          body: putBody,
        );
        _extractCookies(resp);

        if (resp.statusCode == 200) {
          final decoded = jsonDecode(resp.body);
          final serverMessage = decoded is Map && decoded['message'] != null
              ? decoded['message'].toString()
              : (book ? 'Lunch booked for $date' : 'Lunch cancelled for $date');

          _cachedCalendar = null; // Invalidate cache
          final updatedCal = await getMealCalendar(month: targetMonth, forceRefresh: true);

          final tomorrowStr = DateTime.now()
              .add(const Duration(days: 1))
              .toIso8601String()
              .substring(0, 10);
          if (date == tomorrowStr) {
            await prefs.setBool(
              NotificationConstants.prefLunchLastKnownTomorrowBooked,
              book,
            );
          }

          return SteadfastToggleResult(
            success: true,
            message: serverMessage,
            targetDate: date,
            isBooked: book,
            calendar: updatedCal,
          );
        }

        return SteadfastToggleResult(
          success: false,
          message: 'Server error updating meal (HTTP ${resp.statusCode})',
          targetDate: date,
          isBooked: !book,
        );
      } finally {
        client.close();
      }
    } catch (e) {
      return SteadfastToggleResult(
        success: false,
        message: 'Exception updating meal: $e',
        targetDate: date,
        isBooked: !book,
      );
    }
  }
}
