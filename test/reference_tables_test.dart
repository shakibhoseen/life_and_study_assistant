import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/services/reference/reference_import_service.dart';
import 'package:life_and_study_assistant/core/services/reference/reference_service.dart';

/// Reference tables, from the shipped JSON through to search.
///
/// The content is tested as strictly as the code because it is what will be
/// edited most and its mistakes are the quiet kind: a row with one cell too
/// few renders perfectly and simply says the wrong thing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bundled content', () {
    late List<ReferenceSheetData> all;

    setUpAll(() {
      all = [
        for (final path in bundledReferenceAssets)
          ...(jsonDecode(File(path).readAsStringSync()) as List)
              .whereType<Map>()
              .map((e) => ReferenceSheetData.fromJson(e.cast<String, dynamic>())),
      ];
    });

    test('every sheet has a key, a title, a category and columns', () {
      expect(all, isNotEmpty);
      for (final sheet in all) {
        expect(sheet.sheetKey.trim(), isNotEmpty);
        expect(sheet.title.trim(), isNotEmpty, reason: sheet.sheetKey);
        expect(sheet.category.trim(), isNotEmpty, reason: sheet.sheetKey);
        expect(
          sheet.columns.length,
          greaterThanOrEqualTo(2),
          reason: sheet.sheetKey,
        );
      }
    });

    test('sheet keys are unique across every file', () {
      final keys = all.map((s) => s.sheetKey).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('titles are unique, since creating one checks by title', () {
      final titles = all.map((s) => s.title).toList();
      expect(titles.toSet().length, titles.length);
    });

    test('every row has exactly as many cells as the sheet has columns', () {
      for (final sheet in all) {
        for (final row in sheet.rows) {
          expect(
            row.cells.length,
            sheet.columns.length,
            reason: '${sheet.sheetKey}: ${row.cells}',
          );
        }
      }
    });

    test('no sheet is empty and no cell is blank', () {
      for (final sheet in all) {
        expect(sheet.rows, isNotEmpty, reason: sheet.sheetKey);
        for (final row in sheet.rows) {
          expect(
            row.cells.any((c) => c.trim().isNotEmpty),
            isTrue,
            reason: sheet.sheetKey,
          );
        }
      }
    });

    test('the measurements the user asked for are there', () {
      final keys = all.map((s) => s.sheetKey).toSet();
      // These are the specific tables that prompted the feature.
      expect(keys, containsAll(['length_units', 'metric_prefixes']));

      final length = all.firstWhere((s) => s.sheetKey == 'length_units');
      final joined = length.rows.map((r) => r.cells.join(' ')).join(' | ');
      expect(joined, contains('মাইল'));
      expect(joined, contains('ফুট'));

      final prefixes = all.firstWhere((s) => s.sheetKey == 'metric_prefixes');
      expect(
        prefixes.rows.map((r) => r.cells.first).toList(),
        contains('ডেকা'),
      );
    });
  });

  group('seeding and reading', () {
    late AppDatabase db;

    const sheet = ReferenceSheetData(
      sheetKey: 'length',
      title: 'দৈর্ঘ্য',
      category: 'পরিমাপ ও একক',
      subject: 'গাণিতিক যুক্তি',
      note: 'পরীক্ষায় আসে',
      columns: ['একক', 'সমান'],
      rows: [
        ReferenceRowData(cells: ['১ মাইল', '১.৬১ কিলোমিটার']),
        ReferenceRowData(cells: ['১ গজ', '৩ ফুট'], note: '২ হাত = ১ গজ'),
      ],
    );

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await ReferenceService.instance.seed(db, sheets: const [sheet]);
    });
    tearDown(() => db.close());

    test('writes the sheet with its columns and rows', () async {
      final view = await ReferenceService.instance.view(db, 'length');

      expect(view, isNotNull);
      expect(view!.columns, ['একক', 'সমান']);
      expect(view.rows.length, 2);
      expect(view.sheet.note, 'পরীক্ষায় আসে');
    });

    test('seeding twice does not duplicate rows', () async {
      await ReferenceService.instance.seed(db, sheets: const [sheet]);

      final view = await ReferenceService.instance.view(db, 'length');
      expect(view!.rows.length, 2);
    });

    test('a content update replaces the bundled rows', () async {
      await ReferenceService.instance.seed(
        db,
        sheets: const [
          ReferenceSheetData(
            sheetKey: 'length',
            title: 'দৈর্ঘ্য',
            category: 'পরিমাপ ও একক',
            subject: '',
            note: '',
            columns: ['একক', 'সমান'],
            rows: [
              ReferenceRowData(cells: ['১ মাইল', '১.৬০৯ কিলোমিটার']),
            ],
          ),
        ],
      );

      final view = await ReferenceService.instance.view(db, 'length');
      expect(view!.rows.length, 1);
      expect(decodeStringList(view.rows.single.cellsJson)[1], '১.৬০৯ কিলোমিটার');
    });

    test('a row the user added to a bundled sheet survives the update',
        () async {
      await ReferenceService.instance.addRow(
        db,
        sheetKey: 'length',
        cells: ['১ হাত', '১৮ ইঞ্চি'],
      );

      await ReferenceService.instance.seed(db, sheets: const [sheet]);

      final view = await ReferenceService.instance.view(db, 'length');
      final joined = view!.rows
          .map((r) => decodeStringList(r.cellsJson).join(' '))
          .join(' | ');
      expect(joined, contains('১ হাত'));
      expect(view.rows.length, 3);
    });

    test('an edited bundled row is kept rather than overwritten', () async {
      final view = await ReferenceService.instance.view(db, 'length');
      final first = view!.rows.first;

      await ReferenceService.instance.editRow(
        db,
        rowId: first.id,
        cells: ['১ মাইল', '১৭৬০ গজ'],
      );
      await ReferenceService.instance.seed(db, sheets: const [sheet]);

      final after = await ReferenceService.instance.view(db, 'length');
      final joined = after!.rows
          .map((r) => decodeStringList(r.cellsJson).join(' '))
          .join(' | ');
      // The correction is the user's and outlives the content update.
      expect(joined, contains('১৭৬০ গজ'));
    });

    test('a bundled sheet cannot be deleted', () async {
      expect(
        await ReferenceService.instance.deleteSheet(db, sheetKey: 'length'),
        isFalse,
      );
    });
  });

  group('searching', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await ReferenceService.instance.seed(
        db,
        sheets: const [
          ReferenceSheetData(
            sheetKey: 'length',
            title: 'দৈর্ঘ্যের একক',
            category: 'পরিমাপ ও একক',
            subject: '',
            note: '',
            columns: ['একক', 'সমান'],
            rows: [
              ReferenceRowData(cells: ['১ মাইল', '১.৬১ কিলোমিটার']),
              ReferenceRowData(cells: ['১ গজ', '৩ ফুট']),
            ],
          ),
          ReferenceSheetData(
            sheetKey: 'area',
            title: 'জমির একক',
            category: 'পরিমাপ ও একক',
            subject: '',
            note: '',
            columns: ['একক', 'সমান'],
            rows: [
              ReferenceRowData(cells: ['১ বিঘা', '৩৩ শতক']),
            ],
          ),
        ],
      );
    });
    tearDown(() => db.close());

    test('finds a row by what is in it, not by the sheet name', () async {
      // Someone asking "১ মাইল কত" types মাইল, never দৈর্ঘ্যের একক.
      final hits = await ReferenceService.instance.search(db, 'মাইল');

      expect(hits.length, 1);
      expect(hits.single.sheet.title, 'দৈর্ঘ্যের একক');
    });

    test('searches across sheets', () async {
      final hits = await ReferenceService.instance.search(db, 'একক');
      // Matches every row through its sheet title.
      expect(hits.length, 3);
    });

    test('an empty query returns nothing rather than everything', () async {
      expect(await ReferenceService.instance.search(db, '   '), isEmpty);
    });

    test('a miss is empty', () async {
      expect(await ReferenceService.instance.search(db, 'নেই'), isEmpty);
    });
  });

  group('tables of your own', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('can be created with rows and deleted again', () async {
      final key = await ReferenceService.instance.createSheet(
        db,
        title: 'আমার সূত্র',
        columns: ['নাম', 'সূত্র'],
        rows: const [
          ReferenceRowData(cells: ['বৃত্তের ক্ষেত্রফল', 'πr²']),
        ],
      );

      expect(key, isNotNull);
      final view = await ReferenceService.instance.view(db, key!);
      expect(view!.rows.single.isCustom, isTrue);

      expect(
        await ReferenceService.instance.deleteSheet(db, sheetKey: key),
        isTrue,
      );
      expect(await ReferenceService.instance.view(db, key), isNull);
      expect(await db.select(db.referenceRows).get(), isEmpty);
    });

    test('a duplicate title is refused', () async {
      await ReferenceService.instance.createSheet(
        db,
        title: 'আমার সূত্র',
        columns: ['নাম', 'সূত্র'],
      );
      expect(
        await ReferenceService.instance.createSheet(
          db,
          title: 'আমার সূত্র',
          columns: ['ক', 'খ'],
        ),
        isNull,
      );
    });

    test('a sheet with no columns is refused', () async {
      expect(
        await ReferenceService.instance.createSheet(
          db,
          title: 'খালি',
          columns: const [],
        ),
        isNull,
      );
    });

    test('an all-blank row is refused', () async {
      final key = await ReferenceService.instance.createSheet(
        db,
        title: 'আমার সূত্র',
        columns: ['নাম', 'সূত্র'],
      );
      expect(
        await ReferenceService.instance.addRow(
          db,
          sheetKey: key!,
          cells: const ['  ', ''],
        ),
        isNull,
      );
    });
  });

  group('reading a table off a page', () {
    test('parses a well-formed reply', () {
      final sheet = ReferenceImportService.parseSheet('''
{
  "title": "ওজনের একক",
  "category": "পরিমাপ ও একক",
  "columns": ["একক", "সমান"],
  "rows": [
    {"cells": ["১ মণ", "৪০ সের"], "note": "প্রায় ৩৭.৫ কেজি"}
  ]
}
''');

      expect(sheet, isNotNull);
      expect(sheet!.title, 'ওজনের একক');
      expect(sheet.rows.single.note, 'প্রায় ৩৭.৫ কেজি');
    });

    test('survives markdown fences', () {
      final sheet = ReferenceImportService.parseSheet(
        '```json\n{"title":"X","columns":["a","b"],'
        '"rows":[{"cells":["1","2"]}]}\n```',
      );
      expect(sheet, isNotNull);
    });

    test('pads a short row rather than dropping the line', () {
      // A line read off a page with one cell missing is still most of a
      // line, and the user is about to review it anyway.
      final sheet = ReferenceImportService.parseSheet(
        '{"title":"X","columns":["a","b","c"],'
        '"rows":[{"cells":["১ মাইল"]}]}',
      );

      expect(sheet!.rows.single.cells, ['১ মাইল', '', '']);
    });

    test('trims a row with too many cells', () {
      final sheet = ReferenceImportService.parseSheet(
        '{"title":"X","columns":["a","b"],'
        '"rows":[{"cells":["১","২","৩"]}]}',
      );

      expect(sheet!.rows.single.cells, ['১', '২']);
    });

    test('falls back to a title rather than saving a nameless table', () {
      final sheet = ReferenceImportService.parseSheet(
        '{"columns":["a","b"],"rows":[{"cells":["১","২"]}]}',
      );
      expect(sheet!.title, isNotEmpty);
    });

    test('refuses a single-column reply', () {
      // One column is a list, not a table, and almost always a misread page.
      expect(
        ReferenceImportService.parseSheet(
          '{"title":"X","columns":["a"],"rows":[{"cells":["১"]}]}',
        ),
        isNull,
      );
    });

    test('the copied prompt asks for exactly what the parser reads', () {
      // The external path is only as good as this coupling: if the prompt
      // ever stops naming a key the parser needs, a user would paste a
      // perfectly good reply and get nothing, with nothing to point at.
      final prompt = ReferenceImportService.externalPrompt;
      for (final key in ['title', 'category', 'columns', 'rows', 'cells']) {
        expect(prompt, contains('"$key"'), reason: key);
      }

      // And the example inside the prompt must itself parse.
      final start = prompt.indexOf('{');
      final example = prompt.substring(start, prompt.lastIndexOf('}') + 1);
      expect(ReferenceImportService.parseSheet(example), isNotNull);
    });

    test('returns null on rubbish and on an empty table', () {
      expect(ReferenceImportService.parseSheet('দুঃখিত'), isNull);
      expect(
        ReferenceImportService.parseSheet(
          '{"title":"X","columns":["a","b"],"rows":[]}',
        ),
        isNull,
      );
    });
  });
}
