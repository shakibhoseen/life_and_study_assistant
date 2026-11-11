import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';

class PacklyAttendanceStatus {
  final bool isCheckedIn;
  final bool isCheckedOut;
  final String? checkInTime;
  final String? checkOutTime;
  final String statusText;
  final bool isLate;
  final String? rawDate;

  const PacklyAttendanceStatus({
    required this.isCheckedIn,
    required this.isCheckedOut,
    this.checkInTime,
    this.checkOutTime,
    required this.statusText,
    this.isLate = false,
    this.rawDate,
  });

  @override
  String toString() =>
      'PacklyAttendanceStatus(checkedIn: $isCheckedIn, checkedOut: $isCheckedOut, time: $checkInTime, late: $isLate, status: $statusText)';
}

class PacklyResult {
  final bool success;
  final String message;
  final PacklyAttendanceStatus? status;

  const PacklyResult({
    required this.success,
    required this.message,
    this.status,
  });
}

class PacklyPingResult {
  final bool success;
  final String message;
  final String? employeeName;

  const PacklyPingResult({
    required this.success,
    required this.message,
    this.employeeName,
  });
}

class PacklyHoliday {
  final String name;
  final DateTime startDate;
  final DateTime endDate;

  const PacklyHoliday({
    required this.name,
    required this.startDate,
    required this.endDate,
  });

  bool containsDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    return (d.isAtSameMomentAs(s) || d.isAfter(s)) &&
        (d.isAtSameMomentAs(e) || d.isBefore(e));
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
      };

  factory PacklyHoliday.fromJson(Map<String, dynamic> json) => PacklyHoliday(
        name: json['name'] as String,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
      );
}

class PacklyAttendanceService {
  PacklyAttendanceService._();
  static final PacklyAttendanceService instance = PacklyAttendanceService._();

  static const String baseUrl = 'https://zavisoft.packlybd.com';
  static const String defaultEmail = 'shakibhossen100@gmail.com';
  static const String defaultPassword = '01798747299';

  final Map<String, String> _cookies = {};
  String? _csrfToken;
  DateTime? _lastLoginTime;

  /// Header helper with current cookies
  Map<String, String> _buildHeaders([Map<String, String>? extra]) {
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    };
    if (_cookies.isNotEmpty) {
      headers['Cookie'] =
          _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }
    if (extra != null) {
      headers.addAll(extra);
    }
    return headers;
  }

  void _extractCookies(http.Response response) {
    final rawSetCookie = response.headers['set-cookie'];
    if (rawSetCookie == null || rawSetCookie.isEmpty) return;

    // Split cookies, taking into account multiple comma-separated Set-Cookie headers
    final cookieParts = rawSetCookie.split(RegExp(r',(?=\s*[A-Za-z0-9_\-]+=)'));
    for (final part in cookieParts) {
      final keyVal = part.split(';').first.trim();
      final eqIdx = keyVal.indexOf('=');
      if (eqIdx != -1) {
        final key = keyVal.substring(0, eqIdx).trim();
        final val = keyVal.substring(eqIdx + 1).trim();
        if (key.isNotEmpty) {
          _cookies[key] = val;
        }
      }
    }
  }

  String? _extractCsrf(String html) {
    // 1. Meta tag
    final metaMatch =
        RegExp(r'<meta\s+name="csrf-token"\s+content="([^"]+)"', caseSensitive: false)
            .firstMatch(html);
    if (metaMatch != null) return metaMatch.group(1);

    // 2. Hidden input
    final inputMatch =
        RegExp(r'<input[^>]+name="_token"[^>]+value="([^"]+)"', caseSensitive: false)
            .firstMatch(html);
    if (inputMatch != null) return inputMatch.group(1);

    final inputMatchAlt =
        RegExp(r'value="([^"]+)"[^>]+name="_token"', caseSensitive: false)
            .firstMatch(html);
    if (inputMatchAlt != null) return inputMatchAlt.group(1);

    return null;
  }

  /// Simple hash identical to Packly web app's simpleHash (djb2 variant)
  static String simpleHash(String str) {
    int hash = 5381;
    for (int i = 0; i < str.length; i++) {
      hash = (((hash << 5) + hash) + str.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  /// Log in to Packly portal and store session
  Future<bool> login({String? email, String? password, bool forceRefresh = false}) async {
    // If logged in recently (within 4 hours), reuse session unless forced
    if (!forceRefresh &&
        _lastLoginTime != null &&
        DateTime.now().difference(_lastLoginTime!).inHours < 4 &&
        _cookies.containsKey('packly-leave-management-session')) {
      return true;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final loginEmail = email ??
          prefs.getString(NotificationConstants.prefPacklyEmail) ??
          defaultEmail;
      final loginPassword = password ??
          prefs.getString(NotificationConstants.prefPacklyPassword) ??
          defaultPassword;

      final client = http.Client();
      try {
        // 1. GET login page to obtain initial cookies and CSRF token
        final getResp = await client.get(
          Uri.parse('$baseUrl/login'),
          headers: _buildHeaders(),
        );
        _extractCookies(getResp);

        final token = _extractCsrf(getResp.body);
        if (token == null) {
          debugPrint('PacklyAttendance: Failed to extract CSRF token from login page');
          return false;
        }
        _csrfToken = token;

        // 2. POST login credentials
        final postResp = await client.post(
          Uri.parse('$baseUrl/login'),
          headers: _buildHeaders({
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': '$baseUrl/login',
          }),
          body: {
            '_token': token,
            'login': loginEmail,
            'password': loginPassword,
          },
        );
        _extractCookies(postResp);

        if (postResp.statusCode == 302 ||
            postResp.statusCode == 200 ||
            postResp.body.contains('dashboard') ||
            postResp.headers['location']?.contains('dashboard') == true) {
          _lastLoginTime = DateTime.now();
          debugPrint('PacklyAttendance: Login successful for $loginEmail');
          return true;
        }

        debugPrint('PacklyAttendance: Login failed with status ${postResp.statusCode}');
        return false;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('PacklyAttendance: Login exception: $e');
      return false;
    }
  }

  /// Ping / Test connection to Packly attendance portal
  Future<PacklyPingResult> ping({String? email, String? password}) async {
    final prefs = await SharedPreferences.getInstance();
    final isSim = prefs.getBool(NotificationConstants.prefPacklySimulationMode) ?? false;
    if (isSim) {
      return const PacklyPingResult(
        success: true,
        message: '[TEST MODE] Connected to Packly Attendance (Mock)',
        employeeName: 'Shakib Hossen (Simulation)',
      );
    }

    final ok = await login(email: email, password: password, forceRefresh: true);
    if (!ok) {
      return const PacklyPingResult(
        success: false,
        message: 'Packly Login failed! Please check email and password in Settings.',
      );
    }

    return const PacklyPingResult(
      success: true,
      message: 'Packly Attendance connected successfully! (Live Active)',
      employeeName: 'Shakib Hossen',
    );
  }

  /// Fetches client IP reported by Packly server
  Future<String> getClientIp() async {
    try {
      final client = http.Client();
      try {
        final resp = await client.get(
          Uri.parse('$baseUrl/api/get-ip'),
          headers: _buildHeaders(),
        );
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          if (data is Map && data['ip'] != null) {
            return data['ip'].toString();
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('PacklyAttendance: Error fetching IP: $e');
    }
    return '';
  }

  /// Reverse geocode coordinates using OpenStreetMap Nominatim
  Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final client = http.Client();
      try {
        final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
        );
        final resp = await client.get(
          url,
          headers: {'User-Agent': 'PacklyApp/1.0 (info@packly.com)'},
        );
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          if (data is Map) {
            if (data['display_name'] != null) {
              return data['display_name'].toString();
            }
            if (data['address'] is Map) {
              final addr = data['address'] as Map;
              final parts = [
                addr['road'] ?? addr['street'],
                addr['city'] ?? addr['town'] ?? addr['village'],
                addr['state'] ?? addr['region'],
                addr['country'],
              ].where((p) => p != null && p.toString().isNotEmpty).join(', ');
              if (parts.isNotEmpty) return parts;
            }
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('PacklyAttendance: Reverse geocode error: $e');
    }
    return 'Location captured';
  }

  /// Get today's attendance status from portal
  Future<PacklyAttendanceStatus> getAttendanceStatus({bool? forceSimulate}) async {
    final prefs = await SharedPreferences.getInstance();
    final isSim = (forceSimulate == true) ||
        (prefs.getBool(NotificationConstants.prefPacklySimulationMode) ?? false);

    if (isSim) {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final lastCheckinDate = prefs.getString(NotificationConstants.prefLastCheckInDate);
      final lastCheckinStatus = prefs.getString(NotificationConstants.prefLastCheckInStatus);
      final lastCheckinTime = prefs.getString(NotificationConstants.prefLastCheckInTime);
      final lastCheckoutDate = prefs.getString(NotificationConstants.prefLastCheckOutDate);
      final lastCheckoutTime = prefs.getString(NotificationConstants.prefLastCheckOutTime);
      final isLate = prefs.getBool(NotificationConstants.prefLastCheckInIsLate) ?? false;

      final isCheckedIn = lastCheckinDate == today &&
          (lastCheckinStatus == 'Punched In' || lastCheckinStatus == 'Punched');
      final isCheckedOut = lastCheckoutDate == today && lastCheckoutTime != null;

      return PacklyAttendanceStatus(
        isCheckedIn: isCheckedIn,
        isCheckedOut: isCheckedOut,
        checkInTime: lastCheckinTime,
        checkOutTime: lastCheckoutTime,
        statusText: isCheckedOut
            ? 'Workday Completed (Test Mode)'
            : (isCheckedIn ? 'In Progress (Test Mode)' : 'Not Checked In (Test Mode)'),
        isLate: isLate,
      );
    }

    final loggedIn = await login();
    if (!loggedIn) {
      return const PacklyAttendanceStatus(
        isCheckedIn: false,
        isCheckedOut: false,
        statusText: 'Authentication Required',
      );
    }

    try {
      final client = http.Client();
      try {
        // Fetch /attendance/history
        final histResp = await client.get(
          Uri.parse('$baseUrl/attendance/history'),
          headers: _buildHeaders(),
        );
        _extractCookies(histResp);

        final html = histResp.body;
        // Search table rows for today
        // Format e.g.: Wed, Nov 11, 2026   09:19:26 AM LATE   —   —   —   In Progress
        final rows = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true).allMatches(html);

        final now = DateTime.now();
        final nowMonthStr = _shortMonthName(now.month);
        final nowDayStr = now.day.toString();

        for (final rowMatch in rows) {
          final rowHtml = rowMatch.group(1) ?? '';
          final cleanText = rowHtml
              .replaceAll(RegExp(r'<[^>]+>'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();

          // Check if this row is for today
          if (cleanText.contains(nowMonthStr) && cleanText.contains(nowDayStr)) {
            final isLate = cleanText.contains('LATE');

            // Extract check-in time e.g. "09:19:26 AM"
            final timeMatch =
                RegExp(r'(\d{2}:\d{2}:\d{2}\s+(?:AM|PM))').firstMatch(cleanText);
            final checkInTime = timeMatch?.group(1);

            // Extract check-out time if not "—"
            String? checkOutTime;
            final times = RegExp(r'(\d{2}:\d{2}:\d{2}\s+(?:AM|PM))')
                .allMatches(cleanText)
                .map((m) => m.group(1)!)
                .toList();
            if (times.length > 1) {
              checkOutTime = times[1];
            }

            final isCheckedIn = checkInTime != null;
            final isCheckedOut = checkOutTime != null;

            final statusText = isCheckedOut
                ? 'Workday Completed'
                : (isCheckedIn ? 'In Progress' : 'Not Checked In');

            // Save in prefs
            final prefs = await SharedPreferences.getInstance();
            final todayIso = now.toIso8601String().substring(0, 10);
            if (isCheckedIn) {
              await prefs.setString(NotificationConstants.prefLastCheckInDate, todayIso);
              await prefs.setString(NotificationConstants.prefLastCheckInStatus, 'Punched In');
              await prefs.setString(NotificationConstants.prefLastCheckInTime, checkInTime);
              await prefs.setBool(NotificationConstants.prefLastCheckInIsLate, isLate);
            }
            if (isCheckedOut) {
              await prefs.setString(NotificationConstants.prefLastCheckOutDate, todayIso);
              await prefs.setString(NotificationConstants.prefLastCheckOutTime, checkOutTime);
            }

            return PacklyAttendanceStatus(
              isCheckedIn: isCheckedIn,
              isCheckedOut: isCheckedOut,
              checkInTime: checkInTime,
              checkOutTime: checkOutTime,
              statusText: statusText,
              isLate: isLate,
              rawDate: cleanText,
            );
          }
        }

        // If no today's row in history, check dashboard directly
        final dashResp = await client.get(
          Uri.parse('$baseUrl/dashboard'),
          headers: _buildHeaders(),
        );
        _extractCookies(dashResp);

        final dashHtml = dashResp.body;
        final hasCheckOutForm = dashHtml.contains('checkOutForm');
        final hasCheckInForm = dashHtml.contains('checkInForm');

        if (hasCheckOutForm) {
          return const PacklyAttendanceStatus(
            isCheckedIn: true,
            isCheckedOut: false,
            statusText: 'In Progress',
          );
        }

        return PacklyAttendanceStatus(
          isCheckedIn: false,
          isCheckedOut: false,
          statusText: hasCheckInForm ? 'Not Checked In' : 'Attendance Ready',
        );
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('PacklyAttendance: Error fetching attendance status: $e');
      return PacklyAttendanceStatus(
        isCheckedIn: false,
        isCheckedOut: false,
        statusText: 'Error: $e',
      );
    }
  }

  String _shortMonthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  static const Map<String, int> _monthMap = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  List<PacklyHoliday> _cachedHolidays = [];

  /// Fetches official company holidays from /holidays and caches them
  Future<List<PacklyHoliday>> fetchHolidays({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh && _cachedHolidays.isNotEmpty) {
      return _cachedHolidays;
    }

    // Try loading from prefs cache first if fresh (less than 24h old)
    if (!forceRefresh) {
      final cachedJsonStr =
          prefs.getString(NotificationConstants.prefPacklyHolidaysCache);
      final lastSyncStr =
          prefs.getString(NotificationConstants.prefPacklyHolidaysLastSync);
      if (cachedJsonStr != null && lastSyncStr != null) {
        final lastSync = DateTime.tryParse(lastSyncStr);
        if (lastSync != null &&
            DateTime.now().difference(lastSync).inHours < 24) {
          try {
            final List decoded = jsonDecode(cachedJsonStr);
            _cachedHolidays = decoded
                .map((item) =>
                    PacklyHoliday.fromJson(item as Map<String, dynamic>))
                .toList();
            return _cachedHolidays;
          } catch (e) {
            debugPrint('Error decoding cached holidays: $e');
          }
        }
      }
    }

    final loggedIn = await login();
    if (!loggedIn) {
      return _cachedHolidays;
    }

    try {
      final client = http.Client();
      try {
        final resp = await client.get(
          Uri.parse('$baseUrl/holidays'),
          headers: _buildHeaders(),
        );
        _extractCookies(resp);

        final html = resp.body;
        final rowRegex = RegExp(
          r'<tr[^>]*>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>',
          dotAll: true,
        );
        final matches = rowRegex.allMatches(html);

        final holidays = <PacklyHoliday>[];

        for (final m in matches) {
          final dateCol = (m.group(1) ?? '')
              .replaceAll(RegExp(r'<[^>]+>'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          final nameCol = (m.group(2) ?? '')
              .replaceAll(RegExp(r'<[^>]+>'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();

          if (dateCol.isEmpty || nameCol.isEmpty || dateCol == 'Date') continue;

          // Find date parts e.g. "16 Dec 2026" or "19 Mar 2026 → 23 Mar 2026"
          final dateMatches =
              RegExp(r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})').allMatches(dateCol);

          if (dateMatches.isNotEmpty) {
            final parsedDates = <DateTime>[];
            for (final dm in dateMatches) {
              final day = int.tryParse(dm.group(1) ?? '');
              final monStr = (dm.group(2) ?? '').toLowerCase();
              final year = int.tryParse(dm.group(3) ?? '');
              final mon = _monthMap[monStr];
              if (day != null && mon != null && year != null) {
                parsedDates.add(DateTime(year, mon, day));
              }
            }

            if (parsedDates.isNotEmpty) {
              final start = parsedDates.first;
              final end = parsedDates.length > 1 ? parsedDates[1] : start;
              holidays.add(PacklyHoliday(
                name: nameCol,
                startDate: start,
                endDate: end,
              ));
            }
          }
        }

        if (holidays.isNotEmpty) {
          _cachedHolidays = holidays;
          await prefs.setString(
            NotificationConstants.prefPacklyHolidaysCache,
            jsonEncode(holidays.map((h) => h.toJson()).toList()),
          );
          await prefs.setString(
            NotificationConstants.prefPacklyHolidaysLastSync,
            DateTime.now().toIso8601String(),
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Error fetching holidays from Packly: $e');
    }

    return _cachedHolidays;
  }

  /// Checks if given date falls on an official Packly holiday
  Future<PacklyHoliday?> getHolidayForDate(DateTime date) async {
    final list = await fetchHolidays();
    for (final h in list) {
      if (h.containsDate(date)) {
        return h;
      }
    }
    return null;
  }

  /// Perform Check-In
  Future<PacklyResult> checkIn({
    double? latitude,
    double? longitude,
    String? locationName,
    bool? forceSimulate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final isSim = (forceSimulate == true) ||
        (prefs.getBool(NotificationConstants.prefPacklySimulationMode) ?? false);

    if (isSim) {
      debugPrint('PacklyAttendance: Running in SIMULATION MODE. Zero server hits.');
      await Future.delayed(const Duration(milliseconds: 900));
      final now = DateTime.now();
      final nowTimeStr =
          '${(now.hour % 12 == 0 ? 12 : now.hour % 12).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';
      final isLate = (now.hour > 9) || (now.hour == 9 && now.minute >= 15);
      final todayIso = now.toIso8601String().substring(0, 10);

      await prefs.setString(NotificationConstants.prefLastCheckInDate, todayIso);
      await prefs.setString(NotificationConstants.prefLastCheckInStatus, 'Punched In');
      await prefs.setString(NotificationConstants.prefLastCheckInTime, nowTimeStr);
      await prefs.setBool(NotificationConstants.prefLastCheckInIsLate, isLate);

      final status = PacklyAttendanceStatus(
        isCheckedIn: true,
        isCheckedOut: false,
        checkInTime: nowTimeStr,
        statusText: 'In Progress (Test Mode)',
        isLate: isLate,
      );

      return PacklyResult(
        success: true,
        message: '[TEST MODE] Simulated Check-In at $nowTimeStr (${isLate ? 'LATE' : 'On-Time ✓'})',
        status: status,
      );
    }

    // Safety guard against duplicate punches today
    final todayIso = DateTime.now().toIso8601String().substring(0, 10);
    final lastCheckinDate =
        prefs.getString(NotificationConstants.prefLastCheckInDate);
    final lastCheckinStatus =
        prefs.getString(NotificationConstants.prefLastCheckInStatus);
    if (lastCheckinDate == todayIso &&
        (lastCheckinStatus == 'Punched In' || lastCheckinStatus == 'Punched')) {
      final savedTime =
          prefs.getString(NotificationConstants.prefLastCheckInTime) ?? 'Already Recorded';
      return PacklyResult(
        success: true,
        message: 'Already checked in today at $savedTime (Duplicate prevented).',
        status: await getAttendanceStatus(),
      );
    }

    final loggedIn = await login();
    if (!loggedIn) {
      return const PacklyResult(
        success: false,
        message: 'Could not log in to Zavisoft Packly.',
      );
    }

    try {
      final client = http.Client();
      try {
        // 1. Obtain location if not provided
        double lat = latitude ?? 0.0;
        double lng = longitude ?? 0.0;
        String locName = locationName ?? '';

        if (lat == 0.0 || lng == 0.0) {
          try {
            final hasPerm = await Geolocator.checkPermission();
            if (hasPerm == LocationPermission.always ||
                hasPerm == LocationPermission.whileInUse) {
              final pos = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high,
                  timeLimit: Duration(seconds: 12),
                ),
              );
              lat = pos.latitude;
              lng = pos.longitude;
            }
          } catch (e) {
            debugPrint('PacklyAttendance: Geolocator error: $e');
          }
        }

        // If coordinates still 0, check if office coordinates are saved in prefs
        final prefs = await SharedPreferences.getInstance();
        if (lat == 0.0 || lng == 0.0) {
          lat = prefs.getDouble(NotificationConstants.prefOfficeLatitude) ?? 23.7925;
          lng = prefs.getDouble(NotificationConstants.prefOfficeLongitude) ?? 90.4078;
        }

        if (locName.isEmpty) {
          locName = prefs.getString(NotificationConstants.prefOfficeAddress) ??
              await reverseGeocode(lat, lng);
        }

        // Save office coordinates if not already saved
        if (prefs.getDouble(NotificationConstants.prefOfficeLatitude) == null && lat != 0.0) {
          await prefs.setDouble(NotificationConstants.prefOfficeLatitude, lat);
          await prefs.setDouble(NotificationConstants.prefOfficeLongitude, lng);
          await prefs.setString(NotificationConstants.prefOfficeAddress, locName);
        }

        // 2. Fetch fresh page to get CSRF token
        final pageResp = await client.get(
          Uri.parse('$baseUrl/dashboard'),
          headers: _buildHeaders(),
        );
        _extractCookies(pageResp);
        final token = _extractCsrf(pageResp.body) ?? _csrfToken;
        if (token == null) {
          return const PacklyResult(
            success: false,
            message: 'Failed to retrieve CSRF token for check-in.',
          );
        }

        // 3. Client IP
        final clientIp = await getClientIp();

        // 4. Fingerprint
        final fpHash = simpleHash(
            'PacklyApp###${DateTime.now().timeZoneOffset.inMinutes}###${lat.toStringAsFixed(4)}x${lng.toStringAsFixed(4)}');

        // 5. Submit Check-In
        final checkInResp = await client.post(
          Uri.parse('$baseUrl/attendance/check-in'),
          headers: _buildHeaders({
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': '$baseUrl/dashboard',
          }),
          body: {
            '_token': token,
            'client_ip': clientIp,
            'latitude': lat.toStringAsFixed(8),
            'longitude': lng.toStringAsFixed(8),
            'location_name': locName,
            'device_fingerprint': fpHash,
            'deviceFingerprint': fpHash,
          },
        );
        _extractCookies(checkInResp);

        final now = DateTime.now();
        final nowTimeStr =
            '${(now.hour % 12 == 0 ? 12 : now.hour % 12).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';
        final isLate = (now.hour > 9) || (now.hour == 9 && now.minute >= 15);

        // Update local prefs
        final todayIso = now.toIso8601String().substring(0, 10);
        await prefs.setString(NotificationConstants.prefLastCheckInDate, todayIso);
        await prefs.setString(NotificationConstants.prefLastCheckInStatus, 'Punched In');
        await prefs.setString(NotificationConstants.prefLastCheckInTime, nowTimeStr);
        await prefs.setBool(NotificationConstants.prefLastCheckInIsLate, isLate);

        final newStatus = await getAttendanceStatus();

        if (checkInResp.statusCode == 302 ||
            checkInResp.statusCode == 200 ||
            newStatus.isCheckedIn) {
          return PacklyResult(
            success: true,
            message: isLate
                ? 'Check-In recorded at $nowTimeStr (LATE: After 9:14 AM)'
                : 'Check-In successful at $nowTimeStr (On-Time ✓)',
            status: newStatus,
          );
        }

        return PacklyResult(
          success: false,
          message: 'Check-In rejected by portal (Status: ${checkInResp.statusCode})',
          status: newStatus,
        );
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('PacklyAttendance: checkIn error: $e');
      return PacklyResult(
        success: false,
        message: 'Check-in error: $e',
      );
    }
  }

  /// Perform Check-Out
  Future<PacklyResult> checkOut({
    double? latitude,
    double? longitude,
    String? locationName,
    bool? forceSimulate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final isSim = (forceSimulate == true) ||
        (prefs.getBool(NotificationConstants.prefPacklySimulationMode) ?? false);

    if (isSim) {
      debugPrint('PacklyAttendance: Running in SIMULATION MODE. Zero server hits.');
      await Future.delayed(const Duration(milliseconds: 900));
      final now = DateTime.now();
      final nowTimeStr =
          '${(now.hour % 12 == 0 ? 12 : now.hour % 12).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';
      final todayIso = now.toIso8601String().substring(0, 10);

      await prefs.setString(NotificationConstants.prefLastCheckOutDate, todayIso);
      await prefs.setString(NotificationConstants.prefLastCheckOutTime, nowTimeStr);

      final status = PacklyAttendanceStatus(
        isCheckedIn: true,
        isCheckedOut: true,
        checkInTime: prefs.getString(NotificationConstants.prefLastCheckInTime) ?? '09:00:00 AM',
        checkOutTime: nowTimeStr,
        statusText: 'Workday Completed (Test Mode)',
      );

      return PacklyResult(
        success: true,
        message: '[TEST MODE] Simulated Check-Out at $nowTimeStr',
        status: status,
      );
    }

    final todayIso = DateTime.now().toIso8601String().substring(0, 10);
    final lastCheckOutDate =
        prefs.getString(NotificationConstants.prefLastCheckOutDate);
    final lastCheckOutTime =
        prefs.getString(NotificationConstants.prefLastCheckOutTime);
    final isUpdate = (lastCheckOutDate == todayIso && lastCheckOutTime != null);

    final loggedIn = await login();
    if (!loggedIn) {
      return const PacklyResult(
        success: false,
        message: 'Could not log in to Zavisoft Packly.',
      );
    }

    try {
      final client = http.Client();
      try {
        // 1. Obtain location
        double lat = latitude ?? 0.0;
        double lng = longitude ?? 0.0;
        String locName = locationName ?? '';

        final prefs = await SharedPreferences.getInstance();

        if (lat == 0.0 || lng == 0.0) {
          try {
            final hasPerm = await Geolocator.checkPermission();
            if (hasPerm == LocationPermission.always ||
                hasPerm == LocationPermission.whileInUse) {
              final pos = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high,
                  timeLimit: Duration(seconds: 12),
                ),
              );
              lat = pos.latitude;
              lng = pos.longitude;
            }
          } catch (e) {
            debugPrint('PacklyAttendance: Geolocator checkout error: $e');
          }
        }

        // If coordinates still 0, fallback to saved office coordinates
        if (lat == 0.0 || lng == 0.0) {
          lat = prefs.getDouble(NotificationConstants.prefOfficeLatitude) ?? 23.7925;
          lng = prefs.getDouble(NotificationConstants.prefOfficeLongitude) ?? 90.4078;
        }

        if (locName.isEmpty) {
          locName = prefs.getString(NotificationConstants.prefOfficeAddress) ??
              await reverseGeocode(lat, lng);
        }

        // 2. CSRF Token
        final pageResp = await client.get(
          Uri.parse('$baseUrl/dashboard'),
          headers: _buildHeaders(),
        );
        _extractCookies(pageResp);
        final token = _extractCsrf(pageResp.body) ?? _csrfToken;
        if (token == null) {
          return const PacklyResult(
            success: false,
            message: 'Failed to retrieve CSRF token for check-out.',
          );
        }

        // 3. Client IP
        final clientIp = await getClientIp();

        // 4. Submit Check-Out
        final checkOutResp = await client.post(
          Uri.parse('$baseUrl/attendance/check-out'),
          headers: _buildHeaders({
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': '$baseUrl/dashboard',
          }),
          body: {
            '_token': token,
            'client_ip': clientIp,
            'latitude': lat.toStringAsFixed(8),
            'longitude': lng.toStringAsFixed(8),
            'location_name': locName,
          },
        );
        _extractCookies(checkOutResp);

        final now = DateTime.now();
        final nowTimeStr =
            '${(now.hour % 12 == 0 ? 12 : now.hour % 12).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';

        final todayIso = now.toIso8601String().substring(0, 10);
        await prefs.setString(NotificationConstants.prefLastCheckOutDate, todayIso);
        await prefs.setString(NotificationConstants.prefLastCheckOutTime, nowTimeStr);

        final newStatus = await getAttendanceStatus();

        if (checkOutResp.statusCode == 302 ||
            checkOutResp.statusCode == 200 ||
            newStatus.isCheckedOut) {
          return PacklyResult(
            success: true,
            message: isUpdate
                ? 'Check-Out updated to $nowTimeStr (Overtime / Latest punch recorded ✓)'
                : 'Check-Out successful at $nowTimeStr. Have a great evening!',
            status: newStatus,
          );
        }

        return PacklyResult(
          success: false,
          message: 'Check-Out response status: ${checkOutResp.statusCode}',
          status: newStatus,
        );
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('PacklyAttendance: checkOut error: $e');
      return PacklyResult(
        success: false,
        message: 'Check-out error: $e',
      );
    }
  }
}
