import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/features/quiz/domain/merge_scanned_pages.dart';

QuizQuestion q(String text) => QuizQuestion(
  questionText: text,
  options: const ['ক', 'খ', 'গ', 'ঘ'],
  correctIndex: 0,
  explanation: '',
  subject: 'সাধারণ জ্ঞান',
);

void main() {
  test('the first page starts the set', () {
    final merge = mergeScannedPage(
      existing: const [],
      fromPage: [q('প্রশ্ন ১'), q('প্রশ্ন ২')],
    );

    expect(merge.questions.length, 2);
    expect(merge.added, 2);
    expect(merge.duplicates, 0);
  });

  test('a second page adds to the first rather than replacing it', () {
    final first = mergeScannedPage(
      existing: const [],
      fromPage: [q('প্রশ্ন ১'), q('প্রশ্ন ২')],
    );
    final second = mergeScannedPage(
      existing: first.questions,
      fromPage: [q('প্রশ্ন ৩'), q('প্রশ্ন ৪')],
    );

    expect(second.questions.map((x) => x.questionText), [
      'প্রশ্ন ১',
      'প্রশ্ন ২',
      'প্রশ্ন ৩',
      'প্রশ্ন ৪',
    ]);
    expect(second.added, 2);
  });

  test('the same page photographed twice is not doubled', () {
    final first = mergeScannedPage(
      existing: const [],
      fromPage: [q('প্রশ্ন ১'), q('প্রশ্ন ২')],
    );
    final again = mergeScannedPage(
      existing: first.questions,
      fromPage: [q('প্রশ্ন ১'), q('প্রশ্ন ২')],
    );

    expect(again.questions.length, 2);
    expect(again.added, 0);
    expect(again.duplicates, 2);
  });

  test('an overlapping page keeps only what is new', () {
    final first = mergeScannedPage(
      existing: const [],
      fromPage: [q('প্রশ্ন ১'), q('প্রশ্ন ২')],
    );
    final overlap = mergeScannedPage(
      existing: first.questions,
      fromPage: [q('প্রশ্ন ২'), q('প্রশ্ন ৩')],
    );

    expect(overlap.added, 1);
    expect(overlap.duplicates, 1);
    expect(overlap.questions.length, 3);
  });

  test('spacing around a question does not make it a new one', () {
    final first = mergeScannedPage(
      existing: const [],
      fromPage: [q('প্রশ্ন ১')],
    );
    final spaced = mergeScannedPage(
      existing: first.questions,
      fromPage: [q('  প্রশ্ন ১  ')],
    );

    expect(spaced.added, 0);
  });

  test('a page that read as blank adds nothing', () {
    final merge = mergeScannedPage(
      existing: [q('প্রশ্ন ১')],
      fromPage: [q('   '), q('')],
    );

    expect(merge.questions.length, 1);
    expect(merge.added, 0);
  });

  test('two blank-text questions on one page do not collide', () {
    // Both are dropped for being empty, not one kept and one called a
    // duplicate of the other.
    final merge = mergeScannedPage(
      existing: const [],
      fromPage: [q(''), q('')],
    );

    expect(merge.questions, isEmpty);
    expect(merge.duplicates, 2);
  });
}
