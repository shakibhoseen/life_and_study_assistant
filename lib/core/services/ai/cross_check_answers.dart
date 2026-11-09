import '../../utils/bengali_math_sanitizer.dart';
import 'models/quiz_question.dart';
import 'question_text_parser.dart';

/// A question number reduced to just its digits, for matching one list against
/// another.
///
/// Measured: the full read of a page returned "১." with the printed full stop,
/// while the answers-only read is asked for "১০"-style numbers. Matching the
/// raw strings meant a single dot made every question look unmatched, and
/// every unmatched question has its answer cleared — a page of blanks caused
/// by punctuation rather than by any disagreement. Bengali digits are folded
/// to ASCII as well, so "১০" and "10" are the same question.
String normaliseQuestionNumber(String raw) {
  final digits = BengaliMathSanitizer.toEnglishDigits(raw);
  final buffer = StringBuffer();
  for (final unit in digits.codeUnits) {
    if (unit >= 0x30 && unit <= 0x39) buffer.writeCharCode(unit);
  }
  // Leading zeros are presentation, not identity: "০৭" and "৭" are question 7.
  final trimmed = buffer.toString().replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return trimmed;
}

/// One answer letter as a second reading of the page found it.
class PrintedAnswer {
  const PrintedAnswer({
    required this.printedNumber,
    required this.letter,
    this.sectionTitle,
  });

  final String printedNumber;
  final String letter;
  final String? sectionTitle;

  factory PrintedAnswer.fromJson(Map<String, dynamic> json) => PrintedAnswer(
    printedNumber: json['printed_number']?.toString().trim() ?? '',
    letter: json['printed_answer_letter']?.toString().trim() ?? '',
    sectionTitle: () {
      final raw = json['section_title']?.toString().trim() ?? '';
      return raw.isEmpty ? null : raw;
    }(),
  );
}

/// Holds the scanned answers up against a second reading of the same page, and
/// keeps only the ones both readings agree on.
///
/// This exists because of something measured rather than suspected: the same
/// page read twice came back with six different answers out of eighteen, and
/// both readings reported every one of them as read straight off the page,
/// with a specific letter and no hint of doubt. A model that takes খ for ঘ
/// does not know it has, so no field it fills in can catch it. Reading twice
/// and comparing is the only thing that can.
///
/// A disagreement is not resolved here. Neither reading has any claim to be
/// the right one, so the answer is cleared and the question is handed back to
/// the reader with both letters shown — which is cheap for them, since the
/// page is in front of them, and is what they asked for.
///
/// A question the second reading has nothing to say about is cleared too. That
/// is deliberately strict: silence is not agreement, and an answer nobody
/// checked is exactly what this is here to stop.
List<QuizQuestion> crossCheckAnswers(
  List<QuizQuestion> questions,
  List<PrintedAnswer> secondRead,
) {
  if (secondRead.isEmpty) return questions;

  // Keyed on the section as well as the number, because the number alone is
  // not unique: a page carrying the end of one test and the start of another
  // has two question ১৩s on it.
  String key(String? section, String number) =>
      '${section ?? ''}#${normaliseQuestionNumber(number)}';

  final byKey = <String, PrintedAnswer>{};
  final byNumber = <String, List<PrintedAnswer>>{};
  for (final answer in secondRead) {
    final number = normaliseQuestionNumber(answer.printedNumber);
    if (number.isEmpty || answer.letter.isEmpty) continue;
    byKey[key(answer.sectionTitle, answer.printedNumber)] = answer;
    byNumber.putIfAbsent(number, () => []).add(answer);
  }

  return [
    for (final question in questions)
      _checked(question, byKey, byNumber, key),
  ];
}

QuizQuestion _checked(
  QuizQuestion question,
  Map<String, PrintedAnswer> byKey,
  Map<String, List<PrintedAnswer>> byNumber,
  String Function(String?, String) key,
) {
  final number = normaliseQuestionNumber(question.printedNumber ?? '');
  if (number.isEmpty) return _unverified(question);

  // The section and number together first. Falling back to the number alone
  // is safe only where the page holds exactly one question with that number.
  var match = byKey[key(question.sectionTitle, question.printedNumber ?? '')];
  if (match == null) {
    final candidates = byNumber[number];
    if (candidates != null && candidates.length == 1) {
      match = candidates.first;
    }
  }
  if (match == null) return _unverified(question);

  final second = match.letter;
  final asIndex = QuestionTextParser.resolveOptionLetterToIndex(second);
  final agrees =
      asIndex >= 0 &&
      asIndex < question.options.length &&
      asIndex == question.correctIndex;

  if (agrees) return question.copyWith(secondReadLetter: second);

  return question.copyWith(
    secondReadLetter: second,
    correctIndex: -1,
    answerSource: AnswerSource.guess,
  );
}

/// Nothing to compare against, so the answer does not survive.
QuizQuestion _unverified(QuizQuestion question) {
  if (!question.hasAnswer) return question;
  return question.copyWith(
    correctIndex: -1,
    answerSource: AnswerSource.guess,
  );
}
