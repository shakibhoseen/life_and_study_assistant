import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/core/services/ai/quiz_batch_correction_service.dart';

List<QuizQuestion> quiz() => [
  const QuizQuestion(
    questionText: 'কল্যাণীর বাবার নাম কী?',
    options: ['শম্ভুনাথ সেন', 'মৃত্যুঞ্জয়', 'অনুপম', 'বিলাসী'],
    correctIndex: 0,
    explanation: '',
  ),
  const QuizQuestion(
    questionText: 'কপবসয় কোন রচনার?',
    options: ['ফরিদপুর', 'ঢাকা', 'বরিশাল', 'খুলনা'],
    correctIndex: 0,
    explanation: '',
    legible: false,
  ),
  const QuizQuestion(
    questionText: 'মৃত্যুঞ্জয় কোন বংশের ছেলে?',
    options: ['শম্ভুনাথ সেন', 'ব্রাহ্মণ', 'কায়স্থ', 'বৈদ্য'],
    correctIndex: 0,
    explanation: '',
  ),
];

QuestionCorrectionItem? parse(Map<String, dynamic> json) =>
    QuestionCorrectionItem.tryFromJson(json, quiz());

void main() {
  final svc = QuizBatchCorrectionService.instance;

  group('A correction must point at a real question', () {
    test('an index past the end is dropped, not redirected', () {
      // It used to fall back to 0, silently rewriting the first question.
      expect(parse({'question_index': 11, 'reason': 'x'}), isNull);
      expect(parse({'question_index': -1, 'reason': 'x'}), isNull);
      expect(parse({'reason': 'x'}), isNull);
    });

    test('a valid index is kept as given', () {
      expect(parse({'question_index': 2, 'reason': 'x'})!.questionIndex, 2);
    });
  });

  group('Rewriting the question itself', () {
    test('a garbled question can be replaced', () {
      final item = parse({
        'question_index': 1,
        'new_question_text': 'বঙ্গবন্ধুকে কোন জেলে স্থানান্তর করা হয়?',
        'new_options': ['ফরিদপুর', 'ঢাকা', 'বরিশাল', 'খুলনা'],
        'proposed_correct_index': 0,
        'reason': 'মূল প্রশ্ন বিকৃত ছিল',
      })!;

      expect(item.rewritesQuestion, isTrue);

      final updated = svc.applyCorrectionsToQuestions(
        questions: quiz(),
        corrections: [item],
      );

      expect(updated[1].questionText, contains('স্থানান্তর'));
      expect(updated[1].correctIndex, 0);
      // A rewritten row is readable again, and its answer is now sourced.
      expect(updated[1].legible, isTrue);
      expect(updated[1].answerSource, AnswerSource.solved);
    });

    test('only the options can be replaced', () {
      final item = parse({
        'question_index': 2,
        'new_options': ['ব্রাহ্মণ', 'কায়স্থ', 'বৈদ্য', 'শূদ্র'],
        'proposed_correct_index': 0,
        'reason': 'অপশনে সঠিক উত্তর ছিল না',
      })!;

      final updated = svc.applyCorrectionsToQuestions(
        questions: quiz(),
        corrections: [item],
      );

      expect(updated[2].options.first, 'ব্রাহ্মণ');
      expect(updated[2].questionText, 'মৃত্যুঞ্জয় কোন বংশের ছেলে?');
      expect(updated[2].correctIndex, 0);
    });

    test('a half-empty replacement option set is refused', () {
      final item = parse({
        'question_index': 2,
        'new_options': ['ব্রাহ্মণ', ''],
        'reason': 'x',
      })!;

      expect(item.newOptions, isNull);
    });

    test('moving only the answer still works', () {
      final item = parse({
        'question_index': 2,
        'proposed_correct_index': 1,
        'reason': 'সঠিক উত্তর ব্রাহ্মণ',
      })!;

      final updated = svc.applyCorrectionsToQuestions(
        questions: quiz(),
        corrections: [item],
      );

      expect(updated[2].correctIndex, 1);
      expect(updated[2].options, quiz()[2].options);
    });

    test('a correction carrying nothing changes nothing', () {
      final item = parse({'question_index': 2, 'reason': 'ঠিক আছে'})!;

      final updated = svc.applyCorrectionsToQuestions(
        questions: quiz(),
        corrections: [item],
      );

      expect(updated[2].questionText, quiz()[2].questionText);
      expect(updated[2].correctIndex, quiz()[2].correctIndex);
      expect(updated[2].explanation, quiz()[2].explanation);
    });

    test('an unselected correction is skipped', () {
      final item = parse({
        'question_index': 2,
        'proposed_correct_index': 1,
        'reason': 'x',
      })!..isSelected = false;

      final updated = svc.applyCorrectionsToQuestions(
        questions: quiz(),
        corrections: [item],
      );

      expect(updated[2].correctIndex, 0);
    });

    test('deletion removes the right row', () {
      final item = parse({
        'question_index': 1,
        'is_delete': true,
        'reason': 'প্রশ্নটি অর্থহীন',
      })!;

      final updated = svc.applyCorrectionsToQuestions(
        questions: quiz(),
        corrections: [item],
      );

      expect(updated, hasLength(2));
      expect(updated.any((q) => q.questionText.contains('কপবসয়')), isFalse);
    });

    test('several deletions do not shift each other', () {
      final items = [
        parse({'question_index': 0, 'is_delete': true, 'reason': 'x'})!,
        parse({'question_index': 2, 'is_delete': true, 'reason': 'x'})!,
      ];

      final updated = svc.applyCorrectionsToQuestions(
        questions: quiz(),
        corrections: items,
      );

      expect(updated, hasLength(1));
      expect(updated.single.questionText, contains('কপবসয়'));
    });
  });
}
