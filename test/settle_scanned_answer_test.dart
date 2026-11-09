import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/core/services/ai/settle_scanned_answer.dart';

/// These books print their own answers, and those are usually right. The model
/// reads them; it does not get to improve on them, and where it cannot read
/// one it says so instead of picking the likelier of two letters.
void main() {
  _noAnswerIsNeverAnAnswer();

  QuizQuestion scanned({
    int correctIndex = 1,
    String? letter,
    AnswerSource source = AnswerSource.answerKey,
    List<String>? options,
  }) {
    return QuizQuestion(
      questionText: 'ATM-এর পূর্ণরূপ কী?',
      options: options ?? const ['ক-অপশন', 'খ-অপশন', 'গ-অপশন', 'ঘ-অপশন'],
      correctIndex: correctIndex,
      explanation: '',
      answerSource: source,
      printedAnswerLetter: letter,
    );
  }

  group('the printed letter decides', () {
    test('a letter the app can read sets the answer', () {
      final settled = settleScannedAnswer(
        scanned(correctIndex: 0, letter: 'ঘ'),
        trustPrintedAnswersOnly: true,
      );

      expect(settled.correctIndex, 3);
      expect(settled.answerSource, AnswerSource.answerKey);
    });

    test('a letter nobody can read leaves no answer', () {
      // "ব" is what খ and ঘ turn into in this print. Neither the model nor
      // this app can say which it was, so neither of them chooses.
      final settled = settleScannedAnswer(
        scanned(correctIndex: 1, letter: 'ব'),
        trustPrintedAnswersOnly: true,
      );

      expect(settled.correctIndex, -1);
      expect(settled.answerSource, AnswerSource.guess);
      expect(settled.needsReview, isTrue);
    });

    test('the letter read is kept, so the reader can see the misread', () {
      final settled = settleScannedAnswer(
        scanned(letter: 'ব'),
        trustPrintedAnswersOnly: true,
      );

      expect(settled.printedAnswerLetter, 'ব');
    });

    test('a letter pointing past the options leaves no answer', () {
      final settled = settleScannedAnswer(
        scanned(letter: 'ঘ', options: const ['হ্যাঁ', 'না']),
        trustPrintedAnswersOnly: true,
      );

      expect(settled.correctIndex, -1);
      expect(settled.answerSource, AnswerSource.guess);
    });

    test('English letters work the same way', () {
      final settled = settleScannedAnswer(
        scanned(correctIndex: 0, letter: 'C'),
        trustPrintedAnswersOnly: true,
      );

      expect(settled.correctIndex, 2);
    });
  });

  group('who is allowed to answer', () {
    test('an answer off the page is kept', () {
      final settled = settleScannedAnswer(
        scanned(correctIndex: 2, source: AnswerSource.answerKey),
        trustPrintedAnswersOnly: true,
      );

      expect(settled.correctIndex, 2);
      expect(settled.answerSource.isDependable, isTrue);
    });

    test('an answer the model worked out is cleared', () {
      final settled = settleScannedAnswer(
        scanned(correctIndex: 2, source: AnswerSource.solved),
        trustPrintedAnswersOnly: true,
      );

      expect(settled.correctIndex, -1);
      expect(settled.answerSource, AnswerSource.guess);
    });

    test('and is kept when the user asked for it', () {
      final settled = settleScannedAnswer(
        scanned(correctIndex: 2, source: AnswerSource.solved),
        trustPrintedAnswersOnly: false,
      );

      expect(settled.correctIndex, 2);
      expect(settled.answerSource, AnswerSource.solved);
    });

    test('a guess is cleared either way', () {
      for (final trust in [true, false]) {
        final settled = settleScannedAnswer(
          scanned(correctIndex: 2, source: AnswerSource.guess),
          trustPrintedAnswersOnly: trust,
        );
        expect(settled.needsReview, isTrue, reason: 'trust: $trust');
      }
    });
  });

  test('the section a question came from survives', () {
    const q = QuizQuestion(
      questionText: 'PDA কী?',
      options: ['ক', 'খ', 'গ', 'ঘ'],
      correctIndex: 1,
      explanation: '',
      answerSource: AnswerSource.answerKey,
      sectionTitle: 'ব্যাংক নিয়োগ পরীক্ষা',
      sourceExam: 'BSC (SO Cancelled): 18',
      printedNumber: '৩',
    );

    final settled = settleScannedAnswer(q, trustPrintedAnswersOnly: true);

    expect(settled.sectionTitle, 'ব্যাংক নিয়োগ পরীক্ষা');
    expect(settled.sourceExam, 'BSC (SO Cancelled): 18');
    expect(settled.printedNumber, '৩');
  });

  test('the new fields survive storage', () {
    const q = QuizQuestion(
      questionText: 'Analog signal is measured in?',
      options: ['Volt', 'Hertz', 'Digits', 'Watts'],
      correctIndex: 1,
      explanation: '',
      answerSource: AnswerSource.answerKey,
      printedAnswerLetter: 'খ',
      sectionTitle: 'ব্যাংক নিয়োগ পরীক্ষা',
      sourceExam: 'Rupali Bank (ANE): 21',
      printedNumber: '২',
    );

    final back = QuizQuestion.fromJson(q.toJson());

    expect(back.printedAnswerLetter, 'খ');
    expect(back.sectionTitle, 'ব্যাংক নিয়োগ পরীক্ষা');
    expect(back.sourceExam, 'Rupali Bank (ANE): 21');
    expect(back.printedNumber, '২');
  });
}

/// A question with no answer is the normal case now, so nothing may read a
/// missing answer as an answer. These cover the shapes that used to.
void _noAnswerIsNeverAnAnswer() {
  group('a missing answer is never treated as one', () {
    const unanswered = QuizQuestion(
      questionText: 'কোনটি সঠিক?',
      options: ['ক', 'খ', 'গ', 'ঘ'],
      correctIndex: -1,
      explanation: '',
      answerSource: AnswerSource.guess,
    );

    test('skipping a question with no key is not correct', () {
      // -1 equals -1, which is how a skipped question with no answer key used
      // to come out right. Four places in the drill screen compared the two
      // indices straight, and the database regraded corrections the same way.
      expect(unanswered.isCorrectChoice(-1), isFalse);
    });

    test('nor is any option, since there is nothing to match', () {
      for (var i = 0; i < unanswered.options.length; i++) {
        expect(unanswered.isCorrectChoice(i), isFalse, reason: 'option $i');
      }
    });

    test('an answer out of step with the options is not correct either', () {
      const broken = QuizQuestion(
        questionText: 'হ্যাঁ না?',
        options: ['হ্যাঁ', 'না'],
        correctIndex: 3,
        explanation: '',
      );

      expect(broken.hasAnswer, isFalse);
      expect(broken.isCorrectChoice(3), isFalse);
    });

    test('a real answer still scores', () {
      const answered = QuizQuestion(
        questionText: 'কোনটি সঠিক?',
        options: ['ক', 'খ', 'গ', 'ঘ'],
        correctIndex: 2,
        explanation: '',
        answerSource: AnswerSource.answerKey,
      );

      expect(answered.isCorrectChoice(2), isTrue);
      expect(answered.isCorrectChoice(1), isFalse);
      expect(answered.isCorrectChoice(-1), isFalse);
    });

    test('reading the answer off an unanswered question is safe', () {
      // Every screen guards this, and the guard is what keeps -1 from
      // reaching the list. Checked here so a new caller has a precedent.
      final answer = unanswered.hasAnswer
          ? unanswered.options[unanswered.correctIndex]
          : null;
      expect(answer, isNull);
    });
  });
}
