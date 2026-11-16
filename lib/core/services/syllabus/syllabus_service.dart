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
  'assets/data/syllabus/ntrca_preliminary.json',
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

    for (var index = 0; index < loaded.length; index++) {
      final track = loaded[index];
      if (track.trackKey.isEmpty) continue;

      await _upsertTrackRow(
        db,
        trackKey: track.trackKey,
        name: track.trackName,
        note: track.note,
        orderIndex: index,
      );

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
    // Once the user has edited a node it is theirs, and the seed stops
    // writing to it. Without this, re-seeding on every launch would undo a
    // renamed topic or a reweighted one within seconds of the edit, and the
    // user would have no way to tell why their change kept vanishing.
    final existing = await _nodeByKey(db, nodeKey);
    if (existing != null && existing.isCustom) return;

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

  /// Writes a bundled track's row, leaving a track the user made alone.
  Future<void> _upsertTrackRow(
    AppDatabase db, {
    required String trackKey,
    required String name,
    required String note,
    required int orderIndex,
  }) async {
    final existing = await trackByKey(db, trackKey);
    if (existing != null && existing.isCustom) return;

    await db
        .into(db.syllabusTracks)
        .insert(
          SyllabusTracksCompanion.insert(
            trackKey: trackKey,
            name: name,
            note: Value(note),
            orderIndex: Value(orderIndex),
          ),
          onConflict: DoUpdate(
            (_) => SyllabusTracksCompanion(
              name: Value(name),
              note: Value(note),
              orderIndex: Value(orderIndex),
            ),
            target: [db.syllabusTracks.trackKey],
          ),
        );
  }

  Future<SyllabusTrackRow?> trackByKey(AppDatabase db, String trackKey) =>
      (db.select(db.syllabusTracks)
            ..where((t) => t.trackKey.equals(trackKey))
            ..limit(1))
          .getSingleOrNull();

  /// Every track, bundled first in seed order, then the user's by age.
  Future<List<SyllabusTrackRow>> tracks(AppDatabase db) =>
      (db.select(db.syllabusTracks)..orderBy([
            (t) => OrderingTerm(expression: t.isCustom),
            (t) => OrderingTerm(expression: t.orderIndex),
            (t) => OrderingTerm(expression: t.createdAt),
          ]))
          .get();

  /// Creates an exam of the user's own.
  ///
  /// The key is generated from the clock rather than the name: an exam the
  /// user renames later must keep the syllabus they built under it, and two
  /// exams with names that reduce to the same merge key must still be two
  /// exams.
  ///
  /// Returns the new track's key, or null if the name is empty or taken.
  Future<String?> createTrack(
    AppDatabase db, {
    required String name,
    String note = '',
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    final existing = await tracks(db);
    if (existing.any((t) => t.name.trim() == trimmed)) return null;

    final key = 'custom_${DateTime.now().microsecondsSinceEpoch}';
    await db
        .into(db.syllabusTracks)
        .insert(
          SyllabusTracksCompanion.insert(
            trackKey: key,
            name: trimmed,
            note: Value(note),
            isCustom: const Value(true),
            orderIndex: Value(existing.length),
          ),
        );
    return key;
  }

  /// Creates a track from another one's subjects and topics.
  ///
  /// Nothing of the source's progress comes with it. The exams overlap, but
  /// what the user has covered for one is a claim about that syllabus, and
  /// copying ticks across would hand them a percentage they never earned.
  Future<String?> copyTrack(
    AppDatabase db, {
    required String sourceTrackKey,
    required String name,
    String note = '',
  }) async {
    final source = await loadCoverage(db, sourceTrackKey);
    return createTrackFrom(
      db,
      name: name,
      note: note,
      subjects: source
          .map(
            (subject) => SyllabusTrackSubject(
              name: subject.name,
              marks: subject.marks,
              aliases: const [],
              topics: subject.topics
                  // A topic the user had removed from the source is not part
                  // of the syllabus they are copying.
                  .where((t) => t.status != SyllabusStatus.hidden)
                  .map(
                    (t) => SyllabusTrackTopic(
                      title: t.title,
                      weight: t.weight,
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
    );
  }

  /// Creates a track of the user's own from a ready-made list of subjects.
  ///
  /// Shared by copying an existing track and by accepting an AI draft: both
  /// arrive with the same shape, and both must land as ordinary custom rows
  /// the user can then edit, with no trace of where they came from beyond
  /// the note.
  Future<String?> createTrackFrom(
    AppDatabase db, {
    required String name,
    required List<SyllabusTrackSubject> subjects,
    String note = '',
  }) async {
    final key = await createTrack(db, name: name, note: note);
    if (key == null) return null;

    for (final subject in subjects) {
      final subjectKey = await addSubject(
        db,
        trackKey: key,
        name: subject.name,
        marks: subject.marks,
      );
      if (subjectKey == null) continue;

      for (final topic in subject.topics) {
        await addCustomTopic(
          db,
          subjectNodeKey: subjectKey,
          title: topic.title,
          weight: topic.weight,
        );
      }
    }
    return key;
  }

  Future<bool> renameTrack(
    AppDatabase db, {
    required String trackKey,
    required String name,
    String? note,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;

    final row = await trackByKey(db, trackKey);
    if (row == null) return false;

    await (db.update(db.syllabusTracks)..where((t) => t.id.equals(row.id)))
        .write(
          SyllabusTracksCompanion(
            name: Value(trimmed),
            note: note == null ? const Value.absent() : Value(note),
          ),
        );
    return true;
  }

  /// Deletes a track the user made, with its syllabus and its progress.
  ///
  /// A bundled track is refused: the seed would rebuild its nodes on the next
  /// launch and leave a track row missing beneath them.
  Future<bool> deleteTrack(AppDatabase db, {required String trackKey}) async {
    final row = await trackByKey(db, trackKey);
    if (row == null || !row.isCustom) return false;

    final nodes = await (db.select(
      db.syllabusNodes,
    )..where((t) => t.trackKey.equals(trackKey))).get();
    for (final node in nodes) {
      await (db.delete(
        db.syllabusProgress,
      )..where((t) => t.nodeKey.equals(node.nodeKey))).go();
    }
    await (db.delete(
      db.syllabusNodes,
    )..where((t) => t.trackKey.equals(trackKey))).go();
    await (db.delete(
      db.syllabusTracks,
    )..where((t) => t.id.equals(row.id))).go();
    return true;
  }

  /// Adds a subject to a track, with the marks it carries in that exam.
  ///
  /// Returns the new subject's node key, or null if the name is empty or
  /// already used in the track.
  Future<String?> addSubject(
    AppDatabase db, {
    required String trackKey,
    required String name,
    required int marks,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    final mergeKey = topicMergeKey(trimmed);
    if (mergeKey.isEmpty) return null;

    final siblings = await (db.select(
      db.syllabusNodes,
    )..where(
          (t) =>
              t.trackKey.equals(trackKey) &
              t.kind.equalsValue(SyllabusNodeKind.subject),
        ))
        .get();
    if (siblings.any((s) => s.mergeKey == mergeKey)) return null;

    final key = subjectNodeKey(trackKey, trimmed);
    await db
        .into(db.syllabusNodes)
        .insert(
          SyllabusNodesCompanion.insert(
            nodeKey: key,
            trackKey: trackKey,
            kind: SyllabusNodeKind.subject,
            title: trimmed,
            mergeKey: mergeKey,
            marks: Value(marks < 0 ? 0 : marks),
            orderIndex: Value(siblings.length),
            isCustom: const Value(true),
          ),
        );
    return key;
  }

  Future<bool> editSubject(
    AppDatabase db, {
    required String nodeKey,
    String? name,
    int? marks,
  }) async {
    final node = await _nodeByKey(db, nodeKey);
    if (node == null || node.kind != SyllabusNodeKind.subject) return false;

    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isEmpty) return false;
    final mergeKey = trimmed == null ? null : topicMergeKey(trimmed);
    if (mergeKey != null && mergeKey.isEmpty) return false;

    await (db.update(db.syllabusNodes)..where((t) => t.id.equals(node.id)))
        .write(
          SyllabusNodesCompanion(
            title: trimmed == null ? const Value.absent() : Value(trimmed),
            mergeKey: mergeKey == null ? const Value.absent() : Value(mergeKey),
            marks: marks == null
                ? const Value.absent()
                : Value(marks < 0 ? 0 : marks),
            isCustom: const Value(true),
          ),
        );
    return true;
  }

  /// Removes a subject and everything under it.
  ///
  /// Only from a track the user made. A bundled track's subjects are the
  /// exam's own mark distribution, and the seed would rebuild them anyway.
  Future<bool> removeSubject(
    AppDatabase db, {
    required String nodeKey,
  }) async {
    final node = await _nodeByKey(db, nodeKey);
    if (node == null || node.kind != SyllabusNodeKind.subject) return false;

    final track = await trackByKey(db, node.trackKey);
    if (track == null || !track.isCustom) return false;

    final children = await (db.select(
      db.syllabusNodes,
    )..where((t) => t.parentId.equals(node.id))).get();
    for (final child in [...children, node]) {
      await (db.delete(
        db.syllabusProgress,
      )..where((t) => t.nodeKey.equals(child.nodeKey))).go();
      await (db.delete(
        db.syllabusNodes,
      )..where((t) => t.id.equals(child.id))).go();
    }
    return true;
  }

  /// Adds a topic of the user's own to a subject.
  ///
  /// Marked [SyllabusNodes.isCustom], so neither the seed nor the prune will
  /// touch it. Its key carries a `custom/` segment: two topics the user adds
  /// with names that reduce to the same merge key are still separate rows,
  /// where bundled content deliberately collapses them.
  ///
  /// Returns the new node's key, or null if the subject is unknown or a
  /// topic with that name is already there.
  Future<String?> addCustomTopic(
    AppDatabase db, {
    required String subjectNodeKey,
    required String title,
    int weight = 2,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return null;

    final subject = await _nodeByKey(db, subjectNodeKey);
    if (subject == null || subject.kind != SyllabusNodeKind.subject) {
      return null;
    }

    final mergeKey = topicMergeKey(trimmed);
    if (mergeKey.isEmpty) return null;

    final siblings =
        await (db.select(db.syllabusNodes)
              ..where((t) => t.parentId.equals(subject.id)))
            .get();
    if (siblings.any((s) => s.mergeKey == mergeKey)) return null;

    final key = '$subjectNodeKey/custom/$mergeKey';
    final order = siblings.fold<int>(
      0,
      (max, s) => s.orderIndex > max ? s.orderIndex : max,
    );

    await db
        .into(db.syllabusNodes)
        .insert(
          SyllabusNodesCompanion.insert(
            nodeKey: key,
            trackKey: subject.trackKey,
            kind: SyllabusNodeKind.topic,
            parentId: Value(subject.id),
            title: trimmed,
            mergeKey: mergeKey,
            weight: Value(weight < 1 ? 1 : weight),
            orderIndex: Value(order + 1),
            isCustom: const Value(true),
          ),
        );
    return key;
  }

  /// Renames a topic or changes its weight.
  ///
  /// The node keeps its key, so progress recorded against it survives a
  /// rename; the merge key does move, so evidence from drills joins on the
  /// new name. Editing a bundled topic claims it: the row becomes custom and
  /// the seed leaves it alone from then on.
  Future<bool> editTopic(
    AppDatabase db, {
    required String nodeKey,
    String? title,
    int? weight,
  }) async {
    final node = await _nodeByKey(db, nodeKey);
    if (node == null || node.kind != SyllabusNodeKind.topic) return false;

    final trimmed = title?.trim();
    if (trimmed != null && trimmed.isEmpty) return false;
    final mergeKey = trimmed == null ? null : topicMergeKey(trimmed);
    if (mergeKey != null && mergeKey.isEmpty) return false;

    await (db.update(db.syllabusNodes)..where((t) => t.id.equals(node.id)))
        .write(
          SyllabusNodesCompanion(
            title: trimmed == null ? const Value.absent() : Value(trimmed),
            mergeKey: mergeKey == null ? const Value.absent() : Value(mergeKey),
            weight: weight == null
                ? const Value.absent()
                : Value(weight < 1 ? 1 : weight),
            isCustom: const Value(true),
          ),
        );
    return true;
  }

  /// Takes a topic out of the user's syllabus.
  ///
  /// A topic the user added is deleted outright. A bundled one is marked
  /// [SyllabusStatus.hidden] instead, because the seed would put a deleted
  /// row straight back on the next launch — and because the user may want it
  /// again, which [restoreTopic] gives them.
  Future<void> removeTopic(AppDatabase db, {required String nodeKey}) async {
    final node = await _nodeByKey(db, nodeKey);
    if (node == null) return;

    // A node the user made is theirs to unmake, whatever state it is in. Its
    // progress row goes with it, or it would sit in the table keyed to a
    // node that no longer exists and quietly keep a later topic of the same
    // name from starting fresh.
    if (node.isCustom && node.nodeKey.contains('/custom/')) {
      await (db.delete(
        db.syllabusProgress,
      )..where((t) => t.nodeKey.equals(nodeKey))).go();
      await (db.delete(
        db.syllabusNodes,
      )..where((t) => t.id.equals(node.id))).go();
      return;
    }

    await setStatus(db, nodeKey: nodeKey, status: SyllabusStatus.hidden);
  }

  /// Puts a hidden topic back, untouched rather than finished.
  Future<void> restoreTopic(AppDatabase db, {required String nodeKey}) =>
      setStatus(db, nodeKey: nodeKey, status: SyllabusStatus.notStarted);

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
