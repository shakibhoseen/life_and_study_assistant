import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which of a day's micro-commitments have been finished.
///
/// They were not remembered at all. Ticking one off updated the Riverpod state
/// and nothing else, and the day's plan is re-read from its cache whenever the
/// provider rebuilds — so the tick came back off, every time, and finishing a
/// task left no trace that it had ever been done.
///
/// Kept per day, because the plan is per day. A task finished on Tuesday says
/// nothing about Wednesday's plan, and Wednesday's ids will differ anyway.
class StudyTaskCompletions {
  StudyTaskCompletions._();
  static final StudyTaskCompletions instance = StudyTaskCompletions._();

  static const String _prefix = 'study_tasks_done_';

  /// How many days of these are kept.
  ///
  /// Each is a short list of ids. Old days are swept rather than left to
  /// accumulate for ever in a preferences file that is read in full at launch.
  static const int keepDays = 14;

  /// Today, in the form the plan itself uses for its date.
  static String today() =>
      DateTime.now().toIso8601String().substring(0, 10);

  /// The ids finished on [date].
  Future<Set<String>> load(String date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return (prefs.getStringList('$_prefix$date') ?? const <String>[]).toSet();
    } catch (e) {
      debugPrint('Task completions could not be read: $e');
      return <String>{};
    }
  }

  /// Records that [taskId] is finished, or is not.
  Future<void> setCompleted(
    String date,
    String taskId, {
    required bool done,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefix$date';
      final ids = (prefs.getStringList(key) ?? const <String>[]).toSet();
      if (done) {
        ids.add(taskId);
      } else {
        ids.remove(taskId);
      }
      if (ids.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setStringList(key, ids.toList()..sort());
      }
      await _sweepOldDays(prefs);
    } catch (e) {
      debugPrint('Task completions could not be saved: $e');
    }
  }

  /// Drops the days nobody is going to look at again.
  Future<void> _sweepOldDays(SharedPreferences prefs) async {
    final cutoff = DateTime.now().subtract(Duration(days: keepDays));
    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith(_prefix)) continue;
      final date = DateTime.tryParse(key.substring(_prefix.length));
      if (date != null && date.isBefore(cutoff)) {
        await prefs.remove(key);
      }
    }
  }

  /// Everything, for the one case where it all has to go.
  @visibleForTesting
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(_prefix)) await prefs.remove(key);
    }
  }
}
