import 'package:drift/drift.dart';

class DrillRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get subject => text().withLength(min: 1, max: 100)();
  TextColumn get topic => text().withLength(min: 1, max: 200)();
  IntColumn get totalQuestions => integer()();
  IntColumn get correctCount => integer()();
  IntColumn get incorrectCount => integer()();
  RealColumn get scorePercentage => real()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
