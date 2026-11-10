import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/app_database.dart';
import 'app_export_service.dart';
import 'preference_backup.dart';

/// Writes a backup on its own, so that there is always a recent one.
///
/// The manual backup in Settings worked perfectly and had never been used,
/// which is the ordinary fate of a button that has to be remembered. Then an
/// install wiped the app's data and there was nothing to go back to: months of
/// scanned questions, the mistake notebook, the drill history, gone.
///
/// So this runs at launch, at most once a day, and keeps the last few. It
/// costs a file of a few hundred kilobytes and asks nothing of anybody.
///
/// It never touches the manual backups: those are named differently and are
/// never pruned. Only its own files are counted and rolled.
class AutoBackupService {
  const AutoBackupService._();

  /// How many of its own files to keep. A week of daily copies is enough to
  /// get back behind a mistake noticed late, and small enough to ignore.
  static const int keepCount = 7;

  static const Duration interval = Duration(hours: 24);

  static const String prefLastRun = 'auto_backup_last_run';

  /// The prefix that marks a file as this service's to prune.
  static const String filePrefix = 'auto_backup_';

  /// Writes one if enough time has passed. Returns the file, or null when
  /// nothing was due or nothing could be written.
  ///
  /// Failure is quiet on purpose: this runs at launch beside everything else
  /// that has to happen, and a backup that could not be written is not a
  /// reason to hold up the app. The Settings card shows when the last one
  /// actually happened, which is where a silent failure becomes visible.
  static Future<File?> runIfDue({
    required AppDatabase db,
    Directory? directory,
    DateTime? now,
    bool force = false,
  }) async {
    final at = now ?? DateTime.now();

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastRaw = prefs.getString(prefLastRun);
      final last = lastRaw == null ? null : DateTime.tryParse(lastRaw);

      if (!force && last != null && at.difference(last) < interval) {
        return null;
      }

      final dir = directory ?? await AppExportService.getExportDirectory();
      if (!await dir.exists()) await dir.create(recursive: true);

      final json = await db.exportBackupJson(
        extraPreferences: await PreferenceBackup.collect(),
      );

      final stamp =
          '${at.year}-${_two(at.month)}-${_two(at.day)}_'
          '${_two(at.hour)}${_two(at.minute)}';
      final file = File('${dir.path}/$filePrefix$stamp.json');
      await file.writeAsString(json);

      await prefs.setString(prefLastRun, at.toIso8601String());
      await _prune(dir);
      return file;
    } catch (e) {
      debugPrint('Auto backup skipped: $e');
      return null;
    }
  }

  /// When the last one was written, for Settings to show.
  static Future<DateTime?> lastRunAt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(prefLastRun);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Deletes the oldest of its own files beyond [keepCount].
  ///
  /// Sorted by name, which is the same as by time because the stamp in the
  /// name sorts that way — and unlike a file's modified date, a name cannot
  /// be rewritten by a copy or a sync.
  static Future<void> _prune(Directory dir) async {
    final mine =
        (await dir.list().toList()).whereType<File>().where((f) {
          final name = f.uri.pathSegments.last;
          return name.startsWith(filePrefix) && name.endsWith('.json');
        }).toList()..sort(
          (a, b) => a.uri.pathSegments.last.compareTo(b.uri.pathSegments.last),
        );

    if (mine.length <= keepCount) return;
    for (final old in mine.take(mine.length - keepCount)) {
      try {
        await old.delete();
      } catch (_) {
        // A file that will not delete is not worth failing a backup over.
      }
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
