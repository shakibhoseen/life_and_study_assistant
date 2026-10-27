import 'package:drift/drift.dart';

class ChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().nullable()();
  TextColumn get role => text()(); // 'user' or 'model'
  TextColumn get textContent => text()();
  TextColumn get suggestedAction =>
      text().nullable()(); // JSON string for structured action
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
}
