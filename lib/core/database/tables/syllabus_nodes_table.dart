import 'package:drift/drift.dart';

/// Where a node sits in the map: a subject carries marks, a topic carries
/// weight within its subject.
enum SyllabusNodeKind { subject, topic }

/// The syllabus map: one row per subject and per topic, per track.
///
/// Rows are seeded from `assets/data/syllabus/*.json` and refreshed in place
/// whenever that content changes. The thing that makes that safe is
/// [nodeKey]: a stable string built from the track, the subject and the
/// topic's merge key rather than a row id. Re-seeding can therefore rewrite
/// titles, weights and ordering without disturbing what the user has ticked,
/// because progress is keyed by [nodeKey] too and never by the row.
///
/// A topic the user adds themselves is marked [isCustom] and is left alone by
/// a re-seed — the bundled syllabus is a starting point, not a cage.
@TableIndex(name: 'idx_syllabus_nodes_track', columns: {#trackKey, #orderIndex})
@TableIndex(name: 'idx_syllabus_nodes_merge', columns: {#mergeKey})
class SyllabusNodes extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Stable identity: `trackKey/subjectMergeKey` for a subject,
  /// `trackKey/subjectMergeKey/topicMergeKey` for a topic.
  TextColumn get nodeKey => text().withLength(min: 1, max: 400)();

  TextColumn get trackKey => text().withLength(min: 1, max: 100)();
  TextColumn get kind => textEnum<SyllabusNodeKind>()();

  /// Null for a subject; the owning subject's row id for a topic.
  IntColumn get parentId => integer().nullable()();

  TextColumn get title => text().withLength(min: 1, max: 300)();

  /// `topicMergeKey(title)` — the join key against the free-text subjects and
  /// topics that drills, weak topics and imported routines already carry.
  TextColumn get mergeKey => text()();

  /// Exam marks for a subject. Zero on a topic.
  IntColumn get marks => integer().withDefault(const Constant(0))();

  /// Relative weight of a topic inside its subject. Ignored on a subject.
  IntColumn get weight => integer().withDefault(const Constant(1))();

  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {nodeKey},
  ];
}
