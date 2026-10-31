import 'package:drift/drift.dart';

@TableIndex(
  name: 'idx_chat_messages_session_time',
  columns: {#sessionId, #timestamp},
)
class ChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().nullable()();
  TextColumn get role => text()(); // 'user' or 'model'
  TextColumn get textContent => text()();
  TextColumn get suggestedAction =>
      text().nullable()(); // JSON string for structured action
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
}
