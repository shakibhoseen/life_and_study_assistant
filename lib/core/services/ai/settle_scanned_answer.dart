import 'models/quiz_question.dart';
import 'question_text_parser.dart';

/// Decides what a scanned question's answer really is, once the model has had
/// its say.
///
/// Two things the model is not left to settle on its own.
///
/// **The letter.** In this print খ, ঘ and ব are easily taken for one another,
/// so the model reports the letter it saw as well as the index it made of it,
/// and the two are checked against each other here. A letter this app can
/// resolve wins, because it is what the book actually marked. A letter it
/// cannot resolve clears the answer instead of guessing which of two it was.
///
/// **The right to answer at all.** With [trustPrintedAnswersOnly] only an
/// answer the page printed survives; anything the model worked out itself is
/// cleared, so the reader is asked rather than told. These books print their
/// own answers and those are usually right — a model reasoning over the top of
/// them adds mistakes rather than removing any, and a wrong answer that looks
/// certain is worse than no answer at all.
QuizQuestion settleScannedAnswer(
  QuizQuestion question, {
  required bool trustPrintedAnswersOnly,
}) {
  var settled = question;

  final letter = question.printedAnswerLetter?.trim() ?? '';
  if (letter.isNotEmpty) {
    final fromLetter = QuestionTextParser.resolveOptionLetterToIndex(letter);
    if (fromLetter >= 0 && fromLetter < question.options.length) {
      settled = settled.copyWith(correctIndex: fromLetter);
    } else {
      // Something was printed there and neither the model nor this app can say
      // which letter it is. Saying so is the entire point of carrying the
      // letter across.
      settled = settled.copyWith(
        correctIndex: -1,
        answerSource: AnswerSource.guess,
      );
    }
  }

  if (trustPrintedAnswersOnly &&
      settled.answerSource != AnswerSource.answerKey) {
    settled = settled.copyWith(
      correctIndex: -1,
      answerSource: AnswerSource.guess,
    );
  }

  return settled;
}
