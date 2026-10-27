import 'package:drift/drift.dart';

class ExamSchedules extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get examDate => dateTime()(); // parsed date of exam
  TextColumn get examTime => text().withDefault(const Constant('10:00 PM'))();
  TextColumn get subject => text().withDefault(const Constant('General'))();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get topicsCovered =>
      text()(); // JSON string or comma-separated list of topics
  TextColumn get examType => text().withDefault(
    const Constant('Daily'),
  )(); // Daily, Weekly, Model Test, Special
  TextColumn get trackName =>
      text().withDefault(const Constant('General BCS'))(); // e.g. 52nd BCS 135-Day, Vocabulary Booster, Friday Mega Model Test, Primary
  TextColumn get resourceSummary => text().nullable()();
  TextColumn get rawReference =>
      text().nullable()(); // original text/notes/source
  BoolColumn get completedStatus =>
      boolean().withDefault(const Constant(false))();
  RealColumn get score => real().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
