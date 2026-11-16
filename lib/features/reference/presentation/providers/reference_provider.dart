import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/services/reference/reference_import_service.dart';
import '../../../../core/services/reference/reference_service.dart';

/// Bumped on every write so the providers below refetch.
class ReferenceRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final referenceRevisionProvider =
    NotifierProvider<ReferenceRevisionNotifier, int>(
      ReferenceRevisionNotifier.new,
    );

/// Every sheet, seeded on first read.
final referenceSheetsProvider = FutureProvider<List<ReferenceSheet>>((
  ref,
) async {
  final db = ref.watch(appDatabaseProvider);
  ref.watch(referenceRevisionProvider);
  await ReferenceService.instance.seed(db);
  return ReferenceService.instance.sheets(db);
});

/// Sheets grouped under their category, in the order they were seeded.
final referenceCategoriesProvider =
    FutureProvider<Map<String, List<ReferenceSheet>>>((ref) async {
      final sheets = await ref.watch(referenceSheetsProvider.future);
      final grouped = <String, List<ReferenceSheet>>{};
      for (final sheet in sheets) {
        grouped.putIfAbsent(sheet.category, () => []).add(sheet);
      }
      return grouped;
    });

final referenceSheetProvider =
    FutureProvider.family<ReferenceSheetView?, String>((ref, sheetKey) async {
      final db = ref.watch(appDatabaseProvider);
      ref.watch(referenceRevisionProvider);
      return ReferenceService.instance.view(db, sheetKey);
    });

final referenceSearchProvider =
    FutureProvider.family<List<ReferenceHit>, String>((ref, query) async {
      final db = ref.watch(appDatabaseProvider);
      ref.watch(referenceRevisionProvider);
      // Seeding first, or the first search of a fresh install finds nothing.
      await ref.watch(referenceSheetsProvider.future);
      return ReferenceService.instance.search(db, query);
    });

class ReferenceNotifier extends Notifier<void> {
  @override
  void build() {}

  AppDatabase get _db => ref.read(appDatabaseProvider);

  void _bump() => ref.read(referenceRevisionProvider.notifier).bump();

  Future<String?> createSheet({
    required String title,
    required List<String> columns,
    String category = 'আমার টেবিল',
    String subject = '',
    String note = '',
    List<ReferenceRowData> rows = const [],
  }) async {
    final key = await ReferenceService.instance.createSheet(
      _db,
      title: title,
      columns: columns,
      category: category,
      subject: subject,
      note: note,
      rows: rows,
    );
    if (key != null) _bump();
    return key;
  }

  Future<bool> renameSheet({
    required String sheetKey,
    required String title,
    String? note,
  }) async {
    final ok = await ReferenceService.instance.renameSheet(
      _db,
      sheetKey: sheetKey,
      title: title,
      note: note,
    );
    if (ok) _bump();
    return ok;
  }

  Future<bool> deleteSheet(String sheetKey) async {
    final ok = await ReferenceService.instance.deleteSheet(
      _db,
      sheetKey: sheetKey,
    );
    if (ok) _bump();
    return ok;
  }

  Future<bool> addRow({
    required String sheetKey,
    required List<String> cells,
    String note = '',
  }) async {
    final id = await ReferenceService.instance.addRow(
      _db,
      sheetKey: sheetKey,
      cells: cells,
      note: note,
    );
    if (id != null) _bump();
    return id != null;
  }

  Future<bool> editRow({
    required int rowId,
    List<String>? cells,
    String? note,
  }) async {
    final ok = await ReferenceService.instance.editRow(
      _db,
      rowId: rowId,
      cells: cells,
      note: note,
    );
    if (ok) _bump();
    return ok;
  }

  Future<void> deleteRow(int rowId) async {
    await ReferenceService.instance.deleteRow(_db, rowId: rowId);
    _bump();
  }

  /// Reads a table out of a photograph. Nothing is saved yet.
  Future<ReferenceSheetData> draftFromImage(File image) =>
      ReferenceImportService.instance.fromImage(image);

  /// Reads a table out of pasted text. Nothing is saved yet.
  Future<ReferenceSheetData> draftFromText(String text) =>
      ReferenceImportService.instance.fromText(text);

  /// Sends one line into the spaced-repetition deck.
  ///
  /// This is the bridge the reference tables exist beside rather than inside:
  /// most of a table is for looking up, but the two or three lines that keep
  /// slipping are worth being asked about at a bus stop.
  Future<void> sendRowToReview({
    required ReferenceSheet sheet,
    required ReferenceRow row,
  }) async {
    final cells = decodeStringList(row.cellsJson);
    if (cells.isEmpty) return;

    // The first cell is the thing being asked about, the rest is the answer:
    // "১ মাইল" / "১৭৬০ গজ = ১.৬১ কিলোমিটার".
    final title = cells.first.trim();
    final rest = cells.skip(1).where((c) => c.trim().isNotEmpty).join(' · ');
    final keyRule = [
      if (rest.isNotEmpty) rest,
      if (row.note.trim().isNotEmpty) row.note.trim(),
    ].join('\n');

    await _db.insertSpacedReviewItem(
      SpacedReviewItemsCompanion.insert(
        subject: sheet.subject.trim().isEmpty ? sheet.category : sheet.subject,
        topic: sheet.title,
        title: title.isEmpty ? sheet.title : title,
        keyRule: keyRule.isEmpty ? sheet.title : keyRule,
        nextReviewDate: DateTime.now().add(const Duration(days: 1)),
        intervalDays: const Value(1),
        repetitionLevel: const Value(1),
      ),
    );
  }
}

final referenceNotifierProvider = NotifierProvider<ReferenceNotifier, void>(
  ReferenceNotifier.new,
);
