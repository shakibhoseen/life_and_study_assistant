import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../database/app_database.dart';

/// The reference tables that ship with the app.
const List<String> bundledReferenceAssets = [
  'assets/data/reference/measurements.json',
  'assets/data/reference/math_formulas.json',
  'assets/data/reference/science_units.json',
  'assets/data/reference/language_rules.json',
];

/// A sheet as the bundled JSON describes it.
@immutable
class ReferenceSheetData {
  final String sheetKey;
  final String title;
  final String category;
  final String subject;
  final String note;
  final List<String> columns;
  final List<ReferenceRowData> rows;

  const ReferenceSheetData({
    required this.sheetKey,
    required this.title,
    required this.category,
    required this.subject,
    required this.note,
    required this.columns,
    required this.rows,
  });

  factory ReferenceSheetData.fromJson(Map<String, dynamic> json) {
    return ReferenceSheetData(
      sheetKey: json['sheetKey']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      subject: json['subject']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      columns: ((json['columns'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      rows: ((json['rows'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => ReferenceRowData.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

@immutable
class ReferenceRowData {
  final List<String> cells;
  final String note;

  const ReferenceRowData({required this.cells, this.note = ''});

  factory ReferenceRowData.fromJson(Map<String, dynamic> json) =>
      ReferenceRowData(
        cells: ((json['cells'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        note: json['note']?.toString() ?? '',
      );
}

/// A sheet and its rows, as the screen wants them.
@immutable
class ReferenceSheetView {
  final ReferenceSheet sheet;
  final List<ReferenceRow> rows;

  const ReferenceSheetView({required this.sheet, required this.rows});

  List<String> get columns => decodeStringList(sheet.columnsJson);
}

/// A row matched by a search, with the sheet it came from.
@immutable
class ReferenceHit {
  final ReferenceSheet sheet;
  final ReferenceRow row;

  const ReferenceHit({required this.sheet, required this.row});
}

/// The instruction to hand a stronger model elsewhere, for one row.
///
/// A derivation is exactly the kind of thing the cheap model this app can
/// afford gets confidently wrong, and a wrong proof is worse than none: it
/// teaches a method that will fail in the exam. So the app does not generate
/// these. It writes the prompt, the user takes it to whatever they already
/// use, and the answer is pasted back unaltered.
///
/// Every section is conditional, and says so. An earlier version demanded a
/// proof, a condition, a trap and a mnemonic for every row — which for most
/// rows means asking a model to invent three of them. A heading with nothing
/// real under it is worse than a missing heading: it reads as fact.
String derivationPrompt({
  required String sheetTitle,
  required List<String> columns,
  required List<String> cells,
  String note = '',
}) {
  final pairs = <String>[];
  for (var i = 0; i < cells.length; i++) {
    final label = i < columns.length ? columns[i] : '';
    final value = cells[i].trim();
    if (value.isEmpty) continue;
    pairs.add(label.isEmpty ? value : '$label: $value');
  }

  return '''
আপনি একজন বিসিএস/নিয়োগ পরীক্ষার্থীকে একটি সূত্র বা নিয়ম বোঝাচ্ছেন।

টেবিল: $sheetTitle
সারি: ${pairs.join(' | ')}${note.trim().isEmpty ? '' : '\nনোট: ${note.trim()}'}

এটি কোথা থেকে এলো, সেটি বুঝিয়ে লিখুন।

যেগুলো **সত্যিই আছে কেবল সেগুলোই** লিখবেন:
- কোন ধারণা বা উপপাদ্য থেকে এটি আসে
- সংক্ষিপ্ত উৎপত্তি বা প্রমাণ
- কোন শর্তে এটি খাটে, আর কোথায় খাটে না
- পরীক্ষায় পাতা কোনো নির্দিষ্ট ফাঁদ
- মনে রাখার কোনো কৌশল

গুরুত্বপূর্ণ: উপরের সব কটি প্রতিটি নিয়মের ক্ষেত্রে থাকে না। যেটি নেই,
সেটি বানিয়ে লিখবেন না — শিরোনামটিই বাদ দিন। অনেক রূপান্তরের কোনো ফাঁদ
থাকে না, অনেক সূত্রের কোনো কৌশলের দরকার হয় না। খালি শিরোনামের চেয়ে
অনুপস্থিত শিরোনাম ভালো।

ছবি: জ্যামিতি, ঘনবস্তু বা যেকোনো আকৃতির ক্ষেত্রে — যেখানে **না দেখলে বোঝা
যায় না** — একটি সরল SVG ছবি দিন, এভাবে:

```svg চিত্র: সমকোণী ত্রিভুজ
<svg viewBox="0 0 120 90" xmlns="http://www.w3.org/2000/svg">
  <polygon points="10,80 110,80 10,10" fill="none" stroke="black"
           stroke-width="2"/>
  <text x="55" y="88" font-size="9">ভূমি</text>
</svg>
```

ছবির নিয়ম:
- viewBox দেবেন, width/height নয়।
- কালো রেখা ও সাদা পটভূমি ধরে আঁকুন।
- বাইরের কোনো লিংক, ছবি বা ফন্ট ব্যবহার করবেন না।
- বাংলা লেখা <text>-এ দিতে পারেন, ছোট রাখুন।
- আকৃতি না থাকলে ছবি দেবেন না।

লেখার নিয়ম:
- বাংলায় লিখুন (ইংরেজি পরিভাষা থাকলে থাকুক)।
- Markdown ব্যবহার করুন — শিরোনাম, তালিকা, **গুরুত্বপূর্ণ** অংশ।
- গণিত ইউনিকোডে লিখুন: π, √, ², ×, ÷, ≤, ° — LaTeX সিনট্যাক্স নয়।
- নিশ্চিত না হলে অনুমান না করে লিখুন "এ অংশটি যাচাই করে নিন"।
- শুধু ব্যাখ্যাটুকু দিন, ভূমিকা বা উপসংহার নয়।
''';
}

/// Decodes a stored JSON list, tolerating anything that is not one.
///
/// Rows come from an asset, from the user and from a model reading a
/// photograph; a single malformed one must not take a whole table down.
List<String> decodeStringList(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) return decoded.map((e) => e.toString()).toList();
  } catch (_) {
    // Falls through to the empty list below.
  }
  return const [];
}

class ReferenceService {
  ReferenceService._();
  static final ReferenceService instance = ReferenceService._();

  Future<List<ReferenceSheetData>> loadBundled() async {
    final sheets = <ReferenceSheetData>[];
    for (final path in bundledReferenceAssets) {
      try {
        final raw = await rootBundle.loadString(path);
        final decoded = jsonDecode(raw);
        if (decoded is! List) continue;
        for (final entry in decoded.whereType<Map>()) {
          sheets.add(
            ReferenceSheetData.fromJson(entry.cast<String, dynamic>()),
          );
        }
      } catch (e) {
        debugPrint('Reference: could not load $path: $e');
      }
    }
    return sheets;
  }

  /// Writes the bundled tables into the database.
  ///
  /// Bundled rows are replaced wholesale per sheet, which is how a content
  /// update arrives. Rows the user added to a bundled sheet are marked custom
  /// and are left where they are — and a sheet the user made is not touched
  /// at all.
  Future<void> seed(
    AppDatabase db, {
    List<ReferenceSheetData>? sheets,
  }) async {
    final loaded = sheets ?? await loadBundled();
    if (loaded.isEmpty) return;

    for (var i = 0; i < loaded.length; i++) {
      final sheet = loaded[i];
      if (sheet.sheetKey.isEmpty || sheet.columns.isEmpty) continue;

      final existing = await sheetByKey(db, sheet.sheetKey);
      if (existing != null && existing.isCustom) continue;

      await db
          .into(db.referenceSheets)
          .insert(
            ReferenceSheetsCompanion.insert(
              sheetKey: sheet.sheetKey,
              title: sheet.title,
              category: sheet.category,
              subject: Value(sheet.subject),
              note: Value(sheet.note),
              columnsJson: jsonEncode(sheet.columns),
              orderIndex: Value(i),
            ),
            onConflict: DoUpdate(
              (_) => ReferenceSheetsCompanion(
                title: Value(sheet.title),
                category: Value(sheet.category),
                subject: Value(sheet.subject),
                note: Value(sheet.note),
                columnsJson: Value(jsonEncode(sheet.columns)),
                orderIndex: Value(i),
              ),
              target: [db.referenceSheets.sheetKey],
            ),
          );

      // Reconcile rows for this sheet: preserve existing user details and custom edits,
      // and prevent re-inserting duplicate copies of bundled rows.
      final existingRows = await (db.select(db.referenceRows)
            ..where((t) => t.sheetKey.equals(sheet.sheetKey)))
          .get();

      // Deduplicate any rows that already share the same cellsJson
      final existingByCells = <String, ReferenceRow>{};
      for (final r in existingRows) {
        final existing = existingByCells[r.cellsJson];
        if (existing != null) {
          // A duplicate exists: prefer the one that has an attached detail
          final existingHasDetail = (existing.detail ?? '').trim().isNotEmpty;
          final rHasDetail = (r.detail ?? '').trim().isNotEmpty;
          if (!existingHasDetail && rHasDetail) {
            await (db.delete(db.referenceRows)
                  ..where((t) => t.id.equals(existing.id)))
                .go();
            existingByCells[r.cellsJson] = r;
          } else {
            await (db.delete(db.referenceRows)
                  ..where((t) => t.id.equals(r.id)))
                .go();
          }
        } else {
          existingByCells[r.cellsJson] = r;
        }
      }

      for (var r = 0; r < sheet.rows.length; r++) {
        final row = sheet.rows[r];
        if (row.cells.isEmpty) continue;
        final cellsJson = jsonEncode(row.cells);

        final existing = existingByCells.remove(cellsJson);
        if (existing != null) {
          // The row already exists: update its orderIndex and note if needed,
          // but NEVER insert a duplicate and NEVER wipe its detail!
          await (db.update(db.referenceRows)
                ..where((t) => t.id.equals(existing.id)))
              .write(
                ReferenceRowsCompanion(
                  orderIndex: Value(r),
                  note: Value(row.note.isNotEmpty ? row.note : existing.note),
                ),
              );
        } else {
          await db
              .into(db.referenceRows)
              .insert(
                ReferenceRowsCompanion.insert(
                  sheetKey: sheet.sheetKey,
                  cellsJson: cellsJson,
                  note: Value(row.note),
                  orderIndex: Value(r),
                ),
              );
        }
      }

      // Any remaining rows in existingByCells:
      // Keep rows that are custom or have user explanations; prune obsolete uncustomized rows.
      for (final leftover in existingByCells.values) {
        final hasDetail = (leftover.detail ?? '').trim().isNotEmpty;
        if (!leftover.isCustom && !hasDetail) {
          await (db.delete(db.referenceRows)
                ..where((t) => t.id.equals(leftover.id)))
              .go();
        }
      }
    }
  }

  Future<ReferenceSheet?> sheetByKey(AppDatabase db, String sheetKey) =>
      (db.select(db.referenceSheets)
            ..where((t) => t.sheetKey.equals(sheetKey))
            ..limit(1))
          .getSingleOrNull();

  /// Every sheet, bundled in seed order then the user's by age.
  Future<List<ReferenceSheet>> sheets(AppDatabase db) =>
      (db.select(db.referenceSheets)..orderBy([
            (t) => OrderingTerm(expression: t.isCustom),
            (t) => OrderingTerm(expression: t.orderIndex),
            (t) => OrderingTerm(expression: t.createdAt),
          ]))
          .get();

  Future<ReferenceSheetView?> view(AppDatabase db, String sheetKey) async {
    final sheet = await sheetByKey(db, sheetKey);
    if (sheet == null) return null;
    return ReferenceSheetView(sheet: sheet, rows: await rows(db, sheetKey));
  }

  Future<List<ReferenceRow>> rows(AppDatabase db, String sheetKey) =>
      (db.select(db.referenceRows)
            ..where((t) => t.sheetKey.equals(sheetKey))
            ..orderBy([
              (t) => OrderingTerm(expression: t.orderIndex),
              (t) => OrderingTerm(expression: t.id),
            ]))
          .get();

  /// Rows matching [query], across every sheet.
  ///
  /// Searching rows rather than titles is the point: someone who wants to
  /// know what a মাইল is types "মাইল", not "দৈর্ঘ্যের একক".
  Future<List<ReferenceHit>> search(AppDatabase db, String query) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];

    final sheetsByKey = {
      for (final sheet in await sheets(db)) sheet.sheetKey: sheet,
    };
    final allRows = await db.select(db.referenceRows).get();

    final hits = <ReferenceHit>[];
    for (final row in allRows) {
      final sheet = sheetsByKey[row.sheetKey];
      if (sheet == null) continue;
      final haystack = [
        ...decodeStringList(row.cellsJson),
        row.note,
        sheet.title,
      ].join(' ').toLowerCase();
      if (haystack.contains(needle)) {
        hits.add(ReferenceHit(sheet: sheet, row: row));
      }
    }
    return hits;
  }

  /// Creates a table of the user's own, or one read from a book.
  ///
  /// Returns the new sheet's key, or null if the title is empty, it has no
  /// columns, or that title is already taken.
  Future<String?> createSheet(
    AppDatabase db, {
    required String title,
    required List<String> columns,
    String category = 'আমার টেবিল',
    String subject = '',
    String note = '',
    List<ReferenceRowData> rows = const [],
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty || columns.isEmpty) return null;

    final existing = await sheets(db);
    if (existing.any((s) => s.title.trim() == trimmed)) return null;

    final key = 'custom_${DateTime.now().microsecondsSinceEpoch}';
    await db
        .into(db.referenceSheets)
        .insert(
          ReferenceSheetsCompanion.insert(
            sheetKey: key,
            title: trimmed,
            category: category.trim().isEmpty ? 'আমার টেবিল' : category.trim(),
            subject: Value(subject),
            note: Value(note),
            columnsJson: jsonEncode(columns),
            isCustom: const Value(true),
            orderIndex: Value(existing.length),
          ),
        );

    for (var i = 0; i < rows.length; i++) {
      if (rows[i].cells.isEmpty) continue;
      await db
          .into(db.referenceRows)
          .insert(
            ReferenceRowsCompanion.insert(
              sheetKey: key,
              cellsJson: jsonEncode(rows[i].cells),
              note: Value(rows[i].note),
              isCustom: const Value(true),
              orderIndex: Value(i),
            ),
          );
    }
    return key;
  }

  Future<bool> renameSheet(
    AppDatabase db, {
    required String sheetKey,
    required String title,
    String? note,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return false;
    final sheet = await sheetByKey(db, sheetKey);
    if (sheet == null) return false;

    await (db.update(db.referenceSheets)..where((t) => t.id.equals(sheet.id)))
        .write(
          ReferenceSheetsCompanion(
            title: Value(trimmed),
            note: note == null ? const Value.absent() : Value(note),
            isCustom: const Value(true),
          ),
        );
    return true;
  }

  /// Deletes a sheet the user made, with its rows.
  ///
  /// A bundled sheet is refused: the seed would rebuild it on the next
  /// launch and leave nothing but a flicker.
  Future<bool> deleteSheet(AppDatabase db, {required String sheetKey}) async {
    final sheet = await sheetByKey(db, sheetKey);
    if (sheet == null || !sheet.isCustom) return false;

    await (db.delete(
      db.referenceRows,
    )..where((t) => t.sheetKey.equals(sheetKey))).go();
    await (db.delete(
      db.referenceSheets,
    )..where((t) => t.id.equals(sheet.id))).go();
    return true;
  }

  Future<int?> addRow(
    AppDatabase db, {
    required String sheetKey,
    required List<String> cells,
    String note = '',
  }) async {
    if (cells.every((c) => c.trim().isEmpty)) return null;
    final sheet = await sheetByKey(db, sheetKey);
    if (sheet == null) return null;

    final existing = await rows(db, sheetKey);
    return db
        .into(db.referenceRows)
        .insert(
          ReferenceRowsCompanion.insert(
            sheetKey: sheetKey,
            cellsJson: jsonEncode(cells),
            note: Value(note),
            isCustom: const Value(true),
            orderIndex: Value(
              existing.isEmpty ? 0 : existing.last.orderIndex + 1,
            ),
          ),
        );
  }

  /// Edits a row, bundled or not.
  ///
  /// An edited bundled row becomes custom, or the next content update would
  /// replace it and the correction would vanish.
  Future<bool> editRow(
    AppDatabase db, {
    required int rowId,
    List<String>? cells,
    String? note,
  }) async {
    if (cells != null && cells.every((c) => c.trim().isEmpty)) return false;

    final count =
        await (db.update(db.referenceRows)..where((t) => t.id.equals(rowId)))
            .write(
              ReferenceRowsCompanion(
                cellsJson: cells == null
                    ? const Value.absent()
                    : Value(jsonEncode(cells)),
                note: note == null ? const Value.absent() : Value(note),
                isCustom: const Value(true),
              ),
            );
    return count > 0;
  }

  /// Attaches a derivation to a row, or clears it with null.
  ///
  /// Editing a bundled row's detail makes the row custom, as editing its
  /// cells does, or the next content update would replace the row and take
  /// the explanation with it.
  Future<bool> setRowDetail(
    AppDatabase db, {
    required int rowId,
    required String? detail,
  }) async {
    final trimmed = detail?.trim();
    final count =
        await (db.update(db.referenceRows)..where((t) => t.id.equals(rowId)))
            .write(
              ReferenceRowsCompanion(
                detail: Value(
                  trimmed == null || trimmed.isEmpty ? null : trimmed,
                ),
                isCustom: const Value(true),
              ),
            );
    return count > 0;
  }

  Future<void> deleteRow(AppDatabase db, {required int rowId}) =>
      (db.delete(db.referenceRows)..where((t) => t.id.equals(rowId))).go();
}
