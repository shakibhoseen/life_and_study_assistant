import 'package:drift/drift.dart';

/// A reference table: the kind of thing that is useless one line at a time.
///
/// "১ মাইল = ১.৬১ কিলোমিটার" on its own is a fact nobody retains. The same
/// line inside the length table, next to গজ and ফার্লং and হাত, is a thing
/// you can picture — which is why these live apart from flashcards rather
/// than as more of them.
///
/// A sheet carries its own column headers, so a two-column conversion table
/// and a five-column tense chart are the same shape to everything that reads
/// them.
@TableIndex(name: 'idx_reference_sheets_category', columns: {#category})
class ReferenceSheets extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Stable identity, so re-seeding the bundled content never orphans the
  /// rows a user added to a bundled sheet.
  TextColumn get sheetKey => text().withLength(min: 1, max: 200)();

  TextColumn get title => text().withLength(min: 1, max: 250)();

  /// The group it appears under: পরিমাপ ও একক, গাণিতিক সূত্র, and so on.
  TextColumn get category => text().withLength(min: 1, max: 150)();

  /// Which exam subject it belongs to, for matching against weak topics.
  TextColumn get subject => text().withDefault(const Constant(''))();

  /// Caveats or a reading tip, shown under the title.
  TextColumn get note => text().withDefault(const Constant(''))();

  /// JSON list of column headers.
  TextColumn get columnsJson => text()();

  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();

  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {sheetKey},
  ];
}
