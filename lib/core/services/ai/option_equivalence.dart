import '../../utils/bengali_math_sanitizer.dart';

/// Finds options that say the same thing in different words.
///
/// A question whose choices include both ১০:৬ and ৫:৩ has no single answer,
/// and no amount of prompting makes a model notice that reliably — measured
/// against the real model, it spotted this one some runs and not others.
/// Reducing two ratios is arithmetic, so it is settled here instead, at no
/// cost and the same way every time.
class OptionEquivalence {
  OptionEquivalence._();

  static final _ratio = RegExp(r'^(\d+)\s*:\s*(\d+)$');
  static final _number = RegExp(r'^-?\d+(?:\.\d+)?$');
  static final _fraction = RegExp(r'^(\d+)\s*/\s*(\d+)$');

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

  /// A canonical spelling of one option, or null if it is not numeric.
  ///
  /// Only values that can be compared exactly are canonicalised. Prose is
  /// left alone: two differently worded sentences may or may not mean the
  /// same thing, and guessing is worse than not checking.
  static String? canonical(String option) {
    var text = BengaliMathSanitizer.toEnglishDigits(option).trim();
    text = text.replaceAll(RegExp(r'\s+'), '');
    if (text.isEmpty) return null;

    final ratio = _ratio.firstMatch(text);
    if (ratio != null) {
      final a = int.parse(ratio.group(1)!);
      final b = int.parse(ratio.group(2)!);
      if (a == 0 || b == 0) return null;
      final g = _gcd(a, b);
      return 'r:${a ~/ g}:${b ~/ g}';
    }

    final fraction = _fraction.firstMatch(text);
    if (fraction != null) {
      final a = int.parse(fraction.group(1)!);
      final b = int.parse(fraction.group(2)!);
      if (b == 0) return null;
      final g = _gcd(a, b);
      return 'f:${a ~/ g}/${b ~/ g}';
    }

    if (_number.hasMatch(text)) {
      final value = double.tryParse(text);
      if (value == null) return null;
      return 'n:$value';
    }

    return null;
  }

  /// Index pairs whose options are the same value written differently.
  static List<(int, int)> findDuplicates(List<String> options) {
    final seen = <String, int>{};
    final pairs = <(int, int)>[];

    for (var i = 0; i < options.length; i++) {
      final key = canonical(options[i]);
      if (key == null) continue;
      final first = seen[key];
      if (first != null) {
        pairs.add((first, i));
      } else {
        seen[key] = i;
      }
    }

    return pairs;
  }

  /// A Bengali line naming the collision, for the verdict's limitations.
  static String? describe(List<String> options) {
    final pairs = findDuplicates(options);
    if (pairs.isEmpty) return null;
    final (a, b) = pairs.first;
    return '"${options[a].trim()}" ও "${options[b].trim()}" একই মান';
  }
}
