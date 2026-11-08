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
  final seen = <String, int>{};
  for (int i = 0; i < existing.length; i++) {
    final key = _normalizeStem(existing[i].questionText);
    if (key.isNotEmpty) {
      seen[key] = i;
    }
  }

  final updatedExisting = List<QuizQuestion>.from(existing);
  final added = <QuizQuestion>[];
  int duplicates = 0;

  for (final question in fromPage) {
    final text = question.questionText.trim();
    if (text.isEmpty) {
      duplicates++;
      continue;
    }

    final key = _normalizeStem(text);
    if (seen.containsKey(key)) {
      duplicates++;
      final existingIdx = seen[key]!;
      final exQ = updatedExisting[existingIdx];
      // If the existing question had no valid answer or was a guess,
      // but the duplicate incoming question has a valid answer/explanation,
      // enrich the existing question with the new answer.
      if ((exQ.correctIndex < 0 || exQ.answerSource == AnswerSource.guess) &&
          question.correctIndex >= 0 &&
          question.answerSource != AnswerSource.guess) {
        updatedExisting[existingIdx] = exQ.copyWith(
          correctIndex: question.correctIndex,
          explanation: exQ.explanation.isNotEmpty
              ? exQ.explanation
              : question.explanation,
          answerSource: question.answerSource,
        );
      }
      continue;
    }

    seen[key] = updatedExisting.length + added.length;
    added.add(question);
  }

  return PageMerge(
    questions: [...updatedExisting, ...added],
    added: added.length,
    duplicates: duplicates,
  );
}

String _normalizeStem(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '';

  // Remove leading numbering like "১. ", "1)", "প্রশ্ন ১: " if followed by actual text
  final stripped = trimmed.replaceFirst(
    RegExp(r'^(?:(?:প্রশ্ন|Q)\s*)?[\d০-৯]+[\.\)\:\-\=\s]+\s*'),
    '',
  );

  final candidate = stripped.trim().isNotEmpty ? stripped.trim() : trimmed;
  return candidate.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
