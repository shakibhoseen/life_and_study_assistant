import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/core/services/ai/quiz_batch_correction_service.dart';
import 'package:life_and_study_assistant/core/utils/embedded_json.dart';

/// A real reply, copied out of ChatGPT's own window, did not decode: every
/// line ended in a backslash and every indent was an `&#x20;`. It was the
/// right answer, rejected for its wrapping. One of its twenty-one entries
/// also carried the serial number where the printed id belonged, which would
/// have pointed an explanation about the internet's inventors at a question
/// on Garo dance.
void main() {
  final service = QuizBatchCorrectionService.instance;

  QuizQuestion q(
    String text, {
    int correct = 0,
    List<String>? options,
  }) {
    return QuizQuestion(
      questionText: text,
      options: options ?? const ['ক-টা', 'খ-টা', 'গ-টা', 'ঘ-টা'],
      correctIndex: correct,
      explanation: '',
    );
  }

  group('a reply copied out of a chat window', () {
    const mangled = r'''[\
&#x20; {\
&#x20;   "question_id": 180,\
&#x20;   "status": "ambiguous",\
&#x20;   "proposed_correct_index": -1,\
&#x20;   "reason": "খ ও গ অপশনের অর্থ একই"\
&#x20; }\
]''';

    test('decodes once the rendering is taken off', () {
      expect(extractFirstJson(mangled), isNotNull);
      // The raw paste does not decode; that was the whole failure.
      expect(
        () => extractFirstJson(cleanPastedJson(mangled)),
        returnsNormally,
      );
      expect(cleanPastedJson(mangled), isNot(contains('&#x20;')));
      expect(cleanPastedJson(mangled), isNot(contains(r'\')));
    });

    test('and is read without a model', () async {
      final items = await service.parseCorrections(
        questions: [q('সামান্তরিকের কর্ণদ্বয় পরস্পরকে কী করে?', correct: 2)],
        externalAnalysis: mangled,
        questionIds: const [180],
      );

      expect(items, hasLength(1));
      expect(service.lastParseWasFree, isTrue);
      // Ambiguous: marked, answer untouched.
      expect(items.single.proposedCorrectIndex, isNull);
    });

    test('Bengali inside the strings survives intact', () {
      const text = r'''[{"question_id": 1, "new_explanation": "রিজেন্সি যুগের রচনা, ভিক্টোরীয় নয়।"}]''';

      expect(
        cleanPastedJson(text),
        contains('রিজেন্সি যুগের রচনা, ভিক্টোরীয় নয়।'),
      );
    });
  });

  _rewordingTests();

  group('an entry aimed at the wrong question', () {
    final questions = [
      q('গারো জনগোষ্ঠীর ঐতিহ্যবাহী সামাজিক নৃত্য কোনটি?'),
      q('ইন্টারনেটের জনক কে?'),
    ];
    const ids = [53, 101];

    test('is dropped when the echoed words do not match', () async {
      // Exactly what happened: the id says 53 (Garo dance), the words say
      // something else entirely.
      final items = await service.parseCorrections(
        questions: questions,
        externalAnalysis:
            '[{"question_id": 53, "question_snippet": "ইন্টারনেটের জনক কে", '
            '"status": "incorrect", "new_explanation": "ভিন্ট সার্ফ ও বব কান", '
            '"reason": "নাম ভুল লেখা"}]',
        questionIds: ids,
      );

      expect(items, isEmpty);
    });

    test('is kept when they do match', () async {
      final items = await service.parseCorrections(
        questions: questions,
        externalAnalysis:
            '[{"question_id": 53, "question_snippet": "গারো জনগোষ্ঠীর ঐতিহ্যবাহী", '
            '"status": "incorrect", "proposed_correct_index": 1, '
            '"reason": "নৃত্যের নাম আলাদা"}]',
        questionIds: ids,
      );

      expect(items.single.questionIndex, 0);
    });

    test('no echo at all is still accepted', () async {
      // Most replies will not carry one, and refusing those would break every
      // correction that worked before.
      final items = await service.parseCorrections(
        questions: questions,
        externalAnalysis:
            '[{"question_id": 101, "status": "incorrect", '
            '"proposed_correct_index": 1, "reason": "x"}]',
        questionIds: ids,
      );

      expect(items.single.questionIndex, 1);
    });
  });

  group('new options without an index', () {
    test('the answer follows its own text', () async {
      final items = await service.parseCorrections(
        questions: [
          q(
            'ব্লুটুথ কোন প্রযুক্তিতে চলে?',
            correct: 0,
            options: const ['রেডিও ওয়েভ', 'ইনফ্রারেড', 'মাইক্রোওয়েভ', 'স্যাটেলাইট'],
          ),
        ],
        externalAnalysis:
            '[{"question_index": 0, "status": "ambiguous", '
            '"new_options": ["অবলোহিত রশ্মি", "রেডিও ওয়েভ", "এক্স-রে", "অতিবেগুনি"], '
            '"reason": "overlap"}]',
      );

      // Not left at 0, which would now read "অবলোহিত রশ্মি".
      expect(items.single.proposedCorrectIndex, 1);
      expect(items.single.newOptions, isNotNull);
    });

    test('options are left alone when the answer cannot be found', () async {
      final items = await service.parseCorrections(
        questions: [
          q(
            'ব্লুটুথ কোন প্রযুক্তিতে চলে?',
            correct: 0,
            options: const ['রেডিও ওয়েভ', 'ইনফ্রারেড', 'মাইক্রোওয়েভ', 'স্যাটেলাইট'],
          ),
        ],
        externalAnalysis:
            '[{"question_index": 0, "status": "ambiguous", '
            '"new_options": ["ক", "খ", "গ", "ঘ"], "reason": "x"}]',
      );

      // Rewriting them would leave the key pointing at whatever landed there.
      expect(items.single.newOptions, isNull);
    });
  });
}

/// Rewording the answer's own option is the commonest dictated edit there is,
/// and the guard above must not mistake it for a new list.
void _rewordingTests() {
  test('rewording the answer itself keeps the answer', () async {
    final items = await QuizBatchCorrectionService.instance.parseCorrections(
      questions: [
        QuizQuestion(
          questionText: 'কোন নৃগোষ্ঠীর উৎসব বিষু?',
          options: const ['চাকমা', 'মারমা', 'ত্রিপুরা', 'গারো'],
          correctIndex: 0,
          explanation: '',
        ),
      ],
      externalAnalysis: 'অপশন ক হবে: তঞ্চঙ্গ্যা',
    );

    expect(items.single.newOptions?.first, 'তঞ্চঙ্গ্যা');
    // Still slot 0 — the answer was reworded, not moved.
    expect(items.single.proposedCorrectIndex, isNull);
  });
}
