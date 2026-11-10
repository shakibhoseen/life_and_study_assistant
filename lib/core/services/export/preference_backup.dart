import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';

/// The settings that live outside the database.
///
/// Half of what makes the app yours is not in a table: which model to use,
/// whether the scanner trusts printed answers, which of today's tasks are
/// ticked off, the dashboard sections you folded away. A backup that brought
/// back the questions and none of that left somebody setting the app up again
/// from memory.
///
/// **The API key is never written to the file.** A backup goes to the
/// Downloads folder, gets copied to a laptop, mailed to oneself — a key in
/// plain text in all of those places is a key that leaks. It is named in
/// [skippedKeys] so the restore can say plainly that it has to be entered
/// again, which takes one paste.
class PreferenceBackup {
  const PreferenceBackup._();

  /// Secrets, and things that mean nothing on another day or another install.
  static const Set<String> excluded = {
    NotificationConstants.prefGeminiApiKey,
    // Written by the floating bubble while it is open; restoring a stale
    // draft would put yesterday's half-sentence back on screen.
    'bubble_pending_titles',
    'bubble_opened_app',
    'bubble_draft_text',
  };

  /// What was deliberately left out, for the restore to report.
  static List<String> skippedKeys(Map<String, Object?> saved) =>
      excluded.where((k) => !saved.containsKey(k)).toList();

  /// Everything worth carrying, as plain JSON values.
  static Future<Map<String, Object?>> collect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final out = <String, Object?>{};
    for (final key in prefs.getKeys()) {
      if (excluded.contains(key)) continue;
      final value = prefs.get(key);
      // Only the types SharedPreferences can give back. Anything else would
      // decode to something it cannot store.
      if (value is bool || value is int || value is double || value is String) {
        out[key] = value;
      } else if (value is List<String>) {
        out[key] = value;
      }
    }
    return out;
  }

  /// Puts them back. Returns how many were written.
  ///
  /// Existing values are overwritten, because a restore is the user saying
  /// they want the saved state — but the excluded keys are never touched, so
  /// a key entered since the backup survives the restore.
  static Future<int> restore(Object? raw) async {
    if (raw is! Map) return 0;
    final prefs = await SharedPreferences.getInstance();

    var written = 0;
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      if (excluded.contains(key)) continue;
      final value = entry.value;

      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is List) {
        await prefs.setStringList(
          key,
          value.map((e) => e.toString()).toList(),
        );
      } else {
        continue;
      }
      written++;
    }
    return written;
  }
}
