import '../../../core/services/ai/models/quiz_question.dart';

/// What a page added to an existing set contributes.
class PageMerge {
  final List<QuizQuestion> questions;
  final int added;
  final int duplicates;

  const PageMerge({
    required this.questions,
    required this.added,
    required this.duplicates,
  });
}

/// Adds a freshly read page to the questions already gathered.
///
/// A model test rarely fits on one page. Reading the second one used to
/// rebuild the list from that reply alone, so a fifty-question test came out
/// as whatever was on the last page photographed.
///
/// A page photographed twice is dropped rather than doubled: on a long test a
/// repeated question is hard to notice by eye, and it would be drilled and
/// scored twice.
PageMerge mergeScannedPage({
  required List<QuizQuestion> existing,
  required List<QuizQuestion> fromPage,
}) {
  final seen = existing.map((q) => q.questionText.trim()).toSet();
  final added = <QuizQuestion>[];

  for (final question in fromPage) {
    final text = question.questionText.trim();
    if (text.isEmpty || !seen.add(text)) continue;
    added.add(question);
  }

  return PageMerge(
    questions: [...existing, ...added],
    added: added.length,
    duplicates: fromPage.length - added.length,
  );
}
