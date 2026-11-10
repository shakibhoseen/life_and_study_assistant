import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/features/quiz/domain/external_audit_brief.dart';
import 'package:life_and_study_assistant/features/quiz/domain/spoken_edit.dart';

/// Nobody says the same sentence twice. These are the ways the same six
/// intentions actually come out of a person's mouth, and the reader has to
/// take all of them — or the grammar is a form, not speech.
void main() {
  group('moving the answer', () {
    const sayings = [
      'উত্তর গ হবে',
      'গ হবে',
      'সঠিক উত্তর গ',
      'উত্তরটা হবে গ',
      'গ',
      'answer is c',
      'তিন নম্বরটা সঠিক',
    ];

    for (final said in sayings) {
      test('"$said"', () {
        final edit = readSpokenEdit(said);
        expect(edit.kind, SpokenEditKind.answer, reason: said);
        expect(edit.optionIndex, 2, reason: said);
      });
    }
  });

  group('rewriting one option', () {
    const sayings = [
      'অপশন গ হবে: তঞ্চঙ্গ্যা',
      'অপশন গ হবে তঞ্চঙ্গ্যা',
      'গ অপশনটা তঞ্চঙ্গ্যা হবে',
      'অপশন গ তে তঞ্চঙ্গ্যা বসাও',
      'অপশন গ - তঞ্চঙ্গ্যা',
      'option c should be তঞ্চঙ্গ্যা',
    ];

    for (final said in sayings) {
      test('"$said"', () {
        final edit = readSpokenEdit(said);
        expect(edit.kind, SpokenEditKind.option, reason: said);
        expect(edit.optionIndex, 2, reason: said);
        expect(edit.payload, 'তঞ্চঙ্গ্যা', reason: said);
      });
    }
  });

  group('rewriting the question', () {
    const sayings = [
      'প্রশ্ন হবে: কোন শিরা অক্সিজেনসমৃদ্ধ রক্ত বহন করে',
      'প্রশ্নটা হবে কোন শিরা অক্সিজেনসমৃদ্ধ রক্ত বহন করে',
      'প্রশ্নটা এভাবে লিখুন: কোন শিরা অক্সিজেনসমৃদ্ধ রক্ত বহন করে',
    ];

    for (final said in sayings) {
      test('"$said"', () {
        final edit = readSpokenEdit(said);
        expect(edit.kind, SpokenEditKind.questionText, reason: said);
        expect(edit.payload, contains('অক্সিজেনসমৃদ্ধ'), reason: said);
      });
    }
  });

  group('rewriting the explanation', () {
    const sayings = [
      'ব্যাখ্যা হবে: সূত্রটা ভিন্ন',
      'ব্যাখ্যাটা হবে সূত্রটা ভিন্ন',
      'ব্যাখ্যা এমন হবে - সূত্রটা ভিন্ন',
    ];

    for (final said in sayings) {
      test('"$said"', () {
        final edit = readSpokenEdit(said);
        expect(edit.kind, SpokenEditKind.explanation, reason: said);
        expect(edit.payload, 'সূত্রটা ভিন্ন', reason: said);
      });
    }
  });

  group('raising a doubt', () {
    const sayings = [
      'এই প্রশ্নে ভুল আছে',
      'প্রশ্নটা ঠিক নেই',
      'এটা নিয়ে সন্দেহ আছে',
      'প্রশ্নটা সংশোধন করতে হবে',
      'এখানে একাধিক উত্তর সম্ভব',
    ];

    for (final said in sayings) {
      test('"$said"', () {
        final edit = readSpokenEdit(said);
        expect(edit.kind, SpokenEditKind.doubt, reason: said);
        // A doubt never carries wording, so nothing can be written from it.
        expect(edit.payload, isEmpty, reason: said);
      });
    }

    test('asking for the book is its own kind of doubt', () {
      expect(
        readSpokenEdit('বই দেখে নিতে হবে').status,
        QuestionAuditStatus.needsSource,
      );
      expect(
        readSpokenEdit('এই প্রশ্নে ভুল আছে').status,
        QuestionAuditStatus.ambiguous,
      );
    });
  });

  group('dropping the question', () {
    for (final said in const [
      'প্রশ্নটা বাদ দাও',
      'এটা বাতিল করুন',
      'প্রশ্নটা মুছে ফেলো',
      'delete this question',
    ]) {
      test('"$said"', () {
        expect(readSpokenEdit(said).kind, SpokenEditKind.delete, reason: said);
      });
    }
  });

  group('what it refuses to read', () {
    test('a complaint about an option writes nothing into it', () {
      // "অপশন গ ঠিক নয়" names an option and no replacement for it. Writing
      // "ঠিক নয়" into option গ would be the worst possible reading.
      final edit = readSpokenEdit('অপশন গ ঠিক নয়');

      expect(edit.kind, SpokenEditKind.doubt);
      expect(edit.payload, isEmpty);
    });

    test('a complaint that names the answer is a correction', () {
      final edit = readSpokenEdit('এই প্রশ্নটা ঠিক নেই, গ হবে');

      expect(edit.kind, SpokenEditKind.answer);
      expect(edit.optionIndex, 2);
    });

    test('a question rewrite needs actual wording, not a verdict', () {
      // "প্রশ্নটা ভুল" is a complaint of two words; a rewritten question is a
      // sentence. Anything shorter is read as a doubt instead.
      expect(readSpokenEdit('প্রশ্নটা ভুল').kind, isNot(SpokenEditKind.questionText));
      expect(readSpokenEdit('প্রশ্ন হবে:').kind, isNot(SpokenEditKind.questionText));
    });

    test('ordinary talk is left alone', () {
      for (final said in const [
        'এই প্রশ্নটা ভালো হয়েছে',
        'পরের প্রশ্নে যাও',
        'ধন্যবাদ',
      ]) {
        expect(readSpokenEdit(said).kind, SpokenEditKind.none, reason: said);
      }
    });
  });

  group('the chips', () {
    test('tapping one and dictating the words reads back as intended', () {
      final expected = {
        'উত্তর হবে ': SpokenEditKind.answer,
        'অপশন ক হবে: ': SpokenEditKind.option,
        'প্রশ্ন হবে: ': SpokenEditKind.questionText,
        'ব্যাখ্যা হবে: ': SpokenEditKind.explanation,
      };

      for (final (label, prefix) in spokenEditChips) {
        final kind = expected[prefix];
        if (kind == null) {
          // The two doubt chips are complete sentences on their own.
          expect(readSpokenEdit(prefix).kind, SpokenEditKind.doubt,
              reason: label);
          continue;
        }
        final dictated = kind == SpokenEditKind.answer
            ? '$prefix গ'
            : '$prefix নতুন লেখাটা এখানে বসবে';
        expect(readSpokenEdit(dictated).kind, kind, reason: '$label → $dictated');
      }
    });
  });
}
