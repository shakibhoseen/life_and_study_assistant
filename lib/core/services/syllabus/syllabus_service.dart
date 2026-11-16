import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../data/study_data_cleanup.dart';
import '../../data/syllabus_coverage.dart';
import '../../database/app_database.dart';
import '../../database/tables/syllabus_nodes_table.dart';
import '../../database/tables/syllabus_progress_table.dart';

/// The syllabus maps that ship with the app.
const List<String> bundledSyllabusAssets = [
  'assets/data/syllabus/primary.json',
  'assets/data/syllabus/bcs_preliminary.json',
];

/// A track as the bundled JSON describes it, before it reaches the database.
@immutable
class SyllabusTrack {
  final String trackKey;
  final String trackName;
  final int totalMarks;
  final String note;
  final List<SyllabusTrackSubject> subjects;

  const SyllabusTrack({
    required this.trackKey,
    required this.trackName,
    required this.totalMarks,
    required this.note,
    required this.subjects,
  });

  factory SyllabusTrack.fromJson(Map<String, dynamic> json) {
    final rawSubjects = (json['subjects'] as List?) ?? const [];
    return SyllabusTrack(
      trackKey: json['trackKey']?.toString() ?? '',
      trackName: json['trackName']?.toString() ?? '',
      totalMarks: (json['totalMarks'] as num?)?.toInt() ?? 0,
      note: json['note']?.toString() ?? '',
      subjects: rawSubjects
          .whereType<Map>()
          .map((e) => SyllabusTrackSubject.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

@immutable
class SyllabusTrackSubject {
  final String name;
  final int marks;
  final List<String> aliases;
  final List<SyllabusTrackTopic> topics;

  const SyllabusTrackSubject({
    required this.name,
    required this.marks,
    required this.aliases,
    required this.topics,
  });

  factory SyllabusTrackSubject.fromJson(Map<String, dynamic> json) {
    final rawTopics = (json['topics'] as List?) ?? const [];
    return SyllabusTrackSubject(
      name: json['name']?.toString() ?? '',
      marks: (json['marks'] as num?)?.toInt() ?? 0,
      aliases: ((json['aliases'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      topics: rawTopics
          .whereType<Map>()
          .map((e) => SyllabusTrackTopic.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

@immutable
class SyllabusTrackTopic {
  final String title;
  final int weight;

  const SyllabusTrackTopic({required this.title, required this.weight});

  factory SyllabusTrackTopic.fromJson(Map<String, dynamic> json) =>
      SyllabusTrackTopic(
        title: json['title']?.toString() ?? '',
        weight: (json['weight'] as num?)?.toInt() ?? 1,
      );
}

/// The stable identity of a subject node.
String subjectNodeKey(String trackKey, String subjectName) =>
    '$trackKey/${topicMergeKey(subjectName)}';

/// The stable identity of a topic node.
String topicNodeKey(String trackKey, String subjectName, String topicTitle) =>
    '${subjectNodeKey(trackKey, subjectName)}/${topicMergeKey(topicTitle)}';

/// Loads, seeds and reads the syllabus map.
class SyllabusService {
  SyllabusService._();
  static final SyllabusService instance = SyllabusService._();

  /// Parses the bundled maps. Separate from [seed] so the content can be
  /// checked in a test without a database.
  Future<List<SyllabusTrack>> loadBundledTracks() async {
    final tracks = <SyllabusTrack>[];
    for (final path in bundledSyllabusAssets) {
      try {
        final raw = await rootBundle.loadString(path);
        tracks.add(
          SyllabusTrack.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (e) {
        debugPrint('Syllabus: could not load $path: $e');
      }
    }
    return tracks;
  }

  /// Writes the bundled maps into the database, leaving progress alone.
  ///
  /// Safe to run on every launch: nodes are matched by their stable key, so
  /// this refreshes titles, weights and ordering in place. Topics the user
  /// added are never touched, and a bundled topic that has since been dropped
  /// from the asset is removed only if the user has not touched it — a
  /// ticked topic is kept, because deleting it would silently lower a figure
  /// the user has already seen.
  Future<void> seed(AppDatabase db, {List<SyllabusTrack>? tracks}) async {
    final loaded = tracks ?? await loadBundledTracks();
    if (loaded.isEmpty) return;

    for (final track in loaded) {
      if (track.trackKey.isEmpty) continue;
      final seenKeys = <String>{};

      for (var s = 0; s < track.subjects.length; s++) {
        final subject = track.subjects[s];
        final subjectKey = subjectNodeKey(track.trackKey, subject.name);
        if (!seenKeys.add(subjectKey)) continue;

        await _upsertNode(
          db,
          nodeKey: subjectKey,
          trackKey: track.trackKey,
          kind: SyllabusNodeKind.subject,
          parentId: null,
          title: subject.name,
          mergeKey: topicMergeKey(subject.name),
          marks: subject.marks,
          weight: 1,
          orderIndex: s,
        );

        final subjectRow = await _nodeByKey(db, subjectKey);
        if (subjectRow == null) continue;

        for (var t = 0; t < subject.topics.length; t++) {
          final topic = subject.topics[t];
          final key = topicNodeKey(track.trackKey, subject.name, topic.title);
          // Two bundled topics can reduce to the same merge key — anything
          // after " - " or a comma is stripped as an example. Skipping the
          // duplicate keeps the unique index from throwing and losing the
          // rest of the seed.
          if (!seenKeys.add(key)) continue;

          await _upsertNode(
            db,
            nodeKey: key,
            trackKey: track.trackKey,
            kind: SyllabusNodeKind.topic,
            parentId: subjectRow.id,
            title: topic.title,
            mergeKey: topicMergeKey(topic.title),
            marks: 0,
            weight: topic.weight,
            orderIndex: t,
          );
        }
      }

      await _pruneUntouched(db, track.trackKey, seenKeys);
    }
  }

  Future<void> _upsertNode(
    AppDatabase db, {
    required String nodeKey,
    required String trackKey,
    required SyllabusNodeKind kind,
    required int? parentId,
    required String title,
    required String mergeKey,
    required int marks,
    required int weight,
    required int orderIndex,
  }) async {
    await db
        .into(db.syllabusNodes)
        .insert(
          SyllabusNodesCompanion.insert(
            nodeKey: nodeKey,
            trackKey: trackKey,
            kind: kind,
            parentId: Value(parentId),
            title: title,
            mergeKey: mergeKey,
            marks: Value(marks),
            weight: Value(weight),
            orderIndex: Value(orderIndex),
          ),
          onConflict: DoUpdate(
            (_) => SyllabusNodesCompanion(
              trackKey: Value(trackKey),
              kind: Value(kind),
              parentId: Value(parentId),
              title: Value(title),
              mergeKey: Value(mergeKey),
              marks: Value(marks),
              weight: Value(weight),
              orderIndex: Value(orderIndex),
            ),
            target: [db.syllabusNodes.nodeKey],
          ),
        );
  }

  Future<SyllabusNode?> _nodeByKey(AppDatabase db, String key) =>
      (db.select(db.syllabusNodes)
            ..where((t) => t.nodeKey.equals(key))
            ..limit(1))
          .getSingleOrNull();

  /// Drops bundled nodes the asset no longer lists, unless the user has
  /// recorded progress against them.
  Future<void> _pruneUntouched(
    AppDatabase db,
    String trackKey,
    Set<String> keep,
  ) async {
    final rows =
        await (db.select(db.syllabusNodes)..where(
              (t) => t.trackKey.equals(trackKey) & t.isCustom.equals(false),
            ))
            .get();

    final touched = await _progressKeys(db);
    for (final row in rows) {
      if (keep.contains(row.nodeKey)) continue;
      if (touched.contains(row.nodeKey)) continue;
      await (db.delete(
        db.syllabusNodes,
      )..where((t) => t.id.equals(row.id))).go();
    }
  }

  Future<Set<String>> _progressKeys(AppDatabase db) async {
    final rows = await db.select(db.syllabusProgress).get();
    return rows.map((r) => r.nodeKey).toSet();
  }

  /// Every track key present in the map, in seeding order.
  Future<List<String>> trackKeys(AppDatabase db) async {
    final rows =
        await (db.select(db.syllabusNodes)
              ..orderBy([(t) => OrderingTerm(expression: t.id)]))
            .get();
    final seen = <String>[];
    for (final row in rows) {
      if (!seen.contains(row.trackKey)) seen.add(row.trackKey);
    }
    return seen;
  }

  /// One track's subjects and topics with the user's status attached.
  Future<List<CoverageSubject>> loadCoverage(
    AppDatabase db,
    String trackKey,
  ) async {
    final nodes =
        await (db.select(db.syllabusNodes)
              ..where((t) => t.trackKey.equals(trackKey))
              ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
            .get();
    if (nodes.isEmpty) return const [];

    final progress = {
      for (final row in await db.select(db.syllabusProgress).get())
        row.nodeKey: row.status,
    };

    final subjects = nodes
        .where((n) => n.kind == SyllabusNodeKind.subject)
        .toList();
    final topicsByParent = <int, List<SyllabusNode>>{};
    for (final node in nodes) {
      if (node.kind != SyllabusNodeKind.topic) continue;
      final parent = node.parentId;
      if (parent == null) continue;
      topicsByParent.putIfAbsent(parent, () => []).add(node);
    }

    return subjects
        .map(
          (subject) => CoverageSubject(
            nodeKey: subject.nodeKey,
            name: subject.title,
            marks: subject.marks,
            topics: (topicsByParent[subject.id] ?? const <SyllabusNode>[])
                .map(
                  (topic) => CoverageTopic(
                    nodeKey: topic.nodeKey,
                    title: topic.title,
                    weight: topic.weight,
                    status:
                        progress[topic.nodeKey] ?? SyllabusStatus.notStarted,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  /// Records where the user has put a topic.
  ///
  /// [SyllabusStatus.notStarted] removes the row rather than storing it, so
  /// an untouched topic and one the user has reset look the same to every
  /// reader — including the prune above, which must not treat a reset topic
  /// as worth keeping.
  Future<void> setStatus(
    AppDatabase db, {
    required String nodeKey,
    required SyllabusStatus status,
    SyllabusProgressSource source = SyllabusProgressSource.self,
    String? note,
    DateTime? at,
  }) async {
    if (status == SyllabusStatus.notStarted) {
      await (db.delete(
        db.syllabusProgress,
      )..where((t) => t.nodeKey.equals(nodeKey))).go();
      return;
    }

    await db
        .into(db.syllabusProgress)
        .insertOnConflictUpdate(
          SyllabusProgressCompanion.insert(
            nodeKey: nodeKey,
            status: status,
            source: source,
            markedAt: Value(at ?? DateTime.now()),
            note: Value(note),
          ),
        );
  }

  Future<Map<String, SyllabusStatus>> statusMap(AppDatabase db) async {
    final rows = await db.select(db.syllabusProgress).get();
    return {for (final row in rows) row.nodeKey: row.status};
  }
}
