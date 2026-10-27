import 'package:drift/drift.dart';

enum ProficiencyLevel { weak, moderate, strong }

class WeakTopics extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get subject => text().withLength(min: 1, max: 100)();
  TextColumn get topicName => text().withLength(min: 1, max: 200)();
  TextColumn get proficiencyLevel => textEnum<ProficiencyLevel>()();
  DateTimeColumn get lastReviewedAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
