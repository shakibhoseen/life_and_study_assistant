/// Turning a reference table into questions.
///
/// The useful part is where the wrong options come from: the other rows of
/// the same table. A table of length units already holds everything someone
/// might confuse ১ মাইল with — ১ গজ, ১ ইঞ্চি, ১ ফার্লং — so the distractors
/// are not invented, they are the real confusions sitting one line away.
/// That is also why this needs no model, no key and no network: the table
/// has already done the hard part.
///
/// For a two-column table the question is "১ মাইল = কত?". For a wider one it
/// names the column instead — "Present — Perfect কোনটি?" — which generalises
/// a tense chart or a units table without either becoming nonsense.
library;

import 'dart:math';

import '../services/ai/models/quiz_question.dart';

/// A row as the generator sees it.
typedef DrillSourceRow = ({List<String> cells, String note});

/// Fewest options a question is worth asking with.
///
/// Two is a coin toss and teaches nothing. A table too small or too
/// repetitive to produce three plausible wrong answers produces no question
/// at all, which is the honest outcome.
const int tableDrillMinOptions = 3;

/// Builds questions from one table.
///
/// [random] is taken rather than made so a test can pin the shuffle; in the
/// app it is a fresh one, because the same table should not give the same
/// drill twice in a row.
List<QuizQuestion> buildDrillFromTable({
  required String sheetTitle,
  required String subject,
  required List<String> columns,
  required List<DrillSourceRow> rows,
  int limit = 10,
  int optionCount = 4,
  Random? random,
}) {
  if (columns.length < 2 || rows.length < tableDrillMinOptions) return const [];

  final rng = random ?? Random();
  final questions = <QuizQuestion>[];

  // Every (row, column) pair that could be asked about, then shuffled, so a
  // long table does not always drill its first ten rows.
  final candidates = <({int row, int column})>[];
  for (var r = 0; r < rows.length; r++) {
    for (var c = 1; c < columns.length; c++) {
      candidates.add((row: r, column: c));
    }
  }
  candidates.shuffle(rng);

  for (final candidate in candidates) {
    if (questions.length >= limit) break;

    final cells = rows[candidate.row].cells;
    if (candidate.column >= cells.length) continue;

    final prompt = cells.isEmpty ? '' : cells.first.trim();
    final answer = cells[candidate.column].trim();
    if (prompt.isEmpty || answer.isEmpty) continue;

    // Wrong options from the same column of other rows. Deduplicated against
    // the answer and each other: a table that repeats a value would
    // otherwise offer the right answer twice.
    final distractors = <String>{};
    for (var r = 0; r < rows.length; r++) {
      if (r == candidate.row) continue;
      final other = rows[r].cells;
      if (candidate.column >= other.length) continue;
      final value = other[candidate.column].trim();
      if (value.isEmpty || value == answer) continue;
      distractors.add(value);
    }
    if (distractors.length < tableDrillMinOptions - 1) continue;

    final picked = distractors.toList()..shuffle(rng);
    final options = [answer, ...picked.take(optionCount - 1)]..shuffle(rng);

    final note = rows[candidate.row].note.trim();
    questions.add(
      QuizQuestion(
        questionText: columns.length == 2
            ? '$prompt = কত?'
            : '$prompt — ${columns[candidate.column].trim()} কোনটি?',
        options: options,
        correctIndex: options.indexOf(answer),
        explanation: note.isEmpty
            ? 'টেবিল: $sheetTitle'
            : '$note\n(টেবিল: $sheetTitle)',
        subject: subject,
      ),
    );
  }

  return questions;
}
