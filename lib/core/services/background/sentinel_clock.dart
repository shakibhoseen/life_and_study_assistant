import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The clock the office sentinel reads, so its time-of-day rules can be tried
/// without waiting for the time of day.
///
/// Check-in only runs between 8:40 and 10:00 and check-out between 17:45 and
/// 22:30. Testing either meant being at the office at the right hour and
/// hoping, which is how a broken morning goes unnoticed until it costs an
/// attendance record.
///
/// The pretend time **expires**. This is the clock an attendance system makes
/// its decisions on; an override left on by accident would quietly stop a
/// real morning from working, and the person who set it would be the last to
/// suspect it. After [validFor] it is ignored, whatever is still stored.
class SentinelClock {
  SentinelClock._();

  static const String prefFakeNow = 'sentinel_fake_now';
  static const String prefFakeNowSetAt = 'sentinel_fake_now_set_at';

  /// Long enough to watch a window open, act and close. Not long enough to
  /// still be in force tomorrow morning.
  static const Duration validFor = Duration(minutes: 30);

  /// The time the sentinel should treat as now.
  ///
  /// The pretend clock runs: it advances by however long has really passed
  /// since it was set, so a sentinel polling every five seconds sees time
  /// move and windows open and shut, rather than being frozen on one instant.
  static DateTime now(SharedPreferences prefs, {DateTime? realNow}) {
    final real = realNow ?? DateTime.now();
    try {
      final fake = prefs.getString(prefFakeNow);
      final setAt = prefs.getString(prefFakeNowSetAt);
      if (fake == null || setAt == null) return real;

      final pretend = DateTime.tryParse(fake);
      final from = DateTime.tryParse(setAt);
      if (pretend == null || from == null) return real;

      final elapsed = real.difference(from);
      // Negative means the device clock moved backwards since it was set;
      // trusting the override then could put it anywhere.
      if (elapsed.isNegative || elapsed > validFor) return real;

      return pretend.add(elapsed);
    } catch (e) {
      debugPrint('SentinelClock: ignoring override: $e');
      return real;
    }
  }

  /// True when an override is set and still inside its window.
  static bool isOverridden(SharedPreferences prefs, {DateTime? realNow}) {
    final real = realNow ?? DateTime.now();
    return now(prefs, realNow: real) != real;
  }

  static Future<void> pretendItIs(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefFakeNow, time.toIso8601String());
    await prefs.setString(prefFakeNowSetAt, DateTime.now().toIso8601String());
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefFakeNow);
    await prefs.remove(prefFakeNowSetAt);
  }
}
