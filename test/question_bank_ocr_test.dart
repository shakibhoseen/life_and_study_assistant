import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/ai_media_limits.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';

Map<String, dynamic> raw({
  String question = 'মৃত্যুঞ্জয় কোন বংশের ছেলে?',
  List<String>? options,
  int correctIndex = 0,
  Object? legible,
  String source = 'answer_key',
}) => {
  'question': question,
  'options': options ?? ['ব্রাহ্মণ', 'কায়স্থ', 'বৈদ্য', 'শূদ্র'],
  'correct_index': correctIndex,
  'explanation': 'ব্যাখ্যা',
  'legible': ?legible,
  'answer_source': source,
};

void main() {
  group('Unreadable questions are not dressed up as readable', () {
    test('a clean question needs no review', () {
      final q = QuizQuestion.fromJson(raw());

      expect(q.legible, isTrue);
      expect(q.needsReview, isFalse);
      expect(q.answerSource, AnswerSource.answerKey);
    });

    test('a question the model could not read is flagged', () {
      final q = QuizQuestion.fromJson(raw(legible: false));

      expect(q.legible, isFalse);
      expect(q.needsReview, isTrue);
    });

    test('missing options are kept short, not padded with inventions', () {
      // This used to become Option A / Option B / Option C / Option D, which
      // made a failed read look like four real choices.
      final q = QuizQuestion.fromJson(raw(options: ['ব্রাহ্মণ', 'কায়স্থ']));

      expect(q.options, ['ব্রাহ্মণ', 'কায়স্থ']);
      expect(q.options.any((o) => o.startsWith('Option')), isFalse);
      expect(q.needsReview, isTrue);
    });

    test('blank options are dropped rather than counted', () {
      final q = QuizQuestion.fromJson(
        raw(options: ['ব্রাহ্মণ', '', 'বৈদ্য', '  ']),
      );

      expect(q.options, ['ব্রাহ্মণ', 'বৈদ্য']);
      expect(q.needsReview, isTrue);
    });

    test('an empty question text is not legible', () {
      expect(QuizQuestion.fromJson(raw(question: '   ')).needsReview, isTrue);
    });

    test('an answer index outside the options is flagged', () {
      final q = QuizQuestion.fromJson(raw(correctIndex: 7));

      expect(q.correctIndex, 0);
      expect(q.needsReview, isTrue);
    });

    test('a guessed answer is flagged even when the text was readable', () {
      final q = QuizQuestion.fromJson(raw(source: 'guess'));

      expect(q.legible, isTrue);
      expect(q.needsReview, isTrue);
      expect(q.answerSource.isDependable, isFalse);
    });

    test('only an answer read off the page counts as dependable', () {
      expect(AnswerSource.answerKey.isDependable, isTrue);
      expect(AnswerSource.solved.isDependable, isFalse);
      expect(AnswerSource.guess.isDependable, isFalse);
    });

    test('an unknown source is treated as a guess', () {
      expect(AnswerSource.parse(null), AnswerSource.guess);
      expect(AnswerSource.parse('something'), AnswerSource.guess);
    });

    test('the flags survive storage', () {
      final original = QuizQuestion.fromJson(
        raw(legible: false, source: 'solved'),
      );
      final restored = QuizQuestion.fromJson(original.toJson());

      expect(restored.legible, isFalse);
      expect(restored.answerSource, AnswerSource.solved);
    });
  });

  group('Capture detail', () {
    test('the high preset is the one sized for a dense page', () {
      // A question bank page is small Bengali print across a whole page.
      expect(CaptureDetail.high.dimension, 1280);
      expect(
        CaptureDetail.high.dimension,
        greaterThan(CaptureDetail.standard.dimension),
      );
    });
  });
}
