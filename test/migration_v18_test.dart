import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/tables/weak_topics_table.dart';
import 'package:life_and_study_assistant/core/services/reference/reference_service.dart';

/// The 17 -> 18 upgrade: reference tables arrived.
///
/// A phone already using the syllabus map sits at 17 with its tracks, nodes
/// and ticks in place. What this proves is that adding two tables beneath all
/// of that disturbs none of it, and that the next seed fills them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sheet = ReferenceSheetData(
    sheetKey: 'length',
    title: 'দৈর্ঘ্য',
    category: 'পরিমাপ ও একক',
    subject: '',
    note: '',
    columns: ['একক', 'সমান'],
    rows: [ReferenceRowData(cells: ['১ মাইল', '১.৬১ কিলোমিটার'])],
  );

  Future<File> buildV17Database() async {
    final file = File(
      '${Directory.systemTemp.createTempSync('mig18').path}/app.sqlite',
    );
    final db = AppDatabase(NativeDatabase(file));

    await db
        .into(db.weakTopics)
        .insert(
          WeakTopicsCompanion.insert(
            subject: 'গাণিতিক যুক্তি',
            topicName: 'শতকরা',
            proficiencyLevel: ProficiencyLevel.weak,
          ),
        );

    await db.customStatement('DROP TABLE IF EXISTS reference_rows;');
    await db.customStatement('DROP TABLE IF EXISTS reference_sheets;');
    await db.customStatement('PRAGMA user_version = 17;');
    await db.close();
    return file;
  }

  test('adds the tables empty and keeps what was already there', () async {
    final file = await buildV17Database();
    final db = AppDatabase(NativeDatabase(file));

    expect(await ReferenceService.instance.sheets(db), isEmpty);
    // The database seeds some weak topics of its own on create, so this
    // looks for the row the test put in rather than expecting only it.
    final topics = await db.select(db.weakTopics).get();
    expect(topics.map((t) => t.topicName), contains('শতকরা'));

    await db.close();
  });

  test('the next seed fills them', () async {
    final file = await buildV17Database();
    final db = AppDatabase(NativeDatabase(file));

    await ReferenceService.instance.seed(db, sheets: const [sheet]);

    final view = await ReferenceService.instance.view(db, 'length');
    expect(view!.rows.single, isNotNull);
    expect(view.columns, ['একক', 'সমান']);

    await db.close();
  });

  test('a database created fresh at 18 has the tables', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(await db.select(db.referenceSheets).get(), isEmpty);
    expect(await db.select(db.referenceRows).get(), isEmpty);
    await db.close();
  });
}
