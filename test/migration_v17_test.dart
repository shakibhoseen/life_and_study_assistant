import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/tables/syllabus_progress_table.dart';
import 'package:life_and_study_assistant/core/services/syllabus/syllabus_service.dart';

/// The 16 -> 17 upgrade: tracks became rows.
///
/// A phone that already has the syllabus map sits at 16 with nodes and ticks
/// in place and no tracks table at all, so the thing to prove is that the
/// upgrade adds the table without disturbing the syllabus underneath it —
/// and that the next seed fills the missing track rows back in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const track = SyllabusTrack(
    trackKey: 'primary',
    trackName: 'প্রাথমিক সহকারী শিক্ষক',
    totalMarks: 20,
    note: '',
    subjects: [
      SyllabusTrackSubject(
        name: 'গণিত',
        marks: 20,
        aliases: [],
        topics: [SyllabusTrackTopic(title: 'শতকরা', weight: 1)],
      ),
    ],
  );

  final topicKey = topicNodeKey('primary', 'গণিত', 'শতকরা');

  Future<File> buildV16Database() async {
    final file = File(
      '${Directory.systemTemp.createTempSync('mig17').path}/app.sqlite',
    );
    final db = AppDatabase(NativeDatabase(file));

    await SyllabusService.instance.seed(db, tracks: const [track]);
    await SyllabusService.instance.setStatus(
      db,
      nodeKey: topicKey,
      status: SyllabusStatus.done,
    );

    // Back to what a 16 install looks like.
    await db.customStatement('DROP TABLE IF EXISTS syllabus_tracks;');
    await db.customStatement('PRAGMA user_version = 16;');
    await db.close();
    return file;
  }

  test('adds the tracks table and keeps the syllabus and its ticks', () async {
    final file = await buildV16Database();
    final db = AppDatabase(NativeDatabase(file));

    expect(await SyllabusService.instance.tracks(db), isEmpty);

    // The nodes and the user's progress came through untouched.
    final subjects = await SyllabusService.instance.loadCoverage(
      db,
      'primary',
    );
    expect(subjects.single.topics.single.status, SyllabusStatus.done);

    await db.close();
  });

  test('the next seed fills the missing track row back in', () async {
    final file = await buildV16Database();
    final db = AppDatabase(NativeDatabase(file));

    await SyllabusService.instance.seed(db, tracks: const [track]);

    final row = await SyllabusService.instance.trackByKey(db, 'primary');
    expect(row, isNotNull);
    expect(row!.name, 'প্রাথমিক সহকারী শিক্ষক');
    expect(row.isCustom, isFalse);

    // And re-seeding over existing nodes did not disturb the tick.
    final subjects = await SyllabusService.instance.loadCoverage(
      db,
      'primary',
    );
    expect(subjects.single.topics.single.status, SyllabusStatus.done);

    await db.close();
  });

  test('a database created fresh at 17 has the table', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(await db.select(db.syllabusTracks).get(), isEmpty);
    await db.close();
  });
}
