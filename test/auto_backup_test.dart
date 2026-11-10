import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/services/export/auto_backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The manual backup worked perfectly and had never been used, which is the
/// ordinary fate of a button that must be remembered. Then an install wiped
/// the app's data and there was nothing to go back to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory dir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('lsa_backup_test');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<String> namesIn(Directory d) =>
      d.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toList()
        ..sort();

  group('when it runs', () {
    test('the first launch writes one', () async {
      final file = await AutoBackupService.runIfDue(db: db, directory: dir);

      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
      expect(namesIn(dir).single, startsWith(AutoBackupService.filePrefix));
    });

    test('opening the app again an hour later writes nothing', () async {
      final at = DateTime(2026, 11, 10, 9);
      await AutoBackupService.runIfDue(db: db, directory: dir, now: at);

      final second = await AutoBackupService.runIfDue(
        db: db,
        directory: dir,
        now: at.add(const Duration(hours: 1)),
      );

      expect(second, isNull);
      expect(namesIn(dir), hasLength(1));
    });

    test('the next day writes another', () async {
      final at = DateTime(2026, 11, 10, 9);
      await AutoBackupService.runIfDue(db: db, directory: dir, now: at);

      final next = await AutoBackupService.runIfDue(
        db: db,
        directory: dir,
        now: at.add(const Duration(hours: 25)),
      );

      expect(next, isNotNull);
      expect(namesIn(dir), hasLength(2));
    });

    test('and the time it last ran is readable afterwards', () async {
      final at = DateTime(2026, 11, 10, 9, 30);
      await AutoBackupService.runIfDue(db: db, directory: dir, now: at);

      expect(await AutoBackupService.lastRunAt(), at);
    });
  });

  group('what it keeps', () {
    test('only the last few of its own', () async {
      var at = DateTime(2026, 1, 1, 8);
      for (var i = 0; i < AutoBackupService.keepCount + 3; i++) {
        await AutoBackupService.runIfDue(db: db, directory: dir, now: at);
        at = at.add(const Duration(days: 1));
      }

      expect(namesIn(dir), hasLength(AutoBackupService.keepCount));
      // The ones kept are the newest, not whichever the file system listed
      // first — the stamp in the name is what orders them.
      expect(namesIn(dir).last, contains('2026-01-10'));
    });

    test('a manual backup is never pruned', () async {
      final manual = File('${dir.path}/life_study_backup_2020-01-01.json');
      await manual.writeAsString('{}');

      var at = DateTime(2026, 1, 1, 8);
      for (var i = 0; i < AutoBackupService.keepCount + 3; i++) {
        await AutoBackupService.runIfDue(db: db, directory: dir, now: at);
        at = at.add(const Duration(days: 1));
      }

      expect(manual.existsSync(), isTrue);
    });
  });

  group('what is in the file', () {
    test('it is the same full backup the button writes', () async {
      SharedPreferences.setMockInitialValues({'pref_model': 'gemini-x'});

      final file = await AutoBackupService.runIfDue(db: db, directory: dir);
      final decoded =
          jsonDecode(await file!.readAsString()) as Map<String, dynamic>;

      expect(decoded['version'], 2);
      expect(decoded['drill_records'], isNotNull);
      expect(decoded['spaced_review_items'], isNotNull);
      expect((decoded['preferences'] as Map)['pref_model'], 'gemini-x');
    });

    test('and it restores', () async {
      final file = await AutoBackupService.runIfDue(db: db, directory: dir);

      final fresh = AppDatabase(NativeDatabase.memory());
      expect(
        await fresh.importBackupJson(await file!.readAsString()),
        isNotEmpty,
      );
      await fresh.close();
    });
  });

  test('a folder that cannot be written does not break the launch', () async {
    // It runs beside everything else that has to happen when the app opens,
    // so it has to fail quietly. A path that is actually a file is the
    // simplest thing the file system will refuse.
    final blocker = File('${dir.path}/blocker');
    await blocker.writeAsString('not a directory');

    expect(
      await AutoBackupService.runIfDue(
        db: db,
        directory: Directory(blocker.path),
      ),
      isNull,
    );
  });
}
