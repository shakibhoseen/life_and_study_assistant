import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';

/// The 19 -> 20 upgrade: which paper a question came from.
///
/// Everything already in the bank was imported before this was kept, so it
/// has no source exam and never will. What has to hold is that those rows
/// survive untouched and simply do not appear in the frequency list — a
/// thin list means a thin import, not an easy syllabus.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<File> buildV19Database() async {
    final file = File(
      '${Directory.systemTemp.createTempSync('mig20').path}/app.sqlite',
    );
    final db = AppDatabase(NativeDatabase(file));

    await db
        .into(db.drillQuestions)
        .insert(
          DrillQuestionsCompanion.insert(
            subject: 'বাংলা',
            topic: 'কারক',
            questionText: 'পুরোনো প্রশ্ন',
            optionsJson: '["ক","খ"]',
            correctIndex: 0,
            selectedIndex: 1,
            isCorrect: false,
          ),
        );

    await db.customStatement(
      'ALTER TABLE drill_questions DROP COLUMN source_exam;',
    );
    await db.customStatement('PRAGMA user_version = 19;');
    await db.close();
    return file;
  }

  test('adds the column and keeps the questions already there', () async {
    final file = await buildV19Database();
    final db = AppDatabase(NativeDatabase(file));

    final rows = await db.select(db.drillQuestions).get();
    expect(rows.single.questionText, 'পুরোনো প্রশ্ন');
    expect(rows.single.sourceExam, isNull);

    // Not counted, rather than counted as an exam called "".
    expect(await db.getTopicFrequency(), isEmpty);

    await db.close();
  });

  test('a newly imported question carries its exam', () async {
    final file = await buildV19Database();
    final db = AppDatabase(NativeDatabase(file));

    await db
        .into(db.drillQuestions)
        .insert(
          DrillQuestionsCompanion.insert(
            subject: 'বাংলা',
            topic: 'কারক',
            questionText: 'নতুন প্রশ্ন',
            optionsJson: '["ক","খ"]',
            correctIndex: 0,
            selectedIndex: 0,
            isCorrect: true,
            sourceExam: const Value('৪৫তম বিসিএস'),
          ),
        );

    final ranked = await db.getTopicFrequency();
    expect(ranked.single.topic, 'কারক');
    expect(ranked.single.exams, ['৪৫তম বিসিএস']);

    await db.close();
  });
}
