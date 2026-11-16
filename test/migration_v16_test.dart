import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/tables/syllabus_progress_table.dart';
import 'package:life_and_study_assistant/core/services/syllabus/syllabus_service.dart';

/// The 15 -> 16 upgrade, run the way a phone will run it.
///
/// migration_v12_test walks user_version 8 up to current, but it builds the
/// file at the current schema first, so the syllabus tables are already there
/// and `createTable` is a no-op. On a device sitting at 15 they do not exist,
/// and that path has never run outside production.
///
/// Here the two tables are dropped and user_version is rewound to 15, so
/// reopening runs the genuine step — and the study data that was already in
/// the file has to come through it untouched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const question = 'চর্যাপদের আদি কবি কে?';

  Future<File> buildV15Database() async {
    final file = File(
      '${Directory.systemTemp.createTempSync('mig16').path}/app.sqlite',
    );
    final db = AppDatabase(NativeDatabase(file));

    await db
        .into(db.drillQuestions)
        .insert(
          DrillQuestionsCompanion.insert(
            subject: 'বাংলা সাহিত্য',
            topic: 'চর্যাপদ',
            questionText: question,
            optionsJson: '["সরহপা","শবরপা","ভুসুকুপা","লুইপা"]',
            correctIndex: 3,
            selectedIndex: 3,
            isCorrect: true,
          ),
        );

    // Take the file back to what a 15 install actually looks like.
    await db.customStatement('DROP TABLE IF EXISTS syllabus_progress;');
    await db.customStatement('DROP TABLE IF EXISTS syllabus_nodes;');
    await db.customStatement('PRAGMA user_version = 15;');
    await db.close();
    return file;
  }

  test('creates the syllabus tables and keeps the study data', () async {
    final file = await buildV15Database();
    final db = AppDatabase(NativeDatabase(file));

    // Forces the upgrade rather than trusting that opening did it.
    final nodes = await db.select(db.syllabusNodes).get();
    expect(nodes, isEmpty, reason: 'the migration seeds nothing itself');

    final progress = await db.select(db.syllabusProgress).get();
    expect(progress, isEmpty);

    final questions = await db.select(db.drillQuestions).get();
    expect(questions.single.questionText, question);

    await db.close();
  });

  test('seeding after the upgrade fills the map', () async {
    final file = await buildV15Database();
    final db = AppDatabase(NativeDatabase(file));

    await SyllabusService.instance.seed(
      db,
      tracks: const [
        SyllabusTrack(
          trackKey: 'test',
          trackName: 'পরীক্ষা',
          totalMarks: 10,
          note: '',
          subjects: [
            SyllabusTrackSubject(
              name: 'গণিত',
              marks: 10,
              aliases: [],
              topics: [SyllabusTrackTopic(title: 'শতকরা', weight: 1)],
            ),
          ],
        ),
      ],
    );

    expect((await db.select(db.syllabusNodes).get()).length, 2);

    await SyllabusService.instance.setStatus(
      db,
      nodeKey: topicNodeKey('test', 'গণিত', 'শতকরা'),
      status: SyllabusStatus.done,
    );
    expect((await db.select(db.syllabusProgress).get()).single.status,
        SyllabusStatus.done);

    await db.close();
  });

  test('a database created fresh at 16 has the tables too', () async {
    final db = AppDatabase(NativeDatabase.memory());

    // onCreate runs createAll rather than the upgrade steps, so the two paths
    // have to be checked apart.
    expect(await db.select(db.syllabusNodes).get(), isEmpty);
    expect(await db.select(db.syllabusProgress).get(), isEmpty);

    await db.close();
  });
}
