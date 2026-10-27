import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/claim_math_checker.dart';

void main() {
  group('Ratio Checks', () {
    test('catches the flag ratio error without asking a model', () {
      final r = ClaimMathChecker.check('পতাকার অনুপাত ১০:৬, অর্থাৎ ৩:২।');

      expect(r.outcome, MathCheckOutcome.fails);
      expect(r.detail, contains('৫:৩'));
    });

    test('accepts an equivalent pair', () {
      final r = ClaimMathChecker.check('অনুপাত ১০:৬ অর্থাৎ ৫:৩।');
      expect(r.outcome, MathCheckOutcome.holds);
    });

    test('works with English digits too', () {
      expect(
        ClaimMathChecker.check('ratio 10:6 equals 3:2').outcome,
        MathCheckOutcome.fails,
      );
    });

    test('a single ratio is nothing to compare', () {
      expect(
        ClaimMathChecker.check('অনুপাত ১০:৬।').outcome,
        MathCheckOutcome.notApplicable,
      );
    });
  });

  group('Equation Checks', () {
    test('catches a wrong sum', () {
      final r = ClaimMathChecker.check('মোট ২০ + ১ = ২২ শতাংশ।');

      expect(r.outcome, MathCheckOutcome.fails);
      expect(r.detail, contains('২১'));
    });

    test('accepts a correct sum', () {
      expect(
        ClaimMathChecker.check('২০ + ১ = ২১ শতাংশ।').outcome,
        MathCheckOutcome.holds,
      );
    });

    test('handles multiplication', () {
      expect(
        ClaimMathChecker.check('১০ × ১০ = ১০০').outcome,
        MathCheckOutcome.holds,
      );
      expect(
        ClaimMathChecker.check('১০ × ১০ = ১১০').outcome,
        MathCheckOutcome.fails,
      );
    });
  });

  group('Non-Mathematical Claims', () {
    test('prose with no arithmetic is left to the model', () {
      expect(
        ClaimMathChecker.check(
          'ব্রহ্মপুত্র নদ তিব্বতের মানস সরোবর থেকে উৎপন্ন।',
        ).outcome,
        MathCheckOutcome.notApplicable,
      );
      expect(
        ClaimMathChecker.check('').outcome,
        MathCheckOutcome.notApplicable,
      );
    });

    test('a year on its own is not an equation', () {
      expect(
        ClaimMathChecker.check('১৯৭১ সালের ১৭ এপ্রিল ঘোষণা করা হয়।').outcome,
        MathCheckOutcome.notApplicable,
      );
    });

    test('one wrong sum decides it even among correct ones', () {
      final r = ClaimMathChecker.check('২ + ২ = ৪ এবং ৩ + ৩ = ৭।');
      expect(r.outcome, MathCheckOutcome.fails);
      expect(r.detail, contains('৬'));
    });
  });
}
