import 'package:drift/drift.dart';

/// One line of a reference table.
///
/// Rows belong to a sheet by its stable key rather than its row id, so the
/// seed can replace a bundled sheet's rows wholesale — which is how content
/// updates arrive — without touching rows the user added to it. That is also
/// why [isCustom] is on the row and not just the sheet: a user can add a line
/// to a table that shipped with the app, and the next update must not eat it.
@TableIndex(name: 'idx_reference_rows_sheet', columns: {#sheetKey, #orderIndex})
class ReferenceRows extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get sheetKey => text().withLength(min: 1, max: 200)();

  /// JSON list of cell values, one per column of the owning sheet.
  TextColumn get cellsJson => text()();

  /// An aside for this line: a mnemonic, or the condition it holds under.
  TextColumn get note => text().withDefault(const Constant(''))();

  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();

  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  /// Where the rule comes from, at length.
  ///
  /// [note] is one line — a mnemonic, or the condition a formula holds
  /// under. This is the other thing: the derivation. হেরনের সূত্র is four
  /// symbols to memorise and a page to understand, and the page is what
  /// makes it stay. Markdown, rendered the same way the AI explanations
  /// already are.
  ///
  /// Null on almost every row, and meant to be: a conversion table needs no
  /// proof. It is for the handful of rules that are worth understanding
  /// rather than memorising.
  TextColumn get detail => text().nullable()();
}
