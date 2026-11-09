import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/cross_check_answers.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';

/// Two reads of one real page disagreed on six answers out of eighteen, and
/// both reads reported every one of them as read straight off the page. These
/// cover what happens to the six.
void main() {
  QuizQuestion asked({
    required String number,
    required int correctIndex,
    String? letter,
    String? section,
  }) {
    return QuizQuestion(
      questionText: 'প্রশ্ন $number',
      options: const ['ক-অপশন', 'খ-অপশন', 'গ-অপশন', 'ঘ-অপশন'],
      correctIndex: correctIndex,
      explanation: '',
      answerSource: AnswerSource.answerKey,
      printedAnswerLetter: letter,
      printedNumber: number,
      sectionTitle: section,
    );
  }

  PrintedAnswer read(String number, String letter, {String? section}) =>
      PrintedAnswer(
        printedNumber: number,
        letter: letter,
        sectionTitle: section,
      );

  test('the two reads agreeing keeps the answer', () {
    final out = crossCheckAnswers(
      [asked(number: '১', correctIndex: 1, letter: 'খ')],
      [read('১', 'খ')],
    );

    expect(out.single.correctIndex, 1);
    expect(out.single.answerSource, AnswerSource.answerKey);
    expect(out.single.secondReadLetter, 'খ');
    expect(out.single.needsReview, isFalse);
  });

  test('the two reads disagreeing clears it and keeps both letters', () {
    // Question ২ on the measured page: খ one time, ক the other.
    final out = crossCheckAnswers(
      [asked(number: '২', correctIndex: 0, letter: 'ক')],
      [read('২', 'খ')],
    );

    expect(out.single.correctIndex, -1);
    expect(out.single.answerSource, AnswerSource.guess);
    expect(out.single.printedAnswerLetter, 'ক');
    expect(out.single.secondReadLetter, 'খ');
    expect(out.single.needsReview, isTrue);
  });

  test('neither reading is allowed to win a disagreement', () {
    // Whichever way round they come, the answer goes. Picking one would be
    // guessing with extra steps.
    const index = {'ক': 0, 'খ': 1, 'গ': 2, 'ঘ': 3};
    for (final pair in [
      ['ক', 'খ'],
      ['খ', 'ক'],
    ]) {
      final out = crossCheckAnswers(
        [
          asked(
            number: '২',
            // The first read's index has to match its own letter, or the
            // fixture is testing something that cannot happen.
            correctIndex: index[pair[0]]!,
            letter: pair[0],
          ),
        ],
        [read('২', pair[1])],
      );
      expect(out.single.hasAnswer, isFalse, reason: pair.join(' vs '));
    }
  });

  test('a question the second read says nothing about is cleared', () {
    final out = crossCheckAnswers(
      [asked(number: '৭', correctIndex: 3, letter: 'ঘ')],
      [read('৯', 'ক')],
    );

    expect(
      out.single.correctIndex,
      -1,
      reason: 'silence is not agreement',
    );
  });

  test('a question that had no answer anyway is left as it was', () {
    final out = crossCheckAnswers(
      [asked(number: '৭', correctIndex: -1)],
      [read('৯', 'ক')],
    );

    expect(out.single.correctIndex, -1);
  });

  test('two question ১৩s on one page are told apart by section', () {
    // The measured page really does carry two: one in the tail of the previous
    // test, one in the bank section. Matching on the number alone would cross
    // the answers over.
    final out = crossCheckAnswers(
      [
        asked(number: '১৩', correctIndex: 0, letter: 'ক'),
        asked(
          number: '১৩',
          correctIndex: 0,
          letter: 'ক',
          section: 'ব্যাংক নিয়োগ পরীক্ষা',
        ),
      ],
      [
        read('১৩', 'ক'),
        read('১৩', 'ঘ', section: 'ব্যাংক নিয়োগ পরীক্ষা'),
      ],
    );

    expect(out.first.correctIndex, 0, reason: 'the first one agreed');
    expect(out.last.correctIndex, -1, reason: 'the bank one did not');
    expect(out.last.secondReadLetter, 'ঘ');
  });

  test('an unreadable letter from the second read counts as a disagreement', () {
    final out = crossCheckAnswers(
      [asked(number: '৪', correctIndex: 1, letter: 'খ')],
      [read('৪', 'ব')],
    );

    expect(out.single.correctIndex, -1);
    expect(out.single.secondReadLetter, 'ব');
  });

  test('no second read at all leaves everything untouched', () {
    // Not checked is not the same as checked and disagreed. A network fault
    // must not empty the page the user just paid to scan.
    final questions = [asked(number: '১', correctIndex: 1, letter: 'খ')];
    final out = crossCheckAnswers(questions, const []);

    expect(out.single.correctIndex, 1);
    expect(out.single.answerSource, AnswerSource.answerKey);
  });

  test('a question with no printed number cannot be matched, so it clears', () {
    const q = QuizQuestion(
      questionText: 'নম্বরহীন প্রশ্ন',
      options: ['ক', 'খ', 'গ', 'ঘ'],
      correctIndex: 2,
      explanation: '',
      answerSource: AnswerSource.answerKey,
    );

    final out = crossCheckAnswers([q], [read('১', 'ক')]);

    expect(out.single.correctIndex, -1);
  });
}
