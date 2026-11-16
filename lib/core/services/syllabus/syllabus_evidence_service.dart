import 'package:drift/drift.dart';

import '../../data/study_data_cleanup.dart';
import '../../data/syllabus_proposals.dart';
import '../../database/app_database.dart';
import '../../database/tables/syllabus_nodes_table.dart';
import '../../database/tables/weak_topics_table.dart';

/// Joins what the user has already done onto the syllabus map.
///
/// Nothing new is recorded on either side. Drills, weak topics and completed
/// exams all carry free-text subject and topic strings typed by whichever
/// screen created them; `topicMergeKey` is what makes those meet a syllabus
/// node, and it is the same key the weak-topic de-duplication already uses,
/// so a topic that merges there merges here.
///
/// The result is evidence, not progress. It feeds the proposals the user is
/// asked to confirm — see `syllabus_proposals.dart` for why nothing here
/// writes a status.
class SyllabusEvidenceService {
  SyllabusEvidenceService._();
  static final SyllabusEvidenceService instance = SyllabusEvidenceService._();

  /// Evidence for every topic in [trackKey] that has any.
  ///
  /// Topics with nothing against them are left out rather than returned
  /// empty: the caller's next step is to ask the user about these, and there
  /// is nothing to ask about a topic they have never touched.
  Future<List<TopicEvidence>> gather(AppDatabase db, String trackKey) async {
    final nodes =
        await (db.select(db.syllabusNodes)..where(
              (t) =>
                  t.trackKey.equals(trackKey) &
                  t.kind.equalsValue(SyllabusNodeKind.topic),
            ))
            .get();
    if (nodes.isEmpty) return const [];

    // A merge key can belong to more than one node — the same topic sits in
    // two subjects in some tracks — so evidence is credited to each.
    final nodesByMergeKey = <String, List<SyllabusNode>>{};
    for (final node in nodes) {
      nodesByMergeKey.putIfAbsent(node.mergeKey, () => []).add(node);
    }

    final attempts = <String, int>{};
    final corrects = <String, int>{};
    for (final q in await db.select(db.drillQuestions).get()) {
      final key = topicMergeKey(q.topic);
      if (key.isEmpty) continue;
      // attemptCount and wrongCount are the folded history of re-drilling the
      // same question, which is a truer count than one row per attempt.
      final attempted = q.attemptCount < 1 ? 1 : q.attemptCount;
      final wrong = q.wrongCount.clamp(0, attempted);
      attempts[key] = (attempts[key] ?? 0) + attempted;
      corrects[key] = (corrects[key] ?? 0) + (attempted - wrong);
    }

    final weakKeys = <String>{};
    for (final t in await db.select(db.weakTopics).get()) {
      if (t.proficiencyLevel != ProficiencyLevel.weak) continue;
      final key = topicMergeKey(t.topicName);
      if (key.isNotEmpty) weakKeys.add(key);
    }

    final examKeys = <String>{};
    final completedExams = await (db.select(
      db.examSchedules,
    )..where((t) => t.completedStatus.equals(true))).get();
    for (final exam in completedExams) {
      for (final part in splitRoutineTopics(exam.topicsCovered)) {
        final key = topicMergeKey(part);
        if (key.isNotEmpty) examKeys.add(key);
      }
    }

    final out = <TopicEvidence>[];
    for (final entry in nodesByMergeKey.entries) {
      final key = entry.key;
      final attempted = attempts[key] ?? 0;
      final isWeak = weakKeys.contains(key);
      final examDone = examKeys.contains(key);
      if (attempted == 0 && !isWeak && !examDone) continue;

      for (final node in entry.value) {
        out.add(
          TopicEvidence(
            nodeKey: node.nodeKey,
            title: node.title,
            attempted: attempted,
            correct: corrects[key] ?? 0,
            isWeakTopic: isWeak,
            examCompleted: examDone,
          ),
        );
      }
    }
    return out;
  }
}

/// Splits an exam's free-text `topicsCovered` into candidate topics.
///
/// Kept here rather than in the widget that already does this so the map and
/// the existing per-exam checklist cannot drift apart.
///
/// A comma followed by a Bengali or capitalised word starts a new topic,
/// because routine lists are written that way — "কারক ও বিভক্তি, সমাস,
/// শতকরা" is three topics. The cost is that a topic whose own name contains
/// a comma, such as "নৈতিকতা, মূল্যবোধ ও সুশাসন", comes back split. That is
/// the right trade here: this feeds evidence, where an over-split name
/// simply fails to match a syllabus node and is dropped, while an
/// under-split one would smuggle three topics in under a key belonging to
/// none of them.
List<String> splitRoutineTopics(String raw) {
  return raw
      .split(RegExp(r'[\n•;]+|,\s*(?=[A-Zঀ-৿])'))
      .map((s) => s.trim())
      .where((s) {
        if (s.isEmpty) return false;
        final lower = s.toLowerCase();
        return lower != 'math:' &&
            lower != 'topic:' &&
            lower != 'syllabus:' &&
            lower != 'general syllabus';
      })
      .toList();
}
