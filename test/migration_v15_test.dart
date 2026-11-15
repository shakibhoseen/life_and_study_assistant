import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';

/// The 14 -> 15 upgrade, run the way a real phone will run it.
///
/// `mergeDuplicateDrillQuestions()` has its own tests, and migration_v12_test
/// walks user_version 8 up to current — but that test builds the file at the
/// current schema first, so `attempt_count` and `wrong_count` are already
/// there and the `m.addColumn` calls are skipped. On an actual device sitting
/// at 14 those columns do not exist, and that ALTER TABLE has never run
/// outside production.
///
/// Here the columns are dropped and user_version is rewound to 14, so
/// reopening runs the genuine path: add the two columns, then merge the
/// duplicate rows the append-only Mistake Bank left behind.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const question = 'বাংলাদেশের সংবিধান কত সালে প্রণীত হয়?';
  const other = 'গণপরিষদের প্রথম অধিবেশন কবে বসে?';

  Future<File> buildV14Database() async {
    final file = File(
      '${Directory.systemTemp.createTempSync('mig15').path}/app.sqlite',
    );
    final db = AppDatabase(NativeDatabase(file));

    Future<void> insert(String text, {required bool correct}) {
      return db
          .into(db.drillQuestions)
          .insert(
            DrillQuestionsCompanion.insert(
              subject: 'বাংলাদেশ বিষয়াবলি',
              topic: 'সংবিধান',
              questionText: text,
              optionsJson: jsonEncode(['১৯৭১', '১৯৭২', '১৯৭৩', '১৯৭৪']),
              correctIndex: 1,
              selectedIndex: correct ? 1 : 3,
              isCorrect: correct,
            ),
          );
    }

    // What a v14 Mistake Bank looks like: the same question answered three
    // times is three rows, and the user never got it right.
    await insert(question, correct: false);
    await insert(question, correct: false);
    await insert(question, correct: false);
    await insert(other, correct: true);

    // Now make it a real v14 file: these two columns did not exist yet.
    await db.customStatement(
      'ALTER TABLE drill_questions DROP COLUMN attempt_count',
    );
    await db.customStatement(
      'ALTER TABLE drill_questions DROP COLUMN wrong_count',
    );
    await db.customStatement('PRAGMA user_version = 14');
    await db.close();
    return file;
  }

  test('a v14 database gains the counters and loses its duplicates', () async {
    final file = await buildV14Database();

    final db = AppDatabase(NativeDatabase(file));
    final rows = await db.select(db.drillQuestions).get();

    // addColumn ran: reading these does not throw, and they are populated.
    final merged = rows.firstWhere((r) => r.questionText == question);
    expect(
      rows.length,
      2,
      reason: 'three copies of one question collapse to one row',
    );
    expect(merged.attemptCount, 3);
    expect(merged.wrongCount, 3);
    expect(merged.isCorrect, isFalse);

    // The question answered once is untouched by the merge.
    final untouched = rows.firstWhere((r) => r.questionText == other);
    expect(untouched.attemptCount, 1);
    expect(untouched.wrongCount, 0);

    await db.close();
  });

  test('the upgraded bank still reports one unlearnt question', () async {
    final file = await buildV14Database();

    final db = AppDatabase(NativeDatabase(file));
    final bank = await db.watchWrongDrillQuestions().first;
    expect(bank.length, 1, reason: 'the count must not be inflated by copies');

    final stats = await db.getDrillStats();
    expect(stats['active_wrong_count'], 1);
    // Accuracy still counts answers given, not questions seen: 4 attempts,
    // 3 of them wrong.
    expect(stats['total_answered'], 4);
    expect(stats['total_wrong'], 3);

    await db.close();
  });

  test('upgrading twice is a no-op, not a second merge', () async {
    final file = await buildV14Database();

    var db = AppDatabase(NativeDatabase(file));
    await db.select(db.drillQuestions).get();
    await db.close();

    // Reopening an already-migrated file must not re-run anything.
    db = AppDatabase(NativeDatabase(file));
    final rows = await db.select(db.drillQuestions).get();
    expect(rows.length, 2);
    expect(rows.firstWhere((r) => r.questionText == question).attemptCount, 3);
    await db.close();
  });
}
