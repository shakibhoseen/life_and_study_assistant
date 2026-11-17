import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/data/mistake_kind.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';

/// The 18 -> 19 upgrade: a reason on each mistake.
///
/// A phone already using the app sits at 18 with a mistake bank in it. The
/// column is added in place, so what has to hold is that every mistake
/// already there survives and reads as untagged — which is exactly what it
/// is, since nobody has been asked yet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const question = 'একটি দ্রব্য ২০% লাভে বিক্রি করলে ক্রয়মূল্য কত?';

  Future<File> buildV18Database() async {
    final file = File(
      '${Directory.systemTemp.createTempSync('mig19').path}/app.sqlite',
    );
    final db = AppDatabase(NativeDatabase(file));

    await db
        .into(db.drillQuestions)
        .insert(
          DrillQuestionsCompanion.insert(
            subject: 'গাণিতিক যুক্তি',
            topic: 'লাভ-ক্ষতি',
            questionText: question,
            optionsJson: '["ক","খ"]',
            correctIndex: 0,
            selectedIndex: 1,
            isCorrect: false,
            attemptedAt: Value(DateTime.now()),
          ),
        );

    // Back to what an 18 install looks like.
    await db.customStatement(
      'ALTER TABLE drill_questions DROP COLUMN mistake_kind;',
    );
    await db.customStatement('PRAGMA user_version = 18;');
    await db.close();
    return file;
  }

  test('adds the column and keeps every mistake already there', () async {
    final file = await buildV18Database();
    final db = AppDatabase(NativeDatabase(file));

    final rows = await db.select(db.drillQuestions).get();
    expect(rows.single.questionText, question);
    expect(rows.single.mistakeKind, isNull);

    final pattern = await db.getMistakePattern();
    expect(pattern.tagged, 0);
    // Untagged, which is the truth: nobody has been asked yet.
    expect(pattern.untagged, 1);

    await db.close();
  });

  test('a reason can be given straight after the upgrade', () async {
    final file = await buildV18Database();
    final db = AppDatabase(NativeDatabase(file));

    final id = (await db.select(db.drillQuestions).get()).single.id;
    await db.setMistakeKind(id, MistakeKind.calculation);

    expect((await db.getMistakePattern()).dominant, MistakeKind.calculation);

    await db.close();
  });

  test('a database created fresh at 19 has the column', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(await db.getMistakePattern(), isNotNull);
    await db.close();
  });
}
