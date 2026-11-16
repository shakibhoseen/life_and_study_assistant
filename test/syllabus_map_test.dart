import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/data/study_data_cleanup.dart';
import 'package:life_and_study_assistant/core/data/syllabus_coverage.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/tables/syllabus_nodes_table.dart';
import 'package:life_and_study_assistant/core/database/tables/syllabus_progress_table.dart';
import 'package:life_and_study_assistant/core/database/tables/weak_topics_table.dart';
import 'package:life_and_study_assistant/core/services/syllabus/syllabus_evidence_service.dart';
import 'package:life_and_study_assistant/core/services/syllabus/syllabus_service.dart';

/// The syllabus map, from the shipped JSON through to coverage.
///
/// The bundled content gets tested as strictly as the code, because it is the
/// part that will be edited most often and the part whose mistakes are
/// silent: marks that no longer add up to the exam's total still render a
/// perfectly confident percentage.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bundled content', () {
    for (final path in bundledSyllabusAssets) {
      group(path.split('/').last, () {
        late SyllabusTrack track;

        setUpAll(() {
          final raw = File(path).readAsStringSync();
          track = SyllabusTrack.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
          );
        });

        test('subject marks add up to the declared total', () {
          final sum = track.subjects.fold<int>(0, (a, s) => a + s.marks);
          expect(
            sum,
            track.totalMarks,
            reason: 'the exam total and the subject marks disagree',
          );
        });

        test('has a track key, a name and subjects', () {
          expect(track.trackKey, isNotEmpty);
          expect(track.trackName, isNotEmpty);
          expect(track.subjects, isNotEmpty);
        });

        test('every subject has marks and topics', () {
          for (final subject in track.subjects) {
            expect(subject.name, isNotEmpty);
            expect(subject.marks, greaterThan(0), reason: subject.name);
            expect(subject.topics, isNotEmpty, reason: subject.name);
          }
        });

        test('every topic has a title and a positive weight', () {
          for (final subject in track.subjects) {
            for (final topic in subject.topics) {
              expect(topic.title.trim(), isNotEmpty, reason: subject.name);
              expect(
                topic.weight,
                greaterThan(0),
                reason: '${subject.name} / ${topic.title}',
              );
            }
          }
        });

        test('no two topics in a subject collapse to the same key', () {
          // A collision would silently drop one topic at seed time and make
          // the subject permanently un-finishable, since its weight stays in
          // the denominator of the asset but never reaches a row.
          for (final subject in track.subjects) {
            final keys = <String, String>{};
            for (final topic in subject.topics) {
              final key = topicMergeKey(topic.title);
              expect(
                keys.containsKey(key),
                isFalse,
                reason:
                    '${subject.name}: "${topic.title}" and "${keys[key]}" '
                    'both reduce to "$key"',
              );
              keys[key] = topic.title;
            }
          }
        });

        test('no two subjects collapse to the same key', () {
          final keys = <String>{};
          for (final subject in track.subjects) {
            expect(
              keys.add(topicMergeKey(subject.name)),
              isTrue,
              reason: subject.name,
            );
          }
        });
      });
    }

    test('track keys are distinct across the bundled files', () {
      final keys = <String>[];
      for (final path in bundledSyllabusAssets) {
        final raw = File(path).readAsStringSync();
        keys.add(
          SyllabusTrack.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
          ).trackKey,
        );
      }
      expect(keys.toSet().length, keys.length);
    });
  });

  group('seeding', () {
    late AppDatabase db;

    SyllabusTrack track({
      String name = 'গণিত',
      List<SyllabusTrackTopic>? topics,
      int marks = 20,
    }) => SyllabusTrack(
      trackKey: 'test',
      trackName: 'পরীক্ষা',
      totalMarks: marks,
      note: '',
      subjects: [
        SyllabusTrackSubject(
          name: name,
          marks: marks,
          aliases: const [],
          topics:
              topics ??
              const [
                SyllabusTrackTopic(title: 'শতকরা', weight: 2),
                SyllabusTrackTopic(title: 'লাভ-ক্ষতি', weight: 1),
              ],
        ),
      ],
    );

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('creates subjects and topics with the right shape', () async {
      await SyllabusService.instance.seed(db, tracks: [track()]);

      final nodes = await db.select(db.syllabusNodes).get();
      expect(nodes.length, 3);

      final subject = nodes.firstWhere(
        (n) => n.kind == SyllabusNodeKind.subject,
      );
      expect(subject.marks, 20);

      final topics = nodes.where((n) => n.kind == SyllabusNodeKind.topic);
      expect(topics.every((t) => t.parentId == subject.id), isTrue);
      expect(topics.map((t) => t.weight).toList()..sort(), [1, 2]);
    });

    test('seeding twice does not duplicate rows', () async {
      await SyllabusService.instance.seed(db, tracks: [track()]);
      await SyllabusService.instance.seed(db, tracks: [track()]);

      expect((await db.select(db.syllabusNodes).get()).length, 3);
    });

    test('a reworded topic keeps the tick when its key survives', () async {
      await SyllabusService.instance.seed(db, tracks: [track()]);

      final key = topicNodeKey('test', 'গণিত', 'শতকরা');
      await SyllabusService.instance.setStatus(
        db,
        nodeKey: key,
        status: SyllabusStatus.done,
      );

      // The same topic, written with an example after it — topicMergeKey
      // strips what follows " - ", so this is still the same node.
      await SyllabusService.instance.seed(
        db,
        tracks: [
          track(
            topics: const [
              SyllabusTrackTopic(title: 'শতকরা - সরল ও যৌগিক', weight: 3),
              SyllabusTrackTopic(title: 'লাভ-ক্ষতি', weight: 1),
            ],
          ),
        ],
      );

      final statuses = await SyllabusService.instance.statusMap(db);
      expect(statuses[key], SyllabusStatus.done);

      final node = (await db.select(
        db.syllabusNodes,
      ).get()).firstWhere((n) => n.nodeKey == key);
      expect(node.title, 'শতকরা - সরল ও যৌগিক', reason: 'title should refresh');
      expect(node.weight, 3, reason: 'weight should refresh');
    });

    test('drops a withdrawn topic the user never touched', () async {
      await SyllabusService.instance.seed(db, tracks: [track()]);
      await SyllabusService.instance.seed(
        db,
        tracks: [
          track(
            topics: const [SyllabusTrackTopic(title: 'শতকরা', weight: 2)],
          ),
        ],
      );

      final titles = (await db.select(
        db.syllabusNodes,
      ).get()).map((n) => n.title);
      expect(titles, isNot(contains('লাভ-ক্ষতি')));
    });

    test('keeps a withdrawn topic the user had marked', () async {
      await SyllabusService.instance.seed(db, tracks: [track()]);
      await SyllabusService.instance.setStatus(
        db,
        nodeKey: topicNodeKey('test', 'গণিত', 'লাভ-ক্ষতি'),
        status: SyllabusStatus.done,
      );

      await SyllabusService.instance.seed(
        db,
        tracks: [
          track(
            topics: const [SyllabusTrackTopic(title: 'শতকরা', weight: 2)],
          ),
        ],
      );

      // Removing it would drop the coverage figure under the user without
      // anything of theirs having changed.
      final titles = (await db.select(
        db.syllabusNodes,
      ).get()).map((n) => n.title);
      expect(titles, contains('লাভ-ক্ষতি'));
    });

    test('resetting to notStarted removes the row', () async {
      await SyllabusService.instance.seed(db, tracks: [track()]);
      final key = topicNodeKey('test', 'গণিত', 'শতকরা');

      await SyllabusService.instance.setStatus(
        db,
        nodeKey: key,
        status: SyllabusStatus.done,
      );
      await SyllabusService.instance.setStatus(
        db,
        nodeKey: key,
        status: SyllabusStatus.notStarted,
      );

      expect(await db.select(db.syllabusProgress).get(), isEmpty);
    });

    test('coverage reads back through the database', () async {
      await SyllabusService.instance.seed(db, tracks: [track()]);
      await SyllabusService.instance.setStatus(
        db,
        nodeKey: topicNodeKey('test', 'গণিত', 'শতকরা'),
        status: SyllabusStatus.done,
      );

      final subjects = await SyllabusService.instance.loadCoverage(db, 'test');
      final tally = tallyTrack(subjects);

      // শতকরা carries two of the three weight.
      expect(tally.doneFraction, closeTo(2 / 3, 1e-9));
      expect(tally.marksTotal, 20);
    });
  });

  group('evidence from existing data', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await SyllabusService.instance.seed(
        db,
        tracks: [
          const SyllabusTrack(
            trackKey: 'test',
            trackName: 'পরীক্ষা',
            totalMarks: 20,
            note: '',
            subjects: [
              SyllabusTrackSubject(
                name: 'গণিত',
                marks: 20,
                aliases: [],
                topics: [
                  SyllabusTrackTopic(title: 'শতকরা', weight: 1),
                  SyllabusTrackTopic(title: 'লাভ-ক্ষতি', weight: 1),
                ],
              ),
            ],
          ),
        ],
      );
    });
    tearDown(() => db.close());

    Future<void> addQuestion({
      required String topic,
      required int attempts,
      required int wrong,
    }) async {
      await db
          .into(db.drillQuestions)
          .insert(
            DrillQuestionsCompanion.insert(
              subject: 'গণিত',
              topic: topic,
              questionText: 'প্রশ্ন $topic $attempts $wrong',
              optionsJson: '["ক","খ"]',
              correctIndex: 0,
              selectedIndex: 0,
              isCorrect: wrong == 0,
              attemptCount: Value(attempts),
              wrongCount: Value(wrong),
            ),
          );
    }

    test('matches drill topics onto nodes through the merge key', () async {
      // Written the way a screen would, with an example in brackets that
      // topicMergeKey strips.
      await addQuestion(topic: 'শতকরা (সরল)', attempts: 5, wrong: 1);
      await addQuestion(topic: 'শতকরা', attempts: 4, wrong: 0);

      final evidence = await SyllabusEvidenceService.instance.gather(
        db,
        'test',
      );

      final percent = evidence.firstWhere((e) => e.title == 'শতকরা');
      expect(percent.attempted, 9);
      expect(percent.correct, 8);
    });

    test('leaves out topics with nothing against them', () async {
      await addQuestion(topic: 'শতকরা', attempts: 3, wrong: 0);

      final evidence = await SyllabusEvidenceService.instance.gather(
        db,
        'test',
      );

      expect(evidence.map((e) => e.title), ['শতকরা']);
    });

    test('flags a topic that is on the weak list', () async {
      await addQuestion(topic: 'লাভ-ক্ষতি', attempts: 8, wrong: 1);
      await db
          .into(db.weakTopics)
          .insert(
            WeakTopicsCompanion.insert(
              subject: 'গণিত',
              topicName: 'লাভ-ক্ষতি',
              proficiencyLevel: ProficiencyLevel.weak,
            ),
          );

      final evidence = await SyllabusEvidenceService.instance.gather(
        db,
        'test',
      );

      expect(evidence.single.isWeakTopic, isTrue);
    });

    test('a completed exam marks its topics as seen', () async {
      await db
          .into(db.examSchedules)
          .insert(
            ExamSchedulesCompanion.insert(
              examDate: DateTime(2026, 11, 1),
              title: 'মডেল টেস্ট',
              topicsCovered: 'শতকরা, লাভ-ক্ষতি',
              completedStatus: const Value(true),
            ),
          );

      final evidence = await SyllabusEvidenceService.instance.gather(
        db,
        'test',
      );

      expect(evidence.length, 2);
      expect(evidence.every((e) => e.examCompleted), isTrue);
      expect(evidence.every((e) => e.attempted == 0), isTrue);
    });

    test('an unfinished exam is not evidence', () async {
      await db
          .into(db.examSchedules)
          .insert(
            ExamSchedulesCompanion.insert(
              examDate: DateTime(2026, 11, 1),
              title: 'মডেল টেস্ট',
              topicsCovered: 'শতকরা',
            ),
          );

      expect(
        await SyllabusEvidenceService.instance.gather(db, 'test'),
        isEmpty,
      );
    });
  });

  group('routine topic splitting', () {
    test('splits a comma-separated routine list', () {
      // How routines are actually written, and the case this has to get
      // right: three topics, not one long string that matches no node.
      expect(splitRoutineTopics('কারক ও বিভক্তি, সমাস, শতকরা'), [
        'কারক ও বিভক্তি',
        'সমাস',
        'শতকরা',
      ]);
    });

    test('a topic whose own name holds a comma comes back split', () {
      // Documented rather than fixed: an over-split name matches no syllabus
      // node and is dropped, which is the harmless direction to fail in.
      expect(splitRoutineTopics('নৈতিকতা, মূল্যবোধ ও সুশাসন'), [
        'নৈতিকতা',
        'মূল্যবোধ ও সুশাসন',
      ]);
    });

    test('splits on bullets and newlines', () {
      expect(splitRoutineTopics('শতকরা\n• লাভ-ক্ষতি; সুদকষা'), [
        'শতকরা',
        'লাভ-ক্ষতি',
        'সুদকষা',
      ]);
    });

    test('drops the placeholder an import writes when it found nothing', () {
      expect(splitRoutineTopics('General Syllabus'), isEmpty);
    });
  });
}
