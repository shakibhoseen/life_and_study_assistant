import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/models/mcq_verification.dart';
import 'package:life_and_study_assistant/core/services/ai/models/verification_result.dart';
import 'package:life_and_study_assistant/core/services/ai/option_equivalence.dart';

void main() {
  group('Options that say the same thing', () {
    test('a ratio and its reduced form collide', () {
      // The flag question: both are 5:3, so it has no single answer.
      final pairs = OptionEquivalence.findDuplicates([
        '৩ : ২',
        '১০ : ৬',
        '৫ : ৩',
        'অন্যান্য',
      ]);

      expect(pairs, hasLength(1));
      expect(pairs.single, (1, 2));
    });

    test('distinct ratios do not collide', () {
      expect(
        OptionEquivalence.findDuplicates(['৩:২', '৫:৩', '২:১', '৪:৩']),
        isEmpty,
      );
    });

    test('fractions reduce too', () {
      expect(
        OptionEquivalence.findDuplicates(['১/২', '২/৪', '৩/৫']),
        hasLength(1),
      );
    });

    test('plain numbers written differently collide', () {
      expect(OptionEquivalence.findDuplicates(['৫', '5', '৭']), hasLength(1));
    });

    test('prose options are left alone', () {
      // Two sentences may or may not mean the same thing; guessing is worse
      // than not checking.
      expect(
        OptionEquivalence.findDuplicates([
          'ব্রহ্মপুত্র',
          'পদ্মা',
          'ব্রহ্মপুত্র নদ',
          'মেঘনা',
        ]),
        isEmpty,
      );
    });

    test('a zero denominator is not treated as a value', () {
      expect(OptionEquivalence.findDuplicates(['১/০', '২/০']), isEmpty);
    });

    test('the description names both options', () {
      final text = OptionEquivalence.describe(['৩:২', '১০:৬', '৫:৩', 'ক']);

      expect(text, contains('১০ : ৬'.replaceAll(' ', '')));
      expect(text, contains('একই মান'));
    });
  });

  group('A colliding option set is never corrected', () {
    McqVerification decide(int chosen, List<String> options) =>
        McqVerification.decide(
          solve: IndependentSolve(
            chosenIndex: chosen,
            reasoning: 'যুক্তি',
            confidence: 0.9,
          ),
          storedIndex: 0,
          storedExplanation: '',
          optionCount: options.length,
          options: options,
        );

    test('the verdict is inconclusive however sure the model sounded', () {
      // The model picked an option and claimed no ambiguity; the arithmetic
      // says otherwise, and the arithmetic wins.
      final r = decide(0, ['৩ : ২', '১০ : ৬', '৫ : ৩', 'অন্যান্য']);

      expect(r.verdict, VerificationVerdict.inconclusive);
      expect(r.hasProposal, isFalse);
      expect(r.limitations, contains('একই মান'));
    });

    test('no correction is offered even when the model disagreed', () {
      final r = decide(2, ['৩ : ২', '১০ : ৬', '৫ : ৩', 'অন্যান্য']);

      expect(r.hasProposal, isFalse);
    });

    test('a clean option set still behaves normally', () {
      final r = decide(2, ['৩:২', '৫:৩', '২:১', '৪:৩']);

      expect(r.hasProposal, isTrue);
      expect(r.proposedIndex, 2);
    });
  });
}
