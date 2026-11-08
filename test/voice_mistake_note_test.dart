import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/tables/drill_questions_table.dart';
import 'package:life_and_study_assistant/core/services/ai/models/voice_mistake_result.dart';
import 'package:life_and_study_assistant/core/services/ai/voice_mistake_parser_service.dart';

/// A mistake dictated into the floating bubble is a note, not a drill.
///
/// It used to be written as both, which quietly made the app's own figures
/// wrong: a one-question session scored 0% for every note taken, and an
/// invented answer the user had never picked.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // A fresh database seeds starter review cards and weak topics. These
    // tests are about the rows the voice note itself writes.
    await db.delete(db.spacedReviewItems).go();
    await db.delete(db.weakTopics).go();
  });

  tearDown(() async {
    await db.close();
  });

  const spoken = VoiceMistakeResult(
    questionText: 'পদ্মা সেতুর দৈর্ঘ্য কত?',
    options: ['৫.৬ কিমি', '৬.১৫ কিমি', '৭.২ কিমি', '৮.০ কিমি'],
    correctIndex: 1,
    explanation: 'মূল সেতুর দৈর্ঘ্য ৬.১৫ কিলোমিটার।',
    subject: 'সাধারণ জ্ঞান',
    topic: 'বাংলাদেশ বিষয়াবলি',
    keyRule: 'পদ্মা সেতু ৬.১৫ কিমি।',
  );

  /// One question answered here, the ordinary way, through a drill.
  Future<void> sitADrill({required bool gotItRight}) {
    return db.recordFullDrillSession(
      subject: 'গণিত',
      topic: 'বীজগণিত',
      totalQuestions: 1,
      correctCount: gotItRight ? 1 : 0,
      incorrectCount: gotItRight ? 0 : 1,
      scorePercentage: gotItRight ? 100 : 0,
      questions: [
        DrillQuestionsCompanion.insert(
          subject: 'গণিত',
          topic: 'বীজগণিত',
          questionText: 'x + 2 = 5 হলে x = ?',
          optionsJson: jsonEncode(['1', '2', '3', '4']),
          correctIndex: 2,
          selectedIndex: gotItRight ? 2 : 0,
          isCorrect: gotItRight,
        ),
      ],
    );
  }

  Future<bool> dictate([VoiceMistakeResult result = spoken]) {
    return VoiceMistakeParserService.instance.saveVoiceMistakeToDatabase(
      db,
      result,
    );
  }

  test('a dictated mistake writes no drill session', () async {
    await dictate();

    expect(await db.select(db.drillRecords).get(), isEmpty);
    expect((await db.select(db.drillQuestions).get()).length, 1);
  });

  test('a dictated mistake records no answer, because none was given', () async {
    await dictate();

    final saved = (await db.select(db.drillQuestions).get()).single;
    expect(saved.selectedIndex, -1);
    expect(saved.isCorrect, isFalse);
    expect(saved.drillRecordId, isNull);
  });

  test('a dictated mistake carries the tag the statistics read', () async {
    await dictate();

    final saved = (await db.select(db.drillQuestions).get()).single;
    expect(saved.explanation.startsWith(voiceMistakeSourceTag), isTrue);
  });

  test('dictating a mistake does not drag the accuracy down', () async {
    await sitADrill(gotItRight: true);
    final before = await db.getDrillStats();
    expect(before['accuracy_percentage'], 100.0);

    await dictate();
    await dictate();
    await dictate();

    final after = await db.getDrillStats();
    expect(
      after['accuracy_percentage'],
      100.0,
      reason: 'notes are not attempts, so they cannot change the score',
    );
    expect(after['total_answered'], 1);
    expect(after['total_correct'], 1);
    expect(after['total_wrong'], 0);
  });

  test('dictating a mistake does not count as a drill taken', () async {
    await sitADrill(gotItRight: false);
    await dictate();
    await dictate();

    expect((await db.getDrillStats())['total_drills'], 1);
  });

  test('a dictated mistake still waits in the Mistake Bank', () async {
    await dictate();

    final stats = await db.getDrillStats();
    expect(
      stats['active_wrong_count'],
      1,
      reason: 'the whole point of the note is to practise it later',
    );
    expect((await db.watchWrongDrillQuestions().first).length, 1);
  });

  test('a real wrong answer is still counted against the accuracy', () async {
    await sitADrill(gotItRight: true);
    await sitADrill(gotItRight: false);

    final stats = await db.getDrillStats();
    expect(stats['total_answered'], 2);
    expect(stats['accuracy_percentage'], 50.0);
  });

  test('the same mistake dictated twice is kept once', () async {
    expect(await dictate(), isTrue);
    expect(
      await dictate(),
      isFalse,
      reason: 'the second telling is the same question, not a second one',
    );

    expect((await db.select(db.drillQuestions).get()).length, 1);
    expect((await db.select(db.spacedReviewItems).get()).length, 1);
  });

  test('a different mistake is still its own entry', () async {
    await dictate();
    await dictate(
      const VoiceMistakeResult(
        questionText: 'যমুনা সেতুর দৈর্ঘ্য কত?',
        options: ['৪.৮ কিমি', '৫.৬৩ কিমি', '৬.১ কিমি', '৭.০ কিমি'],
        correctIndex: 1,
        explanation: 'যমুনা সেতু ৪.৮ কিলোমিটার।',
        subject: 'সাধারণ জ্ঞান',
        topic: 'বাংলাদেশ বিষয়াবলি',
        keyRule: 'যমুনা সেতু ৪.৮ কিমি।',
      ),
    );

    expect((await db.select(db.drillQuestions).get()).length, 2);
  });

  test('a photographed mistake is left out of the score too', () async {
    await sitADrill(gotItRight: true);
    await VoiceMistakeParserService.instance.saveVoiceMistakeToDatabase(
      db,
      spoken,
      sourceTag: '[উৎস: LiveMCQ 📸]',
    );

    final stats = await db.getDrillStats();
    expect(
      stats['accuracy_percentage'],
      100.0,
      reason: 'a photographed question was not answered here either',
    );
    expect(stats['total_answered'], 1);
  });

  test('the schema is at the version whose migration cleans the old rows', () {
    expect(db.schemaVersion, 14);
  });
}
