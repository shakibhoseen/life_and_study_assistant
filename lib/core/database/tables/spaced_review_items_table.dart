import 'package:drift/drift.dart';

class SpacedReviewItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get subject => text().withLength(min: 1, max: 100)();
  TextColumn get topic => text().withLength(min: 1, max: 200)();
  TextColumn get title => text().withLength(min: 1, max: 250)();
  TextColumn get keyRule =>
      text()(); // The difficult rule, mnemonic, formula, or flashcard content
  IntColumn get repetitionLevel => integer().withDefault(
    const Constant(1),
  )(); // 1 = 1d, 2 = 3d, 3 = 7d, 4 = 14d, 5 = 30d, 6 = Mastered
  IntColumn get intervalDays => integer().withDefault(const Constant(1))();
  DateTimeColumn get nextReviewDate => dateTime()();
  DateTimeColumn get lastReviewedAt => dateTime().nullable()();
  BoolColumn get isMastered => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
