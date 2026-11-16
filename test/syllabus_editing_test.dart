import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/data/syllabus_coverage.dart';
import 'package:life_and_study_assistant/core/data/syllabus_proposals.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/tables/syllabus_progress_table.dart';
import 'package:life_and_study_assistant/core/services/syllabus/syllabus_service.dart';

/// Making the bundled syllabus the user's own.
///
/// The hard part is not the editing — it is that the map re-seeds itself on
/// every launch, so every one of these changes has to survive a seed running
/// straight afterwards. Each test here does exactly that.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  const track = SyllabusTrack(
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
  );

  const subjectKey = 'test/গণিত';
  final percentKey = topicNodeKey('test', 'গণিত', 'শতকরা');
  final profitKey = topicNodeKey('test', 'গণিত', 'লাভ-ক্ষতি');

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await SyllabusService.instance.seed(db, tracks: const [track]);
  });
  tearDown(() => db.close());

  Future<void> reseed() =>
      SyllabusService.instance.seed(db, tracks: const [track]);

  Future<CoverageSubject> subject() async =>
      (await SyllabusService.instance.loadCoverage(db, 'test')).single;

  group('adding', () {
    test('a topic of the user\'s own joins the subject', () async {
      final key = await SyllabusService.instance.addCustomTopic(
        db,
        subjectNodeKey: subjectKey,
        title: 'সুদকষা',
        weight: 2,
      );

      expect(key, isNotNull);
      expect((await subject()).topics.map((t) => t.title), contains('সুদকষা'));
    });

    test('it survives a re-seed', () async {
      await SyllabusService.instance.addCustomTopic(
        db,
        subjectNodeKey: subjectKey,
        title: 'সুদকষা',
      );
      await reseed();

      expect((await subject()).topics.map((t) => t.title), contains('সুদকষা'));
    });

    test('it counts towards the subject like any other topic', () async {
      await SyllabusService.instance.addCustomTopic(
        db,
        subjectNodeKey: subjectKey,
        title: 'সুদকষা',
        weight: 2,
      );

      final tally = tallySubject(await subject());
      expect(tally.totalTopics, 3);
      // Two bundled topics of weight one, plus this one of weight two.
      expect(tally.doneFraction, 0);

      await SyllabusService.instance.setStatus(
        db,
        nodeKey: '$subjectKey/custom/সুদকষা',
        status: SyllabusStatus.done,
      );
      expect(tallySubject(await subject()).doneFraction, closeTo(0.5, 1e-9));
    });

    test('a duplicate name is refused rather than silently merged', () async {
      final key = await SyllabusService.instance.addCustomTopic(
        db,
        subjectNodeKey: subjectKey,
        // Reduces to the same merge key as the bundled "শতকরা".
        title: 'শতকরা (সরল)',
      );

      expect(key, isNull);
      expect((await subject()).topics.length, 2);
    });

    test('an empty name is refused', () async {
      expect(
        await SyllabusService.instance.addCustomTopic(
          db,
          subjectNodeKey: subjectKey,
          title: '   ',
        ),
        isNull,
      );
    });

    test('an unknown subject is refused', () async {
      expect(
        await SyllabusService.instance.addCustomTopic(
          db,
          subjectNodeKey: 'test/নেই',
          title: 'সুদকষা',
        ),
        isNull,
      );
    });
  });

  group('editing', () {
    test('a rename sticks through a re-seed', () async {
      await SyllabusService.instance.editTopic(
        db,
        nodeKey: percentKey,
        title: 'শতকরা ও অনুপাত',
      );
      await reseed();

      final titles = (await subject()).topics.map((t) => t.title);
      expect(titles, contains('শতকরা ও অনুপাত'));
      expect(titles, isNot(contains('শতকরা')));
    });

    test('a reweight sticks through a re-seed', () async {
      await SyllabusService.instance.editTopic(
        db,
        nodeKey: percentKey,
        weight: 3,
      );
      await reseed();

      final topic = (await subject()).topics.firstWhere(
        (t) => t.nodeKey == percentKey,
      );
      expect(topic.weight, 3);
      // Three of the four weight now sits in শতকরা.
      await SyllabusService.instance.setStatus(
        db,
        nodeKey: percentKey,
        status: SyllabusStatus.done,
      );
      expect(tallySubject(await subject()).doneFraction, closeTo(0.75, 1e-9));
    });

    test('a renamed topic keeps the progress recorded against it', () async {
      await SyllabusService.instance.setStatus(
        db,
        nodeKey: percentKey,
        status: SyllabusStatus.done,
      );
      await SyllabusService.instance.editTopic(
        db,
        nodeKey: percentKey,
        title: 'শতকরা ও অনুপাত',
      );

      final topic = (await subject()).topics.firstWhere(
        (t) => t.nodeKey == percentKey,
      );
      expect(topic.status, SyllabusStatus.done);
    });

    test('the merge key moves so later drills match the new name', () async {
      await SyllabusService.instance.editTopic(
        db,
        nodeKey: percentKey,
        title: 'অনুপাত',
      );

      final node = (await db.select(
        db.syllabusNodes,
      ).get()).firstWhere((n) => n.nodeKey == percentKey);
      expect(node.mergeKey, 'অনুপাত');
    });

    test('an empty name is refused and changes nothing', () async {
      expect(
        await SyllabusService.instance.editTopic(
          db,
          nodeKey: percentKey,
          title: '  ',
        ),
        isFalse,
      );
      expect(
        (await subject()).topics.map((t) => t.title),
        contains('শতকরা'),
      );
    });

    test('a subject cannot be edited as a topic', () async {
      expect(
        await SyllabusService.instance.editTopic(
          db,
          nodeKey: subjectKey,
          title: 'অন্য কিছু',
        ),
        isFalse,
      );
    });
  });

  group('removing', () {
    test('a bundled topic leaves the sums entirely', () async {
      await SyllabusService.instance.removeTopic(db, nodeKey: profitKey);

      final tally = tallySubject(await subject());
      // One topic left, not two with one unfinishable.
      expect(tally.totalTopics, 1);

      await SyllabusService.instance.setStatus(
        db,
        nodeKey: percentKey,
        status: SyllabusStatus.done,
      );
      // The subject is finished on the syllabus the user kept.
      expect(tallySubject(await subject()).doneFraction, 1.0);
    });

    test('a bundled topic stays removed through a re-seed', () async {
      await SyllabusService.instance.removeTopic(db, nodeKey: profitKey);
      await reseed();

      final topic = (await subject()).topics.firstWhere(
        (t) => t.nodeKey == profitKey,
      );
      expect(topic.status, SyllabusStatus.hidden);
      expect(tallySubject(await subject()).totalTopics, 1);
    });

    test('a removed topic can be brought back', () async {
      await SyllabusService.instance.removeTopic(db, nodeKey: profitKey);
      await SyllabusService.instance.restoreTopic(db, nodeKey: profitKey);

      final topic = (await subject()).topics.firstWhere(
        (t) => t.nodeKey == profitKey,
      );
      expect(topic.status, SyllabusStatus.notStarted);
      expect(tallySubject(await subject()).totalTopics, 2);
    });

    test('a topic the user added is deleted outright', () async {
      final key = await SyllabusService.instance.addCustomTopic(
        db,
        subjectNodeKey: subjectKey,
        title: 'সুদকষা',
      );
      await SyllabusService.instance.setStatus(
        db,
        nodeKey: key!,
        status: SyllabusStatus.done,
      );

      await SyllabusService.instance.removeTopic(db, nodeKey: key);
      await reseed();

      expect((await subject()).topics.map((t) => t.title), isNot(contains('সুদকষা')));
      // Its progress row goes too, or adding the same topic again would come
      // back already ticked.
      expect(
        (await db.select(db.syllabusProgress).get()).map((r) => r.nodeKey),
        isNot(contains(key)),
      );
    });

    test('no proposal is raised for a removed topic', () {
      expect(
        proposeForTopic(
          evidence: const TopicEvidence(
            nodeKey: 'k',
            title: 'লাভ-ক্ষতি',
            attempted: 20,
            correct: 19,
          ),
          current: SyllabusStatus.hidden,
        ),
        isNull,
      );
    });

    test('"whole subject done" leaves removed topics removed', () async {
      await SyllabusService.instance.removeTopic(db, nodeKey: profitKey);

      final loaded = await subject();
      for (final topic in loaded.topics) {
        if (topic.status == SyllabusStatus.hidden) continue;
        await SyllabusService.instance.setStatus(
          db,
          nodeKey: topic.nodeKey,
          status: SyllabusStatus.done,
        );
      }

      final after = (await subject()).topics.firstWhere(
        (t) => t.nodeKey == profitKey,
      );
      expect(after.status, SyllabusStatus.hidden);
    });
  });

  group('a whole track of hidden topics', () {
    test('reads as nought rather than finished', () async {
      await SyllabusService.instance.removeTopic(db, nodeKey: percentKey);
      await SyllabusService.instance.removeTopic(db, nodeKey: profitKey);

      final tally = tallySubject(await subject());
      // Nothing left to finish is not the same as having finished it.
      expect(tally.doneFraction, 0);
      expect(tally.totalTopics, 0);
      expect(tally.marksTotal, 20);
    });
  });
}
