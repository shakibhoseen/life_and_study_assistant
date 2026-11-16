import 'package:drift/drift.dart';

/// Where the user has put a topic.
///
/// [reading] exists separately from [done] because "I am reading this" and
/// "this is finished" are not the same claim, and a half-read topic reported
/// as covered is the one lie this feature cannot afford to tell.
///
/// [hidden] is a topic the user says is not part of their syllabus. It is a
/// status rather than a deleted row because the bundled map is re-seeded on
/// every launch, and a deleted row would simply come back; this way the
/// removal is the user's and outlasts any content update. A hidden topic
/// leaves the coverage sums entirely — denominator included — so removing a
/// topic the user will never sit raises the percentage honestly instead of
/// leaving a hole that can never be filled.
///
/// Being an enum, adding to it makes the compiler find every reader, which is
/// the point: a status silently handled as "not started" somewhere would put
/// hidden topics back into the denominator.
enum SyllabusStatus { notStarted, reading, done, hidden }

/// Who decided the status.
///
/// A proposal derived from drill performance is never written straight in —
/// it is offered, and only becomes [SyllabusProgressSource.self] once the
/// user confirms it. Keeping the origin means a coverage figure can always be
/// traced back to something the user actually said or did.
enum SyllabusProgressSource { self, drill, exam, routine }

/// One row per syllabus node the user has touched.
///
/// Keyed by the node's stable `nodeKey`, not its row id, so re-seeding the
/// bundled syllabus — new topics, reworded titles, changed weights — never
/// costs the user a tick. A row simply has no entry until it is first moved
/// off [SyllabusStatus.notStarted].
@TableIndex(name: 'idx_syllabus_progress_status', columns: {#status})
class SyllabusProgress extends Table {
  TextColumn get nodeKey => text().withLength(min: 1, max: 400)();

  TextColumn get status => textEnum<SyllabusStatus>()();

  TextColumn get source => textEnum<SyllabusProgressSource>()();

  /// When the current status was set. Doubles as the history this feature
  /// needs: coverage on any past date is the nodes marked done on or before
  /// it, with no separate events table to keep in step.
  DateTimeColumn get markedAt => dateTime().withDefault(currentDateAndTime)();

  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {nodeKey};
}
