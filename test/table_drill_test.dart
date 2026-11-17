import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/data/table_drill.dart';

/// Questions built out of a reference table.
///
/// The point is where the wrong options come from: the other rows of the
/// same table. A length table already holds everything ১ মাইল might be
/// confused with, so the distractors are the real confusions rather than
/// invented ones — which is also why this needs no model and no network.
void main() {
  DrillSourceRow row(List<String> cells, [String note = '']) =>
      (cells: cells, note: note);

  final length = [
    row(['১ মাইল', '১.৬১ কিলোমিটার'], 'মনে রাখুন: মাইল বড়'),
    row(['১ গজ', '৩ ফুট']),
    row(['১ ইঞ্চি', '২.৫৪ সেন্টিমিটার']),
    row(['১ ফার্লং', '২২০ গজ']),
    row(['১ হাত', '১৮ ইঞ্চি']),
  ];

  group('two columns', () {
    test('asks about the first cell and answers with the second', () {
      final questions = buildDrillFromTable(
        sheetTitle: 'দৈর্ঘ্যের একক',
        subject: 'গাণিতিক যুক্তি',
        columns: const ['একক', 'সমান'],
        rows: length,
        random: Random(1),
      );

      expect(questions, isNotEmpty);
      final q = questions.first;
      expect(q.questionText, endsWith('= কত?'));
      expect(q.options.length, 4);
      expect(q.correctIndex, inInclusiveRange(0, 3));
    });

    test('the wrong options come from the same table', () {
      final questions = buildDrillFromTable(
        sheetTitle: 'দৈর্ঘ্যের একক',
        subject: 'গাণিতিক যুক্তি',
        columns: const ['একক', 'সমান'],
        rows: length,
        random: Random(7),
      );

      final answers = length.map((r) => r.cells[1]).toSet();
      for (final q in questions) {
        for (final option in q.options) {
          expect(answers, contains(option));
        }
      }
    });

    test('the right answer is in there exactly once', () {
      final questions = buildDrillFromTable(
        sheetTitle: 'দৈর্ঘ্যের একক',
        subject: 'গাণিতিক যুক্তি',
        columns: const ['একক', 'সমান'],
        rows: length,
        random: Random(3),
      );

      for (final q in questions) {
        final answer = q.options[q.correctIndex];
        expect(q.options.where((o) => o == answer).length, 1);
        expect(q.options.toSet().length, q.options.length);
      }
    });

    test('the row note becomes the explanation', () {
      final questions = buildDrillFromTable(
        sheetTitle: 'দৈর্ঘ্যের একক',
        subject: 'গাণিতিক যুক্তি',
        columns: const ['একক', 'সমান'],
        rows: [length.first, ...length.skip(1)],
        limit: 50,
        random: Random(5),
      );

      final mile = questions.firstWhere(
        (q) => q.questionText.startsWith('১ মাইল'),
      );
      expect(mile.explanation, contains('মনে রাখুন'));
      expect(mile.explanation, contains('দৈর্ঘ্যের একক'));
    });
  });

  group('three or more columns', () {
    final tense = [
      row(['Present', 'V1', 'have + V3']),
      row(['Past', 'V2', 'had + V3']),
      row(['Future', 'shall + V1', 'shall have + V3']),
      // Not named after a column: the assertion below works out which
      // column a question is about by looking at its text.
      row(['Continuous', 'is + V-ing', 'has been + V-ing']),
    ];

    test('names the column being asked about', () {
      final questions = buildDrillFromTable(
        sheetTitle: 'Tense',
        subject: 'English',
        columns: const ['Tense', 'Indefinite', 'Perfect'],
        rows: tense,
        limit: 50,
        random: Random(2),
      );

      expect(questions, isNotEmpty);
      for (final q in questions) {
        expect(q.questionText, contains('—'));
        expect(q.questionText, endsWith('কোনটি?'));
      }
    });

    test('distractors stay inside their own column', () {
      final questions = buildDrillFromTable(
        sheetTitle: 'Tense',
        subject: 'English',
        columns: const ['Tense', 'Indefinite', 'Perfect'],
        rows: tense,
        limit: 50,
        random: Random(11),
      );

      final indefinite = tense.map((r) => r.cells[1]).toSet();
      final perfect = tense.map((r) => r.cells[2]).toSet();

      for (final q in questions) {
        // A question about the Perfect column must never offer an
        // Indefinite form it could not possibly be.
        final column = q.questionText.contains('Perfect') ? perfect : indefinite;
        for (final option in q.options) {
          expect(column, contains(option));
        }
      }
    });
  });

  group('when it should say nothing', () {
    test('a table too small for three plausible options', () {
      // Two is a coin toss and teaches nothing.
      final questions = buildDrillFromTable(
        sheetTitle: 'ছোট',
        subject: 'গণিত',
        columns: const ['ক', 'খ'],
        rows: [row(['এক', '১']), row(['দুই', '২'])],
        random: Random(1),
      );

      expect(questions, isEmpty);
    });

    test('a column where every row says the same thing', () {
      final questions = buildDrillFromTable(
        sheetTitle: 'একই',
        subject: 'গণিত',
        columns: const ['ক', 'খ'],
        rows: [
          row(['এক', 'একই']),
          row(['দুই', 'একই']),
          row(['তিন', 'একই']),
          row(['চার', 'একই']),
        ],
        random: Random(1),
      );

      // No distractor differs from the answer, so there is no question.
      expect(questions, isEmpty);
    });

    test('rows with an empty cell are skipped, not asked blank', () {
      final questions = buildDrillFromTable(
        sheetTitle: 'ফাঁকা',
        subject: 'গণিত',
        columns: const ['ক', 'খ'],
        rows: [
          row(['এক', '']),
          row(['', '২']),
          row(['তিন', '৩']),
          row(['চার', '৪']),
          row(['পাঁচ', '৫']),
        ],
        limit: 50,
        random: Random(4),
      );

      for (final q in questions) {
        expect(q.questionText.trim(), isNot('= কত?'));
        expect(q.options.every((o) => o.trim().isNotEmpty), isTrue);
      }
    });

    test('a ragged row shorter than the column asked about', () {
      final questions = buildDrillFromTable(
        sheetTitle: 'ছেঁড়া',
        subject: 'গণিত',
        columns: const ['ক', 'খ', 'গ'],
        rows: [
          row(['এক', '১']),
          row(['দুই', '২', 'খ২']),
          row(['তিন', '৩', 'গ৩']),
          row(['চার', '৪', 'ঘ৪']),
        ],
        limit: 50,
        random: Random(6),
      );

      // The short row simply does not produce a third-column question.
      expect(
        questions.every((q) => q.options.every((o) => o.isNotEmpty)),
        isTrue,
      );
    });

    test('one column is not a table', () {
      expect(
        buildDrillFromTable(
          sheetTitle: 'এক কলাম',
          subject: 'গণিত',
          columns: const ['ক'],
          rows: [row(['এক']), row(['দুই']), row(['তিন'])],
          random: Random(1),
        ),
        isEmpty,
      );
    });
  });

  test('the limit is respected', () {
    final questions = buildDrillFromTable(
      sheetTitle: 'দৈর্ঘ্যের একক',
      subject: 'গাণিতিক যুক্তি',
      columns: const ['একক', 'সমান'],
      rows: length,
      limit: 2,
      random: Random(1),
    );

    expect(questions.length, 2);
  });

  test('the same seed gives the same drill', () {
    List<String> run() => buildDrillFromTable(
      sheetTitle: 'দৈর্ঘ্যের একক',
      subject: 'গাণিতিক যুক্তি',
      columns: const ['একক', 'সমান'],
      rows: length,
      random: Random(42),
    ).map((q) => '${q.questionText}|${q.options.join(",")}').toList();

    expect(run(), run());
  });
}
