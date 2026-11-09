import '../../../core/services/ai/models/quiz_question.dart';

/// Whether two readings of the page disagreed about this question's answer.
///
/// Both letters have to be there to disagree. One read and no second opinion
/// is a different thing, and is counted as unchecked rather than as a clash.
bool answersDisagree(QuizQuestion question) {
  final first = question.printedAnswerLetter;
  final second = question.secondReadLetter;
  return first != null && second != null && first != second;
}

/// What a scanned set looks like at a glance.
///
/// The screen used to show only what the optional AI verification pass had
/// found, which meant a set nobody had run that pass over looked perfect: a
/// page where a third of the answers could not be read showed the same clean
/// face as one where every answer was certain. These are the scan's own
/// figures, available the moment the page comes back.
class ScanTally {
  const ScanTally({
    required this.total,
    required this.clean,
    required this.noAnswer,
    required this.disagreed,
    required this.unreadable,
  });

  /// How many questions are in the set.
  final int total;

  /// Readable, answered, and the answer came off the page — nothing to do.
  final int clean;

  /// No answer selected, whatever the reason.
  final int noAnswer;

  /// The two readings of the page named different letters. A subset of
  /// [noAnswer], since a clash clears the answer.
  final int disagreed;

  /// The print itself could not be read.
  final int unreadable;

  /// Whether anything at all wants looking at.
  bool get hasIssues => noAnswer > 0 || unreadable > 0;

  /// How many questions want the reader's eye, counting each one once.
  int get needingReview => total - clean;
}

/// Counts the problems in a scanned set.
ScanTally tallyScanIssues(List<QuizQuestion> questions) {
  var clean = 0;
  var noAnswer = 0;
  var disagreed = 0;
  var unreadable = 0;

  for (final question in questions) {
    if (!question.hasAnswer) noAnswer++;
    if (!question.legible) unreadable++;
    if (answersDisagree(question)) disagreed++;
    // Counted once, by the same rule the cards colour themselves with, so the
    // figures on the screen and the rings around the cards cannot disagree.
    if (!question.needsReview) clean++;
  }

  return ScanTally(
    total: questions.length,
    clean: clean,
    noAnswer: noAnswer,
    disagreed: disagreed,
    unreadable: unreadable,
  );
}
