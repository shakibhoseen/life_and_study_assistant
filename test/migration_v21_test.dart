import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/services/reference/reference_service.dart';

/// The 20 -> 21 upgrade: room for a derivation on a reference row.
///
/// Null on every existing row by design — a conversion table needs no proof
/// — so what has to hold is that the tables already seeded come through with
/// their rows intact and simply nothing attached.
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

  Future<File> buildV20Database() async {
    final file = File(
      '${Directory.systemTemp.createTempSync('mig21').path}/app.sqlite',
    );
    final db = AppDatabase(NativeDatabase(file));
    await ReferenceService.instance.seed(db, sheets: const [sheet]);

    await db.customStatement(
      'ALTER TABLE reference_rows DROP COLUMN detail;',
    );
    await db.customStatement('PRAGMA user_version = 20;');
    await db.close();
    return file;
  }

  test('adds the column and keeps the tables already seeded', () async {
    final file = await buildV20Database();
    final db = AppDatabase(NativeDatabase(file));

    final view = await ReferenceService.instance.view(db, 'length');
    expect(view!.rows.single.detail, isNull);
    expect(view.columns, ['একক', 'সমান']);

    await db.close();
  });

  test('a derivation can be attached straight after the upgrade', () async {
    final file = await buildV20Database();
    final db = AppDatabase(NativeDatabase(file));

    final row = (await ReferenceService.instance.rows(db, 'length')).single;
    await ReferenceService.instance.setRowDetail(
      db,
      rowId: row.id,
      detail: '## কোথা থেকে\n\n১ গজ = ৩ ফুট ধরে।',
    );

    final after = (await ReferenceService.instance.rows(db, 'length')).single;
    expect(after.detail, contains('কোথা থেকে'));
    // Claimed, so the next content update does not replace the row and take
    // the explanation with it.
    expect(after.isCustom, isTrue);

    await db.close();
  });

  test('a blank derivation is stored as nothing, not as blank', () async {
    final file = await buildV20Database();
    final db = AppDatabase(NativeDatabase(file));

    final row = (await ReferenceService.instance.rows(db, 'length')).single;
    await ReferenceService.instance.setRowDetail(
      db,
      rowId: row.id,
      detail: '   \n  ',
    );

    expect(
      (await ReferenceService.instance.rows(db, 'length')).single.detail,
      isNull,
    );

    await db.close();
  });
}
