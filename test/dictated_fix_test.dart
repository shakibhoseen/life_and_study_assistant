import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/core/services/ai/quiz_batch_correction_service.dart';
import 'package:life_and_study_assistant/features/quiz/domain/external_audit_brief.dart';

/// Reading the answer out of a book and dictating it is the common case: the
/// user knows what is wrong and what it should say, and nothing about that
/// needs a model. The grammar below is the whole of what the offline reader
/// understands, so it is written down here as well as in the app's help.
void main() {
  QuizQuestion q(
    String text, {
    int correct = 0,
    String explanation = '',
    List<String>? options,
  }) {
    return QuizQuestion(
      questionText: text,
      options: options ?? const ['চাকমা', 'মারমা', 'ত্রিপুরা', 'গারো'],
      correctIndex: correct,
      explanation: explanation,
    );
  }

  Future<List<QuestionCorrectionItem>> parse(
    List<QuizQuestion> questions,
    String spoken, {
    List<int>? ids,
  }) {
    return QuizBatchCorrectionService.instance.parseCorrections(
      questions: questions,
      externalAnalysis: spoken,
      questionIds: ids,
    );
  }

  _phrasebookTests();

  group('dictating one option', () {
    test('the named option is replaced and the rest stand', () async {
      final items = await parse(
        [q('কোন নৃগোষ্ঠীর উৎসব বিষু?')],
        'অপশন গ হবে: তঞ্চঙ্গ্যা',
      );

      expect(items.single.newOptions, [
        'চাকমা',
        'মারমা',
        'তঞ্চঙ্গ্যা',
        'গারো',
      ]);
      expect(items.single.newQuestionText, isNull);
    });

    test('the option and the answer that goes with it are one edit', () async {
      final items = await parse([q('কোন নৃগোষ্ঠীর উৎসব বিষু?')], '''
অপশন গ হবে: তঞ্চঙ্গ্যা
উত্তর গ হবে
''');

      expect(items, hasLength(1));
      expect(items.single.newOptions?[2], 'তঞ্চঙ্গ্যা');
      expect(items.single.proposedCorrectIndex, 2);
    });
  });

  group('dictating the question or its explanation', () {
    test('a corrected question is written exactly as said', () async {
      final items = await parse(
        [q('কোন শিরা অক্সিজেন বহন করে?')],
        'প্রশ্ন হবে: সাধারণ নিয়মের ব্যতিক্রম হিসেবে কোন শিরা অক্সিজেনসমৃদ্ধ রক্ত বহন করে?',
      );

      expect(
        items.single.newQuestionText,
        'সাধারণ নিয়মের ব্যতিক্রম হিসেবে কোন শিরা অক্সিজেনসমৃদ্ধ রক্ত বহন করে?',
      );
    });

    test('a dictated line keeps its own commas and full stops', () async {
      // The clause splitter would have cut this in half.
      final items = await parse(
        [q('x')],
        'ব্যাখ্যা হবে: ফুসফুসীয় শিরা ব্যতিক্রম, কারণ এটি অক্সিজেনসমৃদ্ধ রক্ত বহন করে।',
      );

      expect(
        items.single.newExplanation,
        'ফুসফুসীয় শিরা ব্যতিক্রম, কারণ এটি অক্সিজেনসমৃদ্ধ রক্ত বহন করে।',
      );
    });

    test('an explanation fix does not move the answer', () async {
      final items = await parse(
        [q('x', correct: 1)],
        'ব্যাখ্যা হবে: সূত্রটা ভুল লেখা ছিল',
      );

      expect(items.single.proposedCorrectIndex, isNull);
    });
  });

  group('naming the question in a list', () {
    test('by serial', () async {
      final items = await parse([q('এক'), q('দুই')], 'প্রশ্ন ২ এর অপশন ক হবে: নতুন');

      expect(items.single.questionIndex, 1);
      expect(items.single.newOptions?.first, 'নতুন');
    });

    test('by the printed id', () async {
      final items = await parse(
        [q('এক'), q('দুই')],
        'প্রশ্ন ১৮০ এর ব্যাখ্যা হবে: ঠিক ব্যাখ্যাটা এই',
        ids: const [44, 180],
      );

      expect(items.single.questionIndex, 1);
    });

    test('an unnamed dictation over a list is ignored', () async {
      final items = await parse([q('এক'), q('দুই')], 'অপশন গ হবে: তঞ্চঙ্গ্যা');

      expect(items, isEmpty);
    });
  });

  test('nothing is invented when the words are not there', () async {
    // "the question is wrong" says nothing about what it should say.
    final items = await parse([q('এক')], 'প্রশ্ন হবে:');

    expect(items.where((i) => i.newQuestionText != null), isEmpty);
  });
}

/// Every phrase the app shows in its own help has to do what the help says.
/// A grammar that is advertised and not implemented is worse than one that is
/// neither, because the user has no way of telling which half they are in.
void _phrasebookTests() {
  QuizQuestion one() => QuizQuestion(
    questionText: 'কোন নৃগোষ্ঠীর উৎসব বিষু?',
    options: const ['চাকমা', 'মারমা', 'ত্রিপুরা', 'গারো'],
    correctIndex: 0,
    explanation: 'পুরোনো ব্যাখ্যা',
  );

  Future<QuestionCorrectionItem?> say(String phrase) async {
    final items = await QuizBatchCorrectionService.instance.parseCorrections(
      questions: [one()],
      externalAnalysis: phrase,
    );
    return items.isEmpty ? null : items.single;
  }

  group('the phrasebook the sheet shows', () {
    test('every phrase in it produces something', () async {
      for (final (phrase, effect) in voiceFixPhrasebook) {
        expect(
          await say(phrase.replaceAll('…', 'ঠিক লেখাটা এই')),
          isNotNull,
          reason: 'promised in the help but does nothing: "$phrase" ($effect)',
        );
      }
    });

    test('each phrase does the particular thing it promises', () async {
      expect((await say('উত্তর গ হবে'))!.proposedCorrectIndex, 2);
      expect((await say('অপশন খ হবে: তঞ্চঙ্গ্যা'))!.newOptions?[1], 'তঞ্চঙ্গ্যা');
      expect(
        (await say('প্রশ্ন হবে: ঠিক প্রশ্নটা এই'))!.newQuestionText,
        'ঠিক প্রশ্নটা এই',
      );
      expect(
        (await say('ব্যাখ্যা হবে: ঠিক ব্যাখ্যাটা এই'))!.newExplanation,
        'ঠিক ব্যাখ্যাটা এই',
      );
      expect((await say('এই প্রশ্নে ভুল আছে'))!.proposedCorrectIndex, isNull);
      expect(
        (await say('বই দেখে নিতে হবে'))!.newExplanation,
        contains('উৎস যাচাই দরকার'),
      );
      expect((await say('প্রশ্নটা বাদ দাও'))!.isDelete, isTrue);
    });

    test('a flag never deletes and a delete never guesses an answer', () async {
      expect((await say('এই প্রশ্নে ভুল আছে'))!.isDelete, isFalse);
      expect((await say('প্রশ্নটা বাদ দাও'))!.proposedCorrectIndex, isNull);
    });
  });
}
