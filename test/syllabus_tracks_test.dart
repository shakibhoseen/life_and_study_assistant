import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/data/syllabus_coverage.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/tables/syllabus_progress_table.dart';
import 'package:life_and_study_assistant/core/services/syllabus/syllabus_draft_service.dart';
import 'package:life_and_study_assistant/core/services/syllabus/syllabus_service.dart';

/// Exams of the user's own.
///
/// The map shipped with two tracks and no way to add a third, which is fine
/// for a BCS candidate and useless for anyone sitting প্রধান শিক্ষক or NTRCA.
/// What these check is mostly the seam: a track the user made has to survive
/// the seed that rebuilds the bundled ones on every launch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  const bundled = SyllabusTrack(
    trackKey: 'primary',
    trackName: 'প্রাথমিক সহকারী শিক্ষক',
    totalMarks: 40,
    note: 'প্রচলিত মানবণ্টন',
    subjects: [
      SyllabusTrackSubject(
        name: 'বাংলা',
        marks: 20,
        aliases: [],
        topics: [
          SyllabusTrackTopic(title: 'সমাস', weight: 1),
          SyllabusTrackTopic(title: 'কারক ও বিভক্তি', weight: 1),
        ],
      ),
      SyllabusTrackSubject(
        name: 'গণিত',
        marks: 20,
        aliases: [],
        topics: [SyllabusTrackTopic(title: 'শতকরা', weight: 1)],
      ),
    ],
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await SyllabusService.instance.seed(db, tracks: const [bundled]);
  });
  tearDown(() => db.close());

  Future<void> reseed() =>
      SyllabusService.instance.seed(db, tracks: const [bundled]);

  group('bundled tracks become rows', () {
    test('seeding writes the track with its name and note', () async {
      final row = await SyllabusService.instance.trackByKey(db, 'primary');

      expect(row, isNotNull);
      expect(row!.name, 'প্রাথমিক সহকারী শিক্ষক');
      expect(row.note, 'প্রচলিত মানবণ্টন');
      expect(row.isCustom, isFalse);
    });

    test('seeding twice does not duplicate the row', () async {
      await reseed();
      expect((await SyllabusService.instance.tracks(db)).length, 1);
    });

    test('a bundled track cannot be deleted', () async {
      expect(
        await SyllabusService.instance.deleteTrack(db, trackKey: 'primary'),
        isFalse,
      );
      expect(await SyllabusService.instance.trackByKey(db, 'primary'), isNotNull);
    });

    test('its subjects cannot be removed', () async {
      // The exam's own mark distribution is not the user's to edit, and the
      // seed would rebuild it anyway.
      expect(
        await SyllabusService.instance.removeSubject(
          db,
          nodeKey: subjectNodeKey('primary', 'বাংলা'),
        ),
        isFalse,
      );
    });
  });

  group('creating', () {
    test('an empty track appears beside the bundled ones', () async {
      final key = await SyllabusService.instance.createTrack(
        db,
        name: 'প্রধান শিক্ষক',
      );

      expect(key, isNotNull);
      final tracks = await SyllabusService.instance.tracks(db);
      expect(tracks.map((t) => t.name), contains('প্রধান শিক্ষক'));
      // Bundled first, the user's after.
      expect(tracks.first.trackKey, 'primary');
    });

    test('it survives a re-seed', () async {
      final key = await SyllabusService.instance.createTrack(
        db,
        name: 'প্রধান শিক্ষক',
      );
      await reseed();

      expect(await SyllabusService.instance.trackByKey(db, key!), isNotNull);
    });

    test('a duplicate name is refused', () async {
      await SyllabusService.instance.createTrack(db, name: 'প্রধান শিক্ষক');
      expect(
        await SyllabusService.instance.createTrack(db, name: 'প্রধান শিক্ষক'),
        isNull,
      );
    });

    test('an empty name is refused', () async {
      expect(
        await SyllabusService.instance.createTrack(db, name: '  '),
        isNull,
      );
    });

    test('the key does not come from the name, so renaming is safe', () async {
      final key = await SyllabusService.instance.createTrack(
        db,
        name: 'প্রধান শিক্ষক',
      );
      await SyllabusService.instance.addSubject(
        db,
        trackKey: key!,
        name: 'বাংলা',
        marks: 25,
      );

      await SyllabusService.instance.renameTrack(
        db,
        trackKey: key,
        name: 'সহকারী প্রধান শিক্ষক',
      );

      // The syllabus is still attached to the renamed exam.
      final subjects = await SyllabusService.instance.loadCoverage(db, key);
      expect(subjects.single.name, 'বাংলা');
      expect(
        (await SyllabusService.instance.trackByKey(db, key))!.name,
        'সহকারী প্রধান শিক্ষক',
      );
    });
  });

  group('copying', () {
    test('brings the subjects and topics across', () async {
      final key = await SyllabusService.instance.copyTrack(
        db,
        sourceTrackKey: 'primary',
        name: 'প্রধান শিক্ষক',
      );

      final subjects = await SyllabusService.instance.loadCoverage(db, key!);
      expect(subjects.map((s) => s.name), ['বাংলা', 'গণিত']);
      expect(subjects.first.marks, 20);
      expect(subjects.first.topics.map((t) => t.title), [
        'সমাস',
        'কারক ও বিভক্তি',
      ]);
    });

    test('does not bring the ticks across', () async {
      await SyllabusService.instance.setStatus(
        db,
        nodeKey: topicNodeKey('primary', 'বাংলা', 'সমাস'),
        status: SyllabusStatus.done,
      );

      final key = await SyllabusService.instance.copyTrack(
        db,
        sourceTrackKey: 'primary',
        name: 'প্রধান শিক্ষক',
      );

      // What the user covered for one exam is a claim about that syllabus.
      final tally = tallyTrack(
        await SyllabusService.instance.loadCoverage(db, key!),
      );
      expect(tally.doneFraction, 0);
      // And the source is untouched.
      final source = tallyTrack(
        await SyllabusService.instance.loadCoverage(db, 'primary'),
      );
      expect(source.doneTopics, 1);
    });

    test('leaves out a topic the user had removed from the source', () async {
      await SyllabusService.instance.removeTopic(
        db,
        nodeKey: topicNodeKey('primary', 'বাংলা', 'সমাস'),
      );

      final key = await SyllabusService.instance.copyTrack(
        db,
        sourceTrackKey: 'primary',
        name: 'প্রধান শিক্ষক',
      );

      final subjects = await SyllabusService.instance.loadCoverage(db, key!);
      expect(subjects.first.topics.map((t) => t.title), ['কারক ও বিভক্তি']);
    });

    test('the copy is independent of the original', () async {
      final key = await SyllabusService.instance.copyTrack(
        db,
        sourceTrackKey: 'primary',
        name: 'প্রধান শিক্ষক',
      );

      final copied = await SyllabusService.instance.loadCoverage(db, key!);
      await SyllabusService.instance.setStatus(
        db,
        nodeKey: copied.first.topics.first.nodeKey,
        status: SyllabusStatus.done,
      );

      final source = tallyTrack(
        await SyllabusService.instance.loadCoverage(db, 'primary'),
      );
      expect(source.doneTopics, 0);
    });
  });

  group('subjects in a track of your own', () {
    late String key;

    setUp(() async {
      key = (await SyllabusService.instance.createTrack(
        db,
        name: 'প্রধান শিক্ষক',
      ))!;
    });

    test('can be added with their marks', () async {
      await SyllabusService.instance.addSubject(
        db,
        trackKey: key,
        name: 'বাংলা',
        marks: 25,
      );
      await SyllabusService.instance.addSubject(
        db,
        trackKey: key,
        name: 'গণিত',
        marks: 15,
      );

      final tally = tallyTrack(
        await SyllabusService.instance.loadCoverage(db, key),
      );
      expect(tally.marksTotal, 40);
    });

    test('a duplicate name is refused', () async {
      await SyllabusService.instance.addSubject(
        db,
        trackKey: key,
        name: 'বাংলা',
        marks: 25,
      );
      expect(
        await SyllabusService.instance.addSubject(
          db,
          trackKey: key,
          name: 'বাংলা',
          marks: 10,
        ),
        isNull,
      );
    });

    test('marks can be corrected afterwards', () async {
      final subjectKey = await SyllabusService.instance.addSubject(
        db,
        trackKey: key,
        name: 'বাংলা',
        marks: 25,
      );

      await SyllabusService.instance.editSubject(
        db,
        nodeKey: subjectKey!,
        marks: 30,
      );

      final subjects = await SyllabusService.instance.loadCoverage(db, key);
      expect(subjects.single.marks, 30);
    });

    test('removing one takes its topics with it', () async {
      final subjectKey = await SyllabusService.instance.addSubject(
        db,
        trackKey: key,
        name: 'বাংলা',
        marks: 25,
      );
      final topicKey = await SyllabusService.instance.addCustomTopic(
        db,
        subjectNodeKey: subjectKey!,
        title: 'সমাস',
      );
      await SyllabusService.instance.setStatus(
        db,
        nodeKey: topicKey!,
        status: SyllabusStatus.done,
      );

      expect(
        await SyllabusService.instance.removeSubject(db, nodeKey: subjectKey),
        isTrue,
      );

      expect(await SyllabusService.instance.loadCoverage(db, key), isEmpty);
      // The progress row goes too, or it would outlive its node.
      expect(await db.select(db.syllabusProgress).get(), isEmpty);
    });
  });

  group('deleting a track of your own', () {
    test('takes its syllabus and progress with it', () async {
      final key = await SyllabusService.instance.copyTrack(
        db,
        sourceTrackKey: 'primary',
        name: 'প্রধান শিক্ষক',
      );
      final subjects = await SyllabusService.instance.loadCoverage(db, key!);
      await SyllabusService.instance.setStatus(
        db,
        nodeKey: subjects.first.topics.first.nodeKey,
        status: SyllabusStatus.done,
      );

      expect(
        await SyllabusService.instance.deleteTrack(db, trackKey: key),
        isTrue,
      );

      expect(await SyllabusService.instance.trackByKey(db, key), isNull);
      expect(await SyllabusService.instance.loadCoverage(db, key), isEmpty);
      expect(await db.select(db.syllabusProgress).get(), isEmpty);
    });

    test('leaves the bundled track alone', () async {
      final key = await SyllabusService.instance.copyTrack(
        db,
        sourceTrackKey: 'primary',
        name: 'প্রধান শিক্ষক',
      );
      await SyllabusService.instance.deleteTrack(db, trackKey: key!);

      final subjects = await SyllabusService.instance.loadCoverage(
        db,
        'primary',
      );
      expect(subjects.length, 2);
    });
  });

  group('parsing an AI draft', () {
    test('reads a well-formed reply', () {
      final track = SyllabusDraftService.parseDraft('''
{
  "trackName": "প্রধান শিক্ষক",
  "totalMarks": 100,
  "subjects": [
    {"name": "বাংলা", "marks": 25,
     "topics": [{"title": "সমাস", "weight": 3}]}
  ]
}
''', fallbackName: 'যা হোক');

      expect(track, isNotNull);
      expect(track!.trackName, 'প্রধান শিক্ষক');
      expect(track.subjects.single.marks, 25);
      expect(track.subjects.single.topics.single.weight, 3);
    });

    test('survives markdown fences', () {
      final track = SyllabusDraftService.parseDraft('''
```json
{"trackName": "NTRCA", "subjects": [
  {"name": "গণিত", "marks": 25, "topics": [{"title": "শতকরা", "weight": 2}]}
]}
```
''', fallbackName: 'যা হোক');

      expect(track, isNotNull);
      expect(track!.subjects.single.name, 'গণিত');
    });

    test('accepts a bare array of subjects', () {
      final track = SyllabusDraftService.parseDraft(
        '[{"name": "বাংলা", "marks": 25, '
        '"topics": [{"title": "সমাস", "weight": 1}]}]',
        fallbackName: 'প্রধান শিক্ষক',
      );

      expect(track, isNotNull);
      expect(track!.trackName, 'প্রধান শিক্ষক');
    });

    test('every draft carries the warning in its note', () {
      final track = SyllabusDraftService.parseDraft(
        '{"trackName": "X", "subjects": [{"name": "বাংলা", "marks": 25, '
        '"topics": [{"title": "সমাস"}]}]}',
        fallbackName: 'যা হোক',
      );

      // The caveat has to travel with the data, not just live in the dialog.
      expect(track!.note, SyllabusDraftService.draftNote);
    });

    test('drops a subject with no topics rather than making an empty one', () {
      final track = SyllabusDraftService.parseDraft(
        '{"subjects": ['
        '{"name": "বাংলা", "marks": 25, "topics": []},'
        '{"name": "গণিত", "marks": 25, "topics": [{"title": "শতকরা"}]}'
        ']}',
        fallbackName: 'যা হোক',
      );

      expect(track!.subjects.map((s) => s.name), ['গণিত']);
    });

    test('returns null on rubbish rather than an empty track', () {
      expect(
        SyllabusDraftService.parseDraft('দুঃখিত, আমি পারছি না।',
            fallbackName: 'X'),
        isNull,
      );
      expect(
        SyllabusDraftService.parseDraft('{"subjects": []}', fallbackName: 'X'),
        isNull,
      );
    });
  });
}
