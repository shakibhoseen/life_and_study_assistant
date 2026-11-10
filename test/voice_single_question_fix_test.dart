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

  _doubtTests();

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

/// Said out loud, a doubt is more common than a correction — "এই প্রশ্নে ভুল
/// আছে", "বই দেখে নিতে হবে". None of it names an answer, and all of it used to
/// vanish without trace.
void _doubtTests() {
  QuizQuestion q(String text, {int correct = 0, String explanation = ''}) =>
      QuizQuestion(
        questionText: text,
        options: const ['ক-টা', 'খ-টা', 'গ-টা', 'ঘ-টা'],
        correctIndex: correct,
        explanation: explanation,
      );

  Future<List<QuestionCorrectionItem>> parse(
    List<QuizQuestion> questions,
    String spoken, {
    List<int>? ids,
  }) {
    return QuizBatchCorrectionService.instance.parseCorrections(
      questions: questions,
      externalAnalysis: spoken,
      questionIds: ids,
    );
  }

  group('a doubt spoken about one question', () {
    test('marks it without touching the answer', () async {
      final items = await parse(
        [q('একটি প্রশ্ন', correct: 2, explanation: 'পুরোনো ব্যাখ্যা')],
        'এই প্রশ্নে ভুল আছে',
      );

      final item = items.single;
      expect(item.proposedCorrectIndex, isNull);
      expect(item.isDelete, isFalse);
      expect(item.newExplanation, contains('পুরোনো ব্যাখ্যা'));
      expect(item.newExplanation, contains('একাধিক উত্তর সম্ভব'));
      // What was actually said is kept, so the mark can be read back.
      expect(item.newExplanation, contains('এই প্রশ্নে ভুল আছে'));
    });

    test('asking for a check is a different mark from calling it wrong',
        () async {
      final items = await parse(
        [q('একটি প্রশ্ন')],
        'এটা নিশ্চিত না, বই দেখে নিতে হবে',
      );

      expect(items.single.newExplanation, contains('উৎস যাচাই দরকার'));
    });

    test('a stated answer in the same breath still wins', () async {
      // "এই প্রশ্নটা ঠিক নেই, গ হবে" is a correction, not a doubt.
      final items = await parse(
        [q('একটি প্রশ্ন', correct: 0)],
        'এই প্রশ্নটা ঠিক নেই। গ হবে',
      );

      expect(items.single.proposedCorrectIndex, 2);
    });

    test('nothing is deleted on a doubt', () async {
      final items = await parse([q('একটি প্রশ্ন')], 'প্রশ্নটা সংশোধন করতে হবে');

      expect(items.single.isDelete, isFalse);
    });
  });

  group('a doubt spoken over a list', () {
    test('the question has to be named', () async {
      final items = await parse([q('এক'), q('দুই')], 'এই প্রশ্নে ভুল আছে');

      // Marking the wrong row is worse than marking none.
      expect(items, isEmpty);
    });

    test('a serial names it', () async {
      final items = await parse(
        [q('এক'), q('দুই'), q('তিন')],
        'প্রশ্ন ২ এ ভুল আছে, যাচাই করতে হবে',
      );

      expect(items.single.questionIndex, 1);
      expect(items.single.proposedCorrectIndex, isNull);
    });

    test('the printed id names it too', () async {
      final items = await parse(
        [q('এক'), q('দুই')],
        'প্রশ্ন ১৮০ ঠিক নেই',
        ids: const [44, 180],
      );

      expect(items.single.questionIndex, 1);
    });

    test('an ordinary sentence raises no doubt', () async {
      final items = await parse([q('এক')], 'এই প্রশ্নটা ভালো হয়েছে');

      expect(items, isEmpty);
    });

    test('the same mark is not stacked twice', () async {
      final items = await parse(
        [q('এক', explanation: 'ব্যাখ্যা\n⚠️ একাধিক উত্তর সম্ভব: ভুল আছে')],
        'ভুল আছে',
      );

      expect(items, isEmpty);
    });
  });
}
