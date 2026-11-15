import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:life_and_study_assistant/core/database/app_database.dart';

/// The Mistake Bank serves its own stored questions back as a drill. Before
/// this, finishing that drill wrote a *new* row per question, so the same
/// question got wrong twice appeared twice and the count climbed — and one
/// finally got right kept its old wrong row, so it could never leave the
/// bank by being learnt.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  const questionText =
      'বাংলাদেশের সংবিধানের কোন সংশোধনীর মাধ্যমে তত্ত্বাবধায়ক সরকার '
      'ব্যবস্থা বাতিল করা হয়েছিল?';

  DrillQuestionsCompanion answer({
    required bool correct,
    String text = questionText,
  }) {
    return DrillQuestionsCompanion.insert(
      subject: 'বাংলাদেশ বিষয়াবলি',
      topic: 'সংবিধান',
      questionText: text,
      optionsJson: '["ক","খ","গ","ঘ"]',
      correctIndex: 2,
      selectedIndex: correct ? 2 : 1,
      isCorrect: correct,
      explanation: const Value('পঞ্চদশ সংশোধনী।'),
    );
  }

  Future<int> saveSession(List<DrillQuestionsCompanion> questions) {
    final wrong = questions.where((q) => !q.isCorrect.value).length;
    return db.recordFullDrillSession(
      subject: 'বাংলাদেশ বিষয়াবলি',
      topic: 'সংবিধান',
      totalQuestions: questions.length,
      correctCount: questions.length - wrong,
      incorrectCount: wrong,
      scorePercentage: questions.isEmpty
          ? 0
          : ((questions.length - wrong) / questions.length) * 100,
      questions: questions,
    );
  }

  Future<List<DrillQuestion>> bank() => db.watchWrongDrillQuestions().first;

  test('getting the same question wrong twice keeps one row, not two', () async {
    await saveSession([answer(correct: false)]);
    expect((await bank()).length, 1);

    // Re-drill it from the Mistake Bank and get it wrong again.
    await saveSession([answer(correct: false)]);

    final rows = await bank();
    expect(rows.length, 1, reason: 'the question must not be duplicated');
    expect(rows.single.attemptCount, 2);
    expect(rows.single.wrongCount, 2);
  });

  test('the Mistake Bank count does not climb on a repeated mistake', () async {
    await saveSession([answer(correct: false)]);
    final before = (await db.getDrillStats())['active_wrong_count'] as int;

    await saveSession([answer(correct: false)]);
    await saveSession([answer(correct: false)]);

    final after = (await db.getDrillStats())['active_wrong_count'] as int;
    expect(after, before, reason: 'it is still one unlearnt question');
    expect(after, 1);
  });

  test('getting it right finally clears it out of the bank', () async {
    await saveSession([answer(correct: false)]);
    expect((await bank()).length, 1);

    await saveSession([answer(correct: true)]);

    expect(
      await bank(),
      isEmpty,
      reason: 'a mistake the user has learnt should leave the bank',
    );
  });

  test('accuracy still counts every answer given, not every question seen',
      () async {
    // Wrong, wrong, then right: one question, three answers, one of them good.
    await saveSession([answer(correct: false)]);
    await saveSession([answer(correct: false)]);
    await saveSession([answer(correct: true)]);

    final stats = await db.getDrillStats();
    expect(stats['total_answered'], 3);
    expect(stats['total_wrong'], 2);
    expect(stats['total_correct'], 1);
    expect(stats['accuracy_percentage'], closeTo(33.3, 0.1));
  });

  test('a question got wrong again comes back off the mastered list', () async {
    await saveSession([answer(correct: false)]);
    final row = (await bank()).single;

    await db.markQuestionMastered(row.id, true);
    expect(await bank(), isEmpty);

    // It was not as mastered as it looked.
    await saveSession([answer(correct: false)]);

    final rows = await bank();
    expect(rows.length, 1);
    expect(rows.single.isMastered, isFalse);
    expect(rows.single.id, row.id, reason: 'same row, not a new one');
  });

  test('marking it mastered is not undone by answering it right', () async {
    await saveSession([answer(correct: false)]);
    final row = (await bank()).single;
    await db.markQuestionMastered(row.id, true);

    await saveSession([answer(correct: true)]);

    final stored = await (db.select(
      db.drillQuestions,
    )..where((t) => t.id.equals(row.id))).getSingle();
    expect(stored.isMastered, isTrue);
  });

  test('different questions still get their own rows', () async {
    await saveSession([
      answer(correct: false),
      answer(correct: false, text: 'গণপরিষদের প্রথম অধিবেশন কবে বসে?'),
    ]);

    expect((await bank()).length, 2);
  });

  test('whitespace around the same question does not make it a new one',
      () async {
    await saveSession([answer(correct: false)]);
    await saveSession([answer(correct: false, text: '  $questionText  ')]);

    expect((await bank()).length, 1);
  });

  group('merging the duplicates already on a device', () {
    // What the schema 15 migration runs. The rows are inserted straight into
    // the table, the way the old append-only code wrote them.
    Future<void> insertRaw({
      required String text,
      required bool correct,
      bool mastered = false,
    }) {
      return db
          .into(db.drillQuestions)
          .insert(
            DrillQuestionsCompanion.insert(
              subject: 'বাংলাদেশ বিষয়াবলি',
              topic: 'সংবিধান',
              questionText: text,
              optionsJson: '["ক","খ","গ","ঘ"]',
              correctIndex: 2,
              selectedIndex: correct ? 2 : 1,
              isCorrect: correct,
              isMastered: Value(mastered),
            ),
          );
    }

    test('three copies of one question become one, with the totals kept',
        () async {
      await insertRaw(text: questionText, correct: false);
      await insertRaw(text: questionText, correct: false);
      await insertRaw(text: questionText, correct: false);

      await db.mergeDuplicateDrillQuestions();

      final rows = await db.select(db.drillQuestions).get();
      expect(rows.length, 1);
      expect(rows.single.attemptCount, 3);
      expect(rows.single.wrongCount, 3);
    });

    test('the newest attempt is the one that survives', () async {
      await insertRaw(text: questionText, correct: false);
      await insertRaw(text: questionText, correct: true);

      await db.mergeDuplicateDrillQuestions();

      final rows = await db.select(db.drillQuestions).get();
      expect(rows.length, 1);
      expect(rows.single.isCorrect, isTrue, reason: 'they learnt it in the end');
      expect(rows.single.attemptCount, 2);
      expect(rows.single.wrongCount, 1);
      expect(await bank(), isEmpty);
    });

    test('mastery marked on any copy survives the merge', () async {
      await insertRaw(text: questionText, correct: false, mastered: true);
      await insertRaw(text: questionText, correct: false);

      await db.mergeDuplicateDrillQuestions();

      final rows = await db.select(db.drillQuestions).get();
      expect(rows.length, 1);
      expect(rows.single.isMastered, isTrue);
    });

    test('questions that were never duplicated are left alone', () async {
      await insertRaw(text: questionText, correct: false);
      await insertRaw(text: 'গণপরিষদের প্রথম অধিবেশন কবে বসে?', correct: true);

      await db.mergeDuplicateDrillQuestions();

      final rows = await db.select(db.drillQuestions).get();
      expect(rows.length, 2);
      for (final r in rows) {
        expect(r.attemptCount, 1);
      }
    });
  });
}
