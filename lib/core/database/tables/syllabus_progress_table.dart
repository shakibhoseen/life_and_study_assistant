import 'package:drift/drift.dart';

/// How far through a topic the user is.
///
/// Three states rather than a tick, because "I am reading this" and "this is
/// done" are not the same claim and a half-read topic reported as covered is
/// the one lie this feature cannot afford to tell.
enum SyllabusStatus { notStarted, reading, done }

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
