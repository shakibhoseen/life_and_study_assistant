import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the office sentinel decided, written down where it can be read later.
///
/// The sentinel does its work while the phone is in a pocket, in a background
/// isolate, and `debugPrint` goes to logcat — which is only attached if
/// someone happened to be looking, and rolls over within hours either way.
/// When a morning's auto check-in does not fire, that is exactly the evidence
/// that has already gone.
///
/// These entries live in SharedPreferences, so every isolate writes to the
/// same list and it survives the process dying. Capped, because an unbounded
/// list in preferences is a file Android reads in full at every launch.
class SentinelLog {
  SentinelLog._();

  static const String _key = 'sentinel_event_log';

  /// Enough to cover a morning and an evening without growing without bound.
  static const int maxEntries = 150;

  /// Adds one line. Never throws: logging must not be able to break a punch.
  static Future<void> write(String event) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _append(prefs, event, DateTime.now());
    } catch (e) {
      debugPrint('SentinelLog: could not write "$event": $e');
    }
  }

  /// For callers that already hold a [SharedPreferences], and for tests that
  /// need to say when something happened.
  @visibleForTesting
  static Future<void> writeAt(
    SharedPreferences prefs,
    String event,
    DateTime at,
  ) => _append(prefs, event, at);

  static Future<void> _append(
    SharedPreferences prefs,
    String event,
    DateTime at,
  ) async {
    final stamp =
        '${at.day.toString().padLeft(2, '0')}/'
        '${at.month.toString().padLeft(2, '0')} '
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}:'
        '${at.second.toString().padLeft(2, '0')}';

    // Newest first: the question is almost always "what just happened".
    final entries = <String>['$stamp  $event', ...(prefs.getStringList(_key) ?? const [])];
    if (entries.length > maxEntries) {
      entries.removeRange(maxEntries, entries.length);
    }
    await prefs.setStringList(_key, entries);
  }

  /// Newest first.
  static Future<List<String>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_key) ?? const [];
    } catch (e) {
      debugPrint('SentinelLog: could not read: $e');
      return const [];
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (e) {
      debugPrint('SentinelLog: could not clear: $e');
    }
  }
}
