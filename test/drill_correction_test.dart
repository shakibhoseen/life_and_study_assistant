import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/core/services/ai/quiz_batch_correction_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  final svc = QuizBatchCorrectionService.instance;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  // The real case: a drill on ক্ষুদ্র নৃগোষ্ঠী where the stored options do
  // not contain the correct answer at all.
  Future<DrillQuestion> seedBishu() async {
    final id = await db
        .into(db.drillQuestions)
        .insert(
          DrillQuestionsCompanion.insert(
            subject: 'বাংলাদেশ বিষয়াবলী',
            topic: 'ক্ষুদ্র নৃগোষ্ঠী',
            questionText:
                "বিখ্যাত 'বিষু' উৎসব কোন ক্ষুদ্র নৃগোষ্ঠীর সাথে জড়িত?",
            optionsJson: jsonEncode(['চাকমা', 'মারমা', 'রাখাইন', 'সাঁওতাল']),
            correctIndex: 0,
            selectedIndex: 0,
            isCorrect: true,
            explanation: const Value('চাকমাদের উৎসব বিষু।'),
          ),
        );
    return (db.select(
      db.drillQuestions,
    )..where((t) => t.id.equals(id))).getSingle();
  }

  QuestionCorrectionItem correction(Map<String, dynamic> json) =>
      QuestionCorrectionItem.tryFromJson(json, [
        const QuizQuestion(
          questionText: 'x',
          options: ['চাকমা', 'মারমা', 'রাখাইন', 'সাঁওতাল'],
          correctIndex: 0,
          explanation: '',
        ),
      ])!;

  group('Corrections reach drill questions, not just exams', () {
    test(
      'a new option set is written, with the answer that matches it',
      () async {
        final dq = await seedBishu();

        // What the external analysis asked for: add তঞ্চঙ্গ্যা and point at it.
        await svc.applyCorrectionsToMistakeQuestions(
          db,
          drillQuestions: [dq],
          corrections: [
            correction({
              'question_index': 0,
              'proposed_correct_index': 2,
              'is_delete': false,
              'new_question_text': '',
              'new_options': ['চাকমা', 'মারমা', 'তঞ্চঙ্গ্যা', 'ত্রিপুরা'],
              'reason': 'সঠিক উত্তর অপশনে ছিল না।',
            }),
          ],
        );

        final row = await (db.select(
          db.drillQuestions,
        )..where((t) => t.id.equals(dq.id))).getSingle();
        final options = (jsonDecode(row.optionsJson) as List).cast<String>();

        expect(options, contains('তঞ্চঙ্গ্যা'));
        expect(row.correctIndex, 2);
        // The index belongs to the NEW list. Applied against the old one it
        // would have pointed at রাখাইন.
        expect(options[row.correctIndex], 'তঞ্চঙ্গ্যা');
      },
    );

    test('a reworded question is written', () async {
      final dq = await seedBishu();

      await svc.applyCorrectionsToMistakeQuestions(
        db,
        drillQuestions: [dq],
        corrections: [
          correction({
            'question_index': 0,
            'is_delete': false,
            'new_question_text':
                'বাংলাদেশের কোন ক্ষুদ্র নৃগোষ্ঠীর বর্ষবরণ উৎসবের নাম বিষু?',
            'new_options': [],
            'reason': 'প্রশ্নের ভাষা স্পষ্ট করা হয়েছে।',
          }),
        ],
      );

      final row = await (db.select(
        db.drillQuestions,
      )..where((t) => t.id.equals(dq.id))).getSingle();

      expect(row.questionText, contains('বর্ষবরণ'));
    });

    test('the original is kept so the edit can be undone', () async {
      final dq = await seedBishu();

      await svc.applyCorrectionsToMistakeQuestions(
        db,
        drillQuestions: [dq],
        corrections: [
          correction({
            'question_index': 0,
            'proposed_correct_index': 2,
            'is_delete': false,
            'new_question_text': '',
            'new_options': ['চাকমা', 'মারমা', 'তঞ্চঙ্গ্যা', 'ত্রিপুরা'],
            'reason': 'সংশোধন।',
          }),
        ],
      );

      final row = await (db.select(
        db.drillQuestions,
      )..where((t) => t.id.equals(dq.id))).getSingle();

      expect(row.originalOptionsJson, contains('রাখাইন'));
      expect(row.originalCorrectIndex, 0);
      expect(row.correctedAt, isNotNull);
    });

    test('a correction carrying nothing leaves the row alone', () async {
      final dq = await seedBishu();

      await svc.applyCorrectionsToMistakeQuestions(
        db,
        drillQuestions: [dq],
        corrections: [
          correction({
            'question_index': 0,
            'is_delete': false,
            'new_question_text': '',
            'new_options': [],
            'reason': 'ঠিক আছে, রাখা যায়।',
          }),
        ],
      );

      final row = await (db.select(
        db.drillQuestions,
      )..where((t) => t.id.equals(dq.id))).getSingle();

      expect(row.correctedAt, isNull);
      expect(row.questionText, contains('বিখ্যাত'));
    });

    test('a wrong explanation is replaced on its own', () async {
      // The answer is right; only the reason printed beneath it is wrong.
      // Before new_explanation existed this case fell through entirely.
      final id = await db
          .into(db.drillQuestions)
          .insert(
            DrillQuestionsCompanion.insert(
              subject: 'গণিত',
              topic: 'একক',
              questionText: 'এক কিলোমিটারে কত মিটার?',
              optionsJson: jsonEncode(['১০০', '১০০০', '১০০০০', '১০']),
              correctIndex: 1,
              selectedIndex: 1,
              isCorrect: true,
              explanation: const Value('এক কিলোমিটার সমান ১০০ মিটার।'),
            ),
          );
      final dq = await (db.select(
        db.drillQuestions,
      )..where((t) => t.id.equals(id))).getSingle();

      await svc.applyCorrectionsToMistakeQuestions(
        db,
        drillQuestions: [dq],
        corrections: [
          QuestionCorrectionItem.tryFromJson(
            {
              'question_index': 0,
              'is_delete': false,
              'new_question_text': '',
              'new_options': [],
              'new_explanation': 'এক কিলোমিটার সমান ১০০০ মিটার।',
              'reason': 'ব্যাখ্যায় ভুল সংখ্যা ছিল।',
            },
            [
              const QuizQuestion(
                questionText: 'এক কিলোমিটারে কত মিটার?',
                options: ['১০০', '১০০০', '১০০০০', '১০'],
                correctIndex: 1,
                explanation: '',
              ),
            ],
          )!,
        ],
      );

      final row = await (db.select(
        db.drillQuestions,
      )..where((t) => t.id.equals(id))).getSingle();

      expect(row.explanation, 'এক কিলোমিটার সমান ১০০০ মিটার।');
      expect(row.correctIndex, 1, reason: 'the answer was already right');
      expect(row.originalExplanation, contains('১০০ মিটার'));
    });

    test('deletion still removes the question', () async {
      final dq = await seedBishu();

      await svc.applyCorrectionsToMistakeQuestions(
        db,
        drillQuestions: [dq],
        corrections: [
          correction({
            'question_index': 0,
            'is_delete': true,
            'new_question_text': '',
            'new_options': [],
            'reason': 'প্রশ্নটি ত্রুটিপূর্ণ।',
          }),
        ],
      );

      expect(await db.select(db.drillQuestions).get(), isEmpty);
    });
  });
}
