import 'package:drift/drift.dart';

class DrillQuestions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get drillRecordId => integer().nullable()();
  TextColumn get subject => text().withLength(min: 1, max: 100)();
  TextColumn get topic => text().withLength(min: 1, max: 200)();
  TextColumn get questionText => text()();
  TextColumn get optionsJson =>
      text()(); // JSON List of strings e.g. ["A","B","C","D"]
  IntColumn get correctIndex => integer()();
  IntColumn get selectedIndex => integer()();
  BoolColumn get isCorrect => boolean()();
  TextColumn get explanation => text().withDefault(const Constant(''))();
  BoolColumn get isMastered => boolean().withDefault(const Constant(false))();
  DateTimeColumn get attemptedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// What [correctIndex] and [explanation] held before a verification
  /// correction was accepted. Null until one is.
  ///
  /// [selectedIndex] and [isCorrect] are never rewritten: they record what
  /// the user answered and how it was scored at the time, and a later
  /// correction to the question does not change what happened in that
  /// attempt.
  IntColumn get originalCorrectIndex => integer().nullable()();
  TextColumn get originalExplanation => text().nullable()();
  TextColumn get originalQuestionText => text().nullable()();
  TextColumn get originalOptionsJson => text().nullable()();
  DateTimeColumn get correctedAt => dateTime().nullable()();

  /// The last verification's outcome, kept so reopening the sheet shows what
  /// was already found instead of paying for the same check again.
  TextColumn get verificationStatus => text().nullable()();
  TextColumn get verificationNote => text().nullable()();
  DateTimeColumn get verifiedAt => dateTime().nullable()();
}
