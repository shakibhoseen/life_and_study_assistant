import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/data/confusable_pairs.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';

/// The two things the user keeps swapping.
///
/// Nothing new is recorded for this: every wrong answer already stored which
/// option was picked and which was right, and nobody had ever read the two
/// together. "কারকে দুর্বল" sends somebody to re-read a chapter; "অপাদান আর
/// অধিকরণ গুলিয়ে ফেলেন" is an afternoon on one distinction.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ConfusionEvidence e(String chosen, String correct, [String topic = 'কারক']) =>
      ConfusionEvidence(chosen: chosen, correct: correct, topic: topic);

  group('normalising an option', () {
    test('drops a leading marker', () {
      expect(normaliseOption('ক. অপাদান'), 'অপাদান');
      expect(normaliseOption('খ) অধিকরণ'), 'অধিকরণ');
      expect(normaliseOption('A. Noun'), 'Noun');
    });

    test('keeps a marker that is the whole answer', () {
      // "ক." is what the user picked, not a label on something else.
      expect(normaliseOption('ক.'), 'ক.');
    });

    test('collapses runs of space so one thing is one thing', () {
      expect(normaliseOption('অপাদান   কারক'), 'অপাদান কারক');
    });
  });

  group('finding pairs', () {
    test('a pair that recurs is reported, commonest first', () {
      final pairs = findConfusablePairs([
        e('অপাদান', 'অধিকরণ'),
        e('অধিকরণ', 'অপাদান'),
        e('করণ', 'সম্প্রদান'),
        e('সম্প্রদান', 'করণ'),
        e('অপাদান', 'অধিকরণ'),
      ]);

      expect(pairs.first.times, 3);
      expect({pairs.first.first, pairs.first.second}, {'অপাদান', 'অধিকরণ'});
      expect(pairs.length, 2);
    });

    test('direction does not split a pair in two', () {
      // The remedy — learn the difference — is the same either way round.
      final pairs = findConfusablePairs([
        e('bring', 'take'),
        e('take', 'bring'),
      ]);

      expect(pairs.length, 1);
      expect(pairs.single.times, 2);
    });

    test('one slip is not a habit', () {
      expect(findConfusablePairs([e('অপাদান', 'অধিকরণ')]), isEmpty);
    });

    test('markers do not make the same pair look like two', () {
      final pairs = findConfusablePairs([
        e('ক. অপাদান', 'খ. অধিকরণ'),
        e('অপাদান', 'অধিকরণ'),
      ]);

      expect(pairs.single.times, 2);
    });

    test('full-sentence options are not a pair', () {
      // Picking the wrong sentence is not a mix-up between two terms, and
      // reporting it as one buries the real pairs.
      final long = 'নিচের কোনটি বাংলাদেশের সংবিধানের মূলনীতির অন্তর্ভুক্ত নয় তা হলো';
      final other = 'উপরের কোনোটিই সঠিক নয় বলে বিবেচিত হবে এই প্রশ্নের ক্ষেত্রে';
      expect(findConfusablePairs([e(long, other), e(long, other)]), isEmpty);
    });

    test('an option swapped with itself is not a pair', () {
      expect(
        findConfusablePairs([e('অপাদান', 'অপাদান'), e('অপাদান', 'অপাদান')]),
        isEmpty,
      );
    });

    test('reports where the pair happens most', () {
      final pairs = findConfusablePairs([
        e('অপাদান', 'অধিকরণ', 'কারক ও বিভক্তি'),
        e('অপাদান', 'অধিকরণ', 'কারক ও বিভক্তি'),
        e('অপাদান', 'অধিকরণ', 'সমাস'),
      ]);

      expect(pairs.single.topic, 'কারক ও বিভক্তি');
    });

    test('the two are ordered the same way every time', () {
      final a = findConfusablePairs([e('খ', 'ক'), e('ক', 'খ')]);
      final b = findConfusablePairs([e('ক', 'খ'), e('খ', 'ক')]);

      expect(a.single.first, b.single.first);
      expect(a.single.second, b.single.second);
    });

    test('nothing at all is empty', () {
      expect(findConfusablePairs([]), isEmpty);
    });
  });

  group('through the database', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> wrong({
      required int selected,
      required int correct,
      List<String> options = const ['ক. অপাদান', 'খ. অধিকরণ', 'গ. করণ'],
      String topic = 'কারক',
      DateTime? at,
    }) async {
      await db
          .into(db.drillQuestions)
          .insert(
            DrillQuestionsCompanion.insert(
              subject: 'বাংলা',
              topic: topic,
              questionText: 'প্রশ্ন ${DateTime.now().microsecondsSinceEpoch}',
              optionsJson:
                  '[${options.map((o) => '"$o"').join(',')}]',
              correctIndex: correct,
              selectedIndex: selected,
              isCorrect: false,
              attemptedAt: Value(at ?? DateTime.now()),
            ),
          );
    }

    test('reads the pair out of what the drills already stored', () async {
      await wrong(selected: 0, correct: 1);
      await wrong(selected: 1, correct: 0);

      final pairs = await db.getConfusablePairs();
      expect(pairs.single.times, 2);
      expect({pairs.single.first, pairs.single.second}, {'অপাদান', 'অধিকরণ'});
    });

    test('a skipped question has no pair', () async {
      await wrong(selected: -1, correct: 1);
      await wrong(selected: -1, correct: 1);

      expect(await db.getConfusablePairs(), isEmpty);
    });

    test('a question with no answer key has no pair', () async {
      await wrong(selected: 0, correct: -1);
      await wrong(selected: 0, correct: -1);

      expect(await db.getConfusablePairs(), isEmpty);
    });

    test('an index past the options is skipped, not crashed on', () async {
      await wrong(selected: 9, correct: 1);
      await wrong(selected: 9, correct: 1);

      expect(await db.getConfusablePairs(), isEmpty);
    });

    test('old mistakes fall out of the window', () async {
      final old = DateTime.now().subtract(const Duration(days: 400));
      await wrong(selected: 0, correct: 1, at: old);
      await wrong(selected: 1, correct: 0, at: old);

      expect(await db.getConfusablePairs(withinDays: 180), isEmpty);
    });

    test('a correct answer never forms a pair', () async {
      await db
          .into(db.drillQuestions)
          .insert(
            DrillQuestionsCompanion.insert(
              subject: 'বাংলা',
              topic: 'কারক',
              questionText: 'ঠিক',
              optionsJson: '["ক. অপাদান","খ. অধিকরণ"]',
              correctIndex: 0,
              selectedIndex: 0,
              isCorrect: true,
            ),
          );

      expect(await db.getConfusablePairs(), isEmpty);
    });
  });
}
