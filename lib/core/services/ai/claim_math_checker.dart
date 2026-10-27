import '../../utils/bengali_math_sanitizer.dart';

/// What a local check could establish about a claim.
enum MathCheckOutcome {
  /// The arithmetic in the claim holds.
  holds,

  /// The arithmetic in the claim is wrong, and we can show why.
  fails,

  /// Nothing arithmetical to check.
  notApplicable,
}

class MathCheck {
  final MathCheckOutcome outcome;

  /// What was checked and what came of it, in Bengali, ready to show.
  final String detail;

  const MathCheck(this.outcome, this.detail);

  static const MathCheck none = MathCheck(MathCheckOutcome.notApplicable, '');

  bool get isDecisive => outcome != MathCheckOutcome.notApplicable;
}

/// Checks the arithmetic inside a claim without asking a model.
///
/// Ratios and small sums are the two things a study answer gets wrong in a way
/// that can be settled exactly, and a model recalling whether 10:6 reduces to
/// 3:2 is strictly worse than dividing by the gcd. Where this returns a
/// verdict it is the one to trust; everything else is left to the model.
class ClaimMathChecker {
  ClaimMathChecker._();

  static final _ratio = RegExp(r'(\d+)\s*:\s*(\d+)');
  static final _equation = RegExp(r'(\d+)\s*([+\-*×x])\s*(\d+)\s*=\s*(\d+)');

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

  static String _reduce(int a, int b) {
    final g = _gcd(a, b);
    if (g == 0) return '$a:$b';
    return '${a ~/ g}:${b ~/ g}';
  }

  /// Runs every applicable check over [claimText].
  ///
  /// A single failure decides the result: one wrong sum makes the claim wrong,
  /// however much else in it adds up.
  static MathCheck check(String claimText) {
    final text = BengaliMathSanitizer.toEnglishDigits(claimText);

    final ratioResult = _checkRatios(text);
    if (ratioResult.outcome == MathCheckOutcome.fails) return ratioResult;

    final equationResult = _checkEquations(text);
    if (equationResult.outcome == MathCheckOutcome.fails) return equationResult;

    if (ratioResult.isDecisive) return ratioResult;
    if (equationResult.isDecisive) return equationResult;
    return MathCheck.none;
  }

  /// Compares every pair of ratios mentioned in one claim.
  ///
  /// A claim that names two ratios is almost always asserting they are the
  /// same thing — "10:6, অর্থাৎ 3:2" — so disagreeing reductions are an error
  /// in the claim itself.
  static MathCheck _checkRatios(String text) {
    final matches = _ratio.allMatches(text).toList();
    if (matches.length < 2) return MathCheck.none;

    final ratios = <(int, int)>[];
    for (final m in matches) {
      final a = int.tryParse(m.group(1)!);
      final b = int.tryParse(m.group(2)!);
      if (a == null || b == null || a == 0 || b == 0) continue;
      ratios.add((a, b));
    }
    if (ratios.length < 2) return MathCheck.none;

    for (var i = 0; i < ratios.length; i++) {
      for (var j = i + 1; j < ratios.length; j++) {
        final (a1, b1) = ratios[i];
        final (a2, b2) = ratios[j];
        if (a1 * b2 == a2 * b1) continue;

        final r1 = _reduce(a1, b1);
        final r2 = _reduce(a2, b2);
        return MathCheck(
          MathCheckOutcome.fails,
          BengaliMathSanitizer.toBengaliDigits(
            '$a1:$b1 লঘিষ্ঠ করলে $r1 হয়, $a2:$b2 নয় (যা $r2)।',
          ),
        );
      }
    }

    final (a, b) = ratios.first;
    return MathCheck(
      MathCheckOutcome.holds,
      BengaliMathSanitizer.toBengaliDigits(
        'অনুপাতগুলো সমতুল্য ($a:$b = ${_reduce(a, b)})।',
      ),
    );
  }

  static MathCheck _checkEquations(String text) {
    final matches = _equation.allMatches(text).toList();
    if (matches.isEmpty) return MathCheck.none;

    var checked = 0;
    for (final m in matches) {
      final a = int.tryParse(m.group(1)!);
      final op = m.group(2)!;
      final b = int.tryParse(m.group(3)!);
      final stated = int.tryParse(m.group(4)!);
      if (a == null || b == null || stated == null) continue;

      final actual = switch (op) {
        '+' => a + b,
        '-' => a - b,
        _ => a * b,
      };
      checked++;
      if (actual == stated) continue;

      return MathCheck(
        MathCheckOutcome.fails,
        BengaliMathSanitizer.toBengaliDigits(
          '$a $op $b = $actual, $stated নয়।',
        ),
      );
    }

    if (checked == 0) return MathCheck.none;
    return MathCheck(
      MathCheckOutcome.holds,
      checked == 1 ? 'হিসাবটি মিলে যায়।' : 'হিসাবগুলো মিলে যায়।',
    );
  }
}
