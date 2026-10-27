import 'package:drift/drift.dart';

class ChatSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get subject => text().nullable()();
  TextColumn get topic => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Running summary of everything that fell out of the replayed history
  /// window, so a long thread keeps its continuity instead of silently
  /// forgetting whatever happened more than a handful of exchanges ago.
  TextColumn get summary => text().nullable()();

  /// Id of the last chat message already folded into [summary].
  IntColumn get summarizedUpToId => integer().nullable()();
}
