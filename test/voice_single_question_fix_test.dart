import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/core/services/ai/quiz_batch_correction_service.dart';

/// A spoken fix takes the offline path — no key needed, nothing sent anywhere.
/// It has to understand the question the way the user sees it on screen: by
/// its serial, by the id printed beside it, or, with one question in front of
/// them, by not naming it at all.
void main() {
  QuizQuestion q(String text, {int correct = 0}) => QuizQuestion(
    questionText: text,
    options: const ['ক-টা', 'খ-টা', 'গ-টা', 'ঘ-টা'],
    correctIndex: correct,
    explanation: '',
  );

  final service = QuizBatchCorrectionService.instance;

  Future<List<QuestionCorrectionItem>> parse(
    List<QuizQuestion> questions,
    String spoken, {
    List<int>? ids,
  }) {
    return service.parseCorrections(
      questions: questions,
      externalAnalysis: spoken,
      questionIds: ids,
    );
  }

  test('one question, and the fix does not name it', () async {
    final items = await parse([q('একটি প্রশ্ন', correct: 0)], 'উত্তর খ হবে');

    expect(items, hasLength(1));
    expect(items.first.questionIndex, 0);
    expect(items.first.proposedCorrectIndex, 1);
  });

  test('a bare letter is enough when there is only one', () async {
    final items = await parse([q('একটি প্রশ্ন', correct: 3)], 'গ');

    expect(items.single.proposedCorrectIndex, 2);
  });

  test('saying the answer it already has changes nothing', () async {
    final items = await parse([q('একটি প্রশ্ন', correct: 1)], 'উত্তর খ হবে');

    expect(items, isEmpty);
  });

  test('a bare letter is ignored when there is more than one question',
      () async {
    // With a list on screen, "খ" alone does not say which question, and
    // guessing the first one would quietly rewrite the wrong row.
    final items = await parse([q('এক'), q('দুই')], 'খ হবে');

    expect(items, isEmpty);
  });

  test('the serial the list prints still works', () async {
    final items = await parse([q('এক'), q('দুই'), q('তিন')], 'প্রশ্ন ৩ এ ঘ হবে');

    expect(items.single.questionIndex, 2);
    expect(items.single.proposedCorrectIndex, 3);
  });

  test('the printed id works when it cannot be a serial', () async {
    // The notebook shows [Q-180] beside a question that is fourth in the list.
    final items = await parse(
      [q('এক'), q('দুই'), q('তিন'), q('চার')],
      'প্রশ্ন ১৮০ এ খ হবে',
      ids: const [12, 44, 97, 180],
    );

    expect(items.single.questionIndex, 3);
    expect(items.single.proposedCorrectIndex, 1);
  });

  test('a number that is a serial stays a serial', () async {
    // Saying "তিন" about a visible list means the third one, even where some
    // other question happens to carry the id 3.
    final items = await parse(
      [q('এক'), q('দুই'), q('তিন')],
      'প্রশ্ন ৩ এ খ হবে',
      ids: const [3, 9, 11],
    );

    expect(items.single.questionIndex, 2);
  });

  test('a number that is neither is dropped', () async {
    final items = await parse(
      [q('এক'), q('দুই')],
      'প্রশ্ন ৫০০ এ খ হবে',
      ids: const [3, 9],
    );

    expect(items, isEmpty);
  });
}
