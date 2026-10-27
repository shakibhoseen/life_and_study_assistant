import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/utils/bengali_math_sanitizer.dart';

void main() {
  group('BengaliMathSanitizer Tests', () {
    test(
      'User exact issue: sanitizes degree and arithmetic in Bengali sentence',
      () {
        const input = r'''
• সমাধান: আমরা জানি, বৃত্তস্থ চতুর্ভুজের বিপরীত কোণদ্বয়ের সমষ্টি ১৮০°।
  সুতরাং, বিপরীত কোণটি হবে
  $180^\circ - 60^\circ = 120^\circ$ ।
''';

        final output = BengaliMathSanitizer.sanitize(input);

        expect(output.contains(r'$'), isFalse);
        expect(output.contains(r'^\circ'), isFalse);
        expect(output.contains(r'\circ'), isFalse);
        // Harmonized with Bengali digits to match surrounding text
        expect(output.contains('১৮০° - ৬০° = ১২০°'), isTrue);
      },
    );

    test(
      r'User exact issue: replaces $to_right$ and direction arrow variants',
      () {
        expect(BengaliMathSanitizer.sanitize(r'A $to_right$ B'), 'A → B');
        expect(BengaliMathSanitizer.sanitize(r'A \to B'), 'A → B');
        expect(BengaliMathSanitizer.sanitize(r'A \rightarrow B'), 'A → B');
        expect(BengaliMathSanitizer.sanitize(r'A to_right B'), 'A → B');
        expect(BengaliMathSanitizer.sanitize(r'A $to_left$ B'), 'A ← B');
        expect(BengaliMathSanitizer.sanitize(r'A \leftarrow B'), 'A ← B');
      },
    );

    test('Handles degree variants including 180 circ or 180^circ', () {
      expect(
        BengaliMathSanitizer.sanitize(
          r'180^\circ',
          harmonizeBengaliDigits: false,
        ),
        '180°',
      );
      expect(
        BengaliMathSanitizer.sanitize(
          r'180^{\circ}',
          harmonizeBengaliDigits: false,
        ),
        '180°',
      );
      expect(
        BengaliMathSanitizer.sanitize(
          r'180 \circ',
          harmonizeBengaliDigits: false,
        ),
        '180°',
      );
      expect(
        BengaliMathSanitizer.sanitize(
          r'180 circ',
          harmonizeBengaliDigits: false,
        ),
        '180°',
      );
      expect(BengaliMathSanitizer.sanitize(r'১৮০ circ'), '১৮০°');
    });

    test('Converts powers and superscripts into clean Unicode', () {
      expect(BengaliMathSanitizer.sanitize(r'x^2 + y^2 = r^2'), 'x² + y² = r²');
      expect(BengaliMathSanitizer.sanitize(r'a^3 + b^3'), 'a³ + b³');
      expect(BengaliMathSanitizer.sanitize(r'10^n'), '10ⁿ');
      expect(BengaliMathSanitizer.sanitize(r'e^{-x}'), 'e⁻ˣ');
    });

    test('Converts subscripts and logarithms into clean Unicode', () {
      expect(
        BengaliMathSanitizer.sanitize(r'log_{10}(100) = 2'),
        'log₁₀(100) = 2',
      );
      expect(BengaliMathSanitizer.sanitize(r'H_2O'), 'H₂O');
    });

    test('Converts fractions into Unicode or clean inline syntax', () {
      expect(BengaliMathSanitizer.sanitize(r'\frac{1}{2}'), '½');
      expect(BengaliMathSanitizer.sanitize(r'\frac{1}{4}'), '¼');
      expect(BengaliMathSanitizer.sanitize(r'\frac{a}{b}'), '(a / b)');
    });

    test('Converts square roots into clean Unicode', () {
      expect(BengaliMathSanitizer.sanitize(r'\sqrt{16} = 4'), '√(16) = 4');
      expect(BengaliMathSanitizer.sanitize(r'\sqrt[3]{8} = 2'), '3√(8) = 2');
    });

    test('Converts math comparison and arithmetic operators', () {
      expect(
        BengaliMathSanitizer.sanitize(r'a \times b \div c \pm d'),
        'a × b ÷ c ± d',
      );
      expect(
        BengaliMathSanitizer.sanitize(r'x \leq y \geq z \neq 0'),
        'x ≤ y ≥ z ≠ 0',
      );
      expect(
        BengaliMathSanitizer.sanitize(r'a \approx b \equiv c'),
        'a ≈ b ≡ c',
      );
    });

    test('Converts geometry symbols cleanly', () {
      expect(
        BengaliMathSanitizer.sanitize(
          r'\angle ABC = 90^\circ',
          harmonizeBengaliDigits: false,
        ),
        '∠ABC = 90°',
      );
      expect(
        BengaliMathSanitizer.sanitize(r'\triangle ABC \cong \triangle DEF'),
        '△ABC ≅ △DEF',
      );
    });

    test('Digit converters work bidirectionally without loss', () {
      expect(BengaliMathSanitizer.toBengaliDigits('0123456789'), '০১২৩৪৫৬৭৮৯');
      expect(BengaliMathSanitizer.toEnglishDigits('০১২৩৪৫৬৭৮৯'), '0123456789');
    });
  });
}
