import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/features/quiz/domain/scan_review_tally.dart';

/// The figures the review screen shows at a glance. They have to be the scan's
/// own: a set nobody ran the AI verification over used to look perfect however
/// much of it could not be read.
void main() {
  QuizQuestion q({
    int correctIndex = 1,
    bool legible = true,
    AnswerSource source = AnswerSource.answerKey,
    String? letter,
    String? secondLetter,
  }) {
    return QuizQuestion(
      questionText: 'প্রশ্ন',
      options: const ['ক', 'খ', 'গ', 'ঘ'],
      correctIndex: correctIndex,
      explanation: '',
      legible: legible,
      answerSource: source,
      printedAnswerLetter: letter,
      secondReadLetter: secondLetter,
    );
  }

  group('answersDisagree', () {
    test('two different letters disagree', () {
      expect(answersDisagree(q(letter: 'ক', secondLetter: 'খ')), isTrue);
    });

    test('the same letter twice does not', () {
      expect(answersDisagree(q(letter: 'খ', secondLetter: 'খ')), isFalse);
    });

    test('one read and no second opinion is not a clash', () {
      // Unchecked and contradicted are different things, and lumping them
      // together would hide which one the reader is looking at.
      expect(answersDisagree(q(letter: 'খ')), isFalse);
      expect(answersDisagree(q(secondLetter: 'খ')), isFalse);
      expect(answersDisagree(q()), isFalse);
    });
  });

  group('tallyScanIssues', () {
    test('an empty set has nothing to report', () {
      final tally = tallyScanIssues(const []);

      expect(tally.total, 0);
      expect(tally.clean, 0);
      expect(tally.needingReview, 0);
      expect(tally.hasIssues, isFalse);
    });

    test('a clean question is counted clean and nothing else', () {
      final tally = tallyScanIssues([q()]);

      expect(tally.clean, 1);
      expect(tally.noAnswer, 0);
      expect(tally.unreadable, 0);
      expect(tally.disagreed, 0);
      expect(tally.needingReview, 0);
      expect(tally.hasIssues, isFalse);
    });

    test('a question with no answer is counted', () {
      final tally = tallyScanIssues([
        q(correctIndex: -1, source: AnswerSource.guess),
      ]);

      expect(tally.noAnswer, 1);
      expect(tally.clean, 0);
      expect(tally.hasIssues, isTrue);
    });

    test('a clash counts as a clash and as a missing answer', () {
      // This is the shape crossCheckAnswers leaves behind: the letters stay so
      // the reader can see both, and the answer is gone.
      final tally = tallyScanIssues([
        q(
          correctIndex: -1,
          source: AnswerSource.guess,
          letter: 'ক',
          secondLetter: 'খ',
        ),
      ]);

      expect(tally.disagreed, 1);
      expect(tally.noAnswer, 1);
      expect(
        tally.needingReview,
        1,
        reason: 'one question, however many ways it is wrong',
      );
    });

    test('unreadable print is counted', () {
      final tally = tallyScanIssues([q(legible: false)]);

      expect(tally.unreadable, 1);
      expect(tally.clean, 0);
    });

    test('a question wrong in two ways is still one question', () {
      final tally = tallyScanIssues([
        q(correctIndex: -1, legible: false, source: AnswerSource.guess),
      ]);

      expect(tally.noAnswer, 1);
      expect(tally.unreadable, 1);
      expect(tally.needingReview, 1);
    });

    test('a guessed answer is not clean even when everything reads', () {
      final tally = tallyScanIssues([q(source: AnswerSource.guess)]);

      expect(tally.clean, 0);
      expect(tally.needingReview, 1);
      expect(
        tally.hasIssues,
        isFalse,
        reason: 'nothing is missing or unreadable, it is merely unverified',
      );
    });

    test('a real page adds up', () {
      // Eighteen questions, six of them cleared by a disagreement — the shape
      // measured on the page this was built for.
      final questions = [
        for (var i = 0; i < 12; i++) q(letter: 'খ', secondLetter: 'খ'),
        for (var i = 0; i < 6; i++)
          q(
            correctIndex: -1,
            source: AnswerSource.guess,
            letter: 'ক',
            secondLetter: 'খ',
          ),
      ];

      final tally = tallyScanIssues(questions);

      expect(tally.total, 18);
      expect(tally.clean, 12);
      expect(tally.disagreed, 6);
      expect(tally.noAnswer, 6);
      expect(tally.needingReview, 6);
    });
  });
}
