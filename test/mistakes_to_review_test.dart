import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';

/// Getting a question wrong should bring it back. That loop is the point of
/// the app, and it used to be closed one question at a time by hand.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  DrillQuestion wrong({
    String text = 'তিব্বতের মানস সরোবর থেকে উৎপন্ন নদী কোনটি?',
    int correctIndex = 0,
    String explanation = 'ব্রহ্মপুত্র মানস সরোবর থেকে উৎপন্ন।',
    List<String> options = const ['ব্রহ্মপুত্র', 'পদ্মা', 'মেঘনা', 'যমুনা'],
  }) => DrillQuestion(
    id: 1,
    subject: 'বাংলাদেশ বিষয়াবলী',
    topic: 'নদ-নদী',
    questionText: text,
    optionsJson: jsonEncode(options),
    correctIndex: correctIndex,
    selectedIndex: 1,
    isCorrect: false,
    explanation: explanation,
    isMastered: false,
    attemptedAt: DateTime.now(),
  );

  // The database seeds a starter deck on creation, so these look at what
  // changed rather than at the whole table.
  Future<List<SpacedReviewItem>> cards() =>
      db.select(db.spacedReviewItems).get();

  Future<SpacedReviewItem?> cardTitled(String title) async =>
      (await cards()).where((c) => c.title == title).firstOrNull;

  test('a wrong answer becomes a card due tomorrow', () async {
    final added = await db.addMistakesToReview([wrong()]);

    expect(added, 1);
    final saved = (await cardTitled(
      'তিব্বতের মানস সরোবর থেকে উৎপন্ন নদী কোনটি?',
    ))!;
    expect(saved.title, contains('মানস সরোবর'));
    // The right answer leads, with the explanation under it.
    expect(saved.keyRule, startsWith('ব্রহ্মপুত্র'));
    expect(saved.keyRule, contains('উৎপন্ন'));
    expect(saved.intervalDays, 1);
  });

  test('a question already in the deck is not added twice', () async {
    final before = (await cards()).length;
    await db.addMistakesToReview([wrong()]);
    final again = await db.addMistakesToReview([wrong()]);

    expect(again, 0);
    expect((await cards()).length, before + 1);
  });

  test('a whole drill goes in at once', () async {
    final before = (await cards()).length;
    final added = await db.addMistakesToReview([
      wrong(text: 'প্রশ্ন ১'),
      wrong(text: 'প্রশ্ন ২'),
      wrong(text: 'প্রশ্ন ৩'),
    ]);

    expect(added, 3);
    expect((await cards()).length, before + 3);
  });

  test('a question with no explanation still makes a usable card', () async {
    await db.addMistakesToReview([wrong(explanation: '')]);

    final saved = (await cardTitled(
      'তিব্বতের মানস সরোবর থেকে উৎপন্ন নদী কোনটি?',
    ))!;
    expect(saved.keyRule, 'ব্রহ্মপুত্র');
  });

  test(
    'a question whose answer cannot be read is skipped, not half saved',
    () async {
      final added = await db.addMistakesToReview([
        wrong(correctIndex: 9),
        wrong(text: '  '),
      ]);

      expect(added, 0);
      expect(
        await cardTitled('তিব্বতের মানস সরোবর থেকে উৎপন্ন নদী কোনটি?'),
        isNull,
      );
    },
  );

  test('a skipped question goes in too', () async {
    // "I did not know this" is the clearest case for seeing it again, even
    // though it does not count against the drill's score.
    final skipped = DrillQuestion(
      id: 2,
      subject: 'বাংলা',
      topic: 'সমাস',
      questionText: 'দ্বিগু সমাস কাকে বলে?',
      optionsJson: '["সংখ্যাবাচক","কর্মধারয়","তৎপুরুষ","বহুব্রীহি"]',
      correctIndex: 0,
      selectedIndex: -1,
      isCorrect: false,
      explanation: '',
      isMastered: false,
      attemptedAt: DateTime.now(),
    );

    expect(await db.addMistakesToReview([skipped]), 1);
    expect(await cardTitled('দ্বিগু সমাস কাকে বলে?'), isNotNull);
  });

  test('nothing wrong means nothing added', () async {
    expect(await db.addMistakesToReview([]), 0);
  });
}
