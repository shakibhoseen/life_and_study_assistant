/// Utility for cleaning and formatting LaTeX, KaTeX, and mathematical notations
/// into native, crisp Unicode symbols that render flawlessly in Flutter
/// on all mobile screens with Bengali and English typography.
class BengaliMathSanitizer {
  BengaliMathSanitizer._();

  static const Map<String, String> _bengaliDigitsMap = {
    '0': '০',
    '1': '১',
    '2': '২',
    '3': '৩',
    '4': '৪',
    '5': '৫',
    '6': '৬',
    '7': '৭',
    '8': '৮',
    '9': '৯',
  };

  static const Map<String, String> _englishDigitsMap = {
    '০': '0',
    '১': '1',
    '২': '2',
    '৩': '3',
    '৪': '4',
    '৫': '5',
    '৬': '6',
    '৭': '7',
    '৮': '8',
    '৯': '9',
  };

  static const Map<String, String> _superscripts = {
    '0': '⁰',
    '1': '¹',
    '2': '²',
    '3': '³',
    '4': '⁴',
    '5': '⁵',
    '6': '⁶',
    '7': '⁷',
    '8': '⁸',
    '9': '⁹',
    '+': '⁺',
    '-': '⁻',
    '=': '⁼',
    '(': '⁽',
    ')': '⁾',
    'n': 'ⁿ',
    'i': 'ⁱ',
    'x': 'ˣ',
    'y': 'ʸ',
    '০': '⁰',
    '১': '¹',
    '২': '²',
    '৩': '³',
    '৪': '⁴',
    '৫': '⁵',
    '৬': '⁶',
    '৭': '⁷',
    '৮': '⁸',
    '৯': '⁹',
  };

  static const Map<String, String> _subscripts = {
    '0': '₀',
    '1': '₁',
    '2': '₂',
    '3': '₃',
    '4': '₄',
    '5': '₅',
    '6': '₆',
    '7': '₇',
    '8': '₈',
    '9': '₉',
    '+': '₊',
    '-': '₋',
    '=': '₌',
    '(': '₍',
    ')': '₎',
    'a': 'ₐ',
    'e': 'ₑ',
    'h': 'ₕ',
    'i': 'ᵢ',
    'j': 'ⱼ',
    'k': 'ₖ',
    'l': 'ₗ',
    'm': 'ₘ',
    'n': 'ₙ',
    'o': 'ₒ',
    'p': 'ₚ',
    'r': 'ᵣ',
    's': 'ₛ',
    't': 'ₜ',
    'u': 'ᵤ',
    'v': 'ᵥ',
    'x': 'ₓ',
    '০': '₀',
    '১': '₁',
    '২': '₂',
    '৩': '₃',
    '৪': '₄',
    '৫': '₅',
    '৬': '₆',
    '৭': '₇',
    '৮': '₈',
    '৯': '₉',
  };

  /// Returns true if [text] contains any Bengali unicode characters.
  static bool hasBengali(String text) {
    return RegExp(r'[\u0980-\u09FF]').hasMatch(text);
  }

  /// Converts English digits in a string to Bengali digits.
  static String toBengaliDigits(String input) {
    var result = input;
    _bengaliDigitsMap.forEach((en, bn) {
      result = result.replaceAll(en, bn);
    });
    return result;
  }

  /// Converts Bengali digits in a string to English digits.
  static String toEnglishDigits(String input) {
    var result = input;
    _englishDigitsMap.forEach((bn, en) {
      result = result.replaceAll(bn, en);
    });
    return result;
  }

  /// Cleans and transforms any raw LaTeX math or symbols into clean,
  /// native Unicode typography for mobile screens.
  static String sanitize(String text, {bool? harmonizeBengaliDigits}) {
    if (text.isEmpty) return text;

    var s = text;
    final isBengaliContext = harmonizeBengaliDigits ?? hasBengali(text);

    // 0. Clean common LLM typos (e.g. $to_right$, \to_right, to_right)
    s = s.replaceAll(RegExp(r'\$?\b(?:to_right|to-right)\b\$?'), '→');
    s = s.replaceAll(RegExp(r'\$?\b(?:to_left|to-left)\b\$?'), '←');

    // 1. Degree & Angle symbols
    // Handle: ^\circ, ^{\circ}, ^ \circ, ^\degree, ^{\degree}, \circ, \degree
    s = s.replaceAll(RegExp(r'\s*(?:\^|\^\{)\s*\\circ\}?'), '°');
    s = s.replaceAll(RegExp(r'\s*(?:\^|\^\{)\s*\\degree\}?'), '°');
    s = s.replaceAll(RegExp(r'\s*\\circ\b'), '°');
    s = s.replaceAll(RegExp(r'\s*\\degree\b'), '°');
    // Handle cases where LLM outputs "180 circ" or "180^circ" without backslash
    s = s.replaceAll(RegExp(r'(?<=[\d\u09E6-\u09EF])\s*\^\s*circ\b'), '°');
    s = s.replaceAll(RegExp(r'(?<=[\d\u09E6-\u09EF])\s+circ\b'), '°');

    // Geometric symbols
    s = s.replaceAll(RegExp(r'\\angle\s*'), '∠');
    s = s.replaceAll(RegExp(r'\\triangle\s*'), '△');
    s = s.replaceAll(RegExp(r'\\perp\b'), '⊥');
    s = s.replaceAll(RegExp(r'\\parallel\b'), '∥');
    s = s.replaceAll(RegExp(r'\\cong\b'), '≅');
    s = s.replaceAll(RegExp(r'\\odot\b'), '⊙');

    // 2. Arrows & Directions
    s = s.replaceAll(RegExp(r'\\(?:rightarrow|longrightarrow|to)\b'), '→');
    s = s.replaceAll(RegExp(r'\\(?:leftarrow|longleftarrow)\b'), '←');
    s = s.replaceAll(RegExp(r'\\(?:leftrightarrow|rightleftharpoons)\b'), '↔');
    s = s.replaceAll(RegExp(r'\\(?:Rightarrow|implies)\b'), '⇒');
    s = s.replaceAll(RegExp(r'\\Leftarrow\b'), '⇐');
    s = s.replaceAll(RegExp(r'\\(?:Leftrightarrow|iff)\b'), '⇔');
    s = s.replaceAll(RegExp(r'\\uparrow\b'), '↑');
    s = s.replaceAll(RegExp(r'\\downarrow\b'), '↓');

    // 3. Operators & Comparisons
    s = s.replaceAll(RegExp(r'\\(?:times|cdot)\b'), '×');
    s = s.replaceAll(RegExp(r'\\(?:div|divided)\b'), '÷');
    s = s.replaceAll(RegExp(r'\\(?:pm|plusminus)\b'), '±');
    s = s.replaceAll(RegExp(r'\\mp\b'), '∓');
    s = s.replaceAll(RegExp(r'\\(?:leq?|leqslant)\b'), '≤');
    s = s.replaceAll(RegExp(r'\\(?:geq?|geqslant)\b'), '≥');
    s = s.replaceAll(RegExp(r'\\(?:neq?)\b'), '≠');
    s = s.replaceAll(RegExp(r'\\(?:approx|thickapprox)\b'), '≈');
    s = s.replaceAll(RegExp(r'\\equiv\b'), '≡');
    s = s.replaceAll(RegExp(r'\\(?:sim|simeq)\b'), '∼');
    s = s.replaceAll(RegExp(r'\\propto\b'), '∝');
    s = s.replaceAll(RegExp(r'\\(?:infty|inf)\b'), '∞');

    // 4. Fractions
    s = s.replaceAll(RegExp(r'\\(?:frac|dfrac)\{1\}\{2\}'), '½');
    s = s.replaceAll(RegExp(r'\\(?:frac|dfrac)\{১\}\{২\}'), '½');
    s = s.replaceAll(RegExp(r'\\(?:frac|dfrac)\{1\}\{4\}'), '¼');
    s = s.replaceAll(RegExp(r'\\(?:frac|dfrac)\{১\}\{৪\}'), '¼');
    s = s.replaceAll(RegExp(r'\\(?:frac|dfrac)\{3\}\{4\}'), '¾');
    s = s.replaceAll(RegExp(r'\\(?:frac|dfrac)\{৩\}\{৪\}'), '¾');
    s = s.replaceAll(RegExp(r'\\(?:frac|dfrac)\{1\}\{3\}'), '⅓');
    s = s.replaceAll(RegExp(r'\\(?:frac|dfrac)\{১\}\{৩\}'), '⅓');
    s = s.replaceAll(RegExp(r'\\(?:frac|dfrac)\{2\}\{3\}'), '⅔');
    s = s.replaceAll(RegExp(r'\\(?:frac|dfrac)\{২\}\{৩\}'), '⅔');

    // General fractions: \frac{a}{b} -> (a / b)
    s = s.replaceAllMapped(
      RegExp(r'\\(?:frac|dfrac)\{([^{}]+)\}\{([^{}]+)\}'),
      (m) => '(${m[1]!.trim()} / ${m[2]!.trim()})',
    );

    // 5. Exponents / Superscripts (Multi-char and single-char)
    s = s.replaceAllMapped(RegExp(r'\^\{([^{}]+)\}'), (m) {
      final inner = m[1]!;
      final buffer = StringBuffer();
      for (int i = 0; i < inner.length; i++) {
        final char = inner[i];
        buffer.write(_superscripts[char] ?? char);
      }
      return buffer.toString();
    });

    s = s.replaceAllMapped(RegExp(r'\^([0-9nxy+\-\u09E6-\u09EF])'), (m) {
      final char = m[1]!;
      return _superscripts[char] ?? '^$char';
    });

    // 6. Subscripts
    s = s.replaceAllMapped(RegExp(r'_\{([^{}]+)\}'), (m) {
      final inner = m[1]!;
      final buffer = StringBuffer();
      for (int i = 0; i < inner.length; i++) {
        final char = inner[i];
        buffer.write(_subscripts[char] ?? char);
      }
      return buffer.toString();
    });

    s = s.replaceAllMapped(RegExp(r'_([0-9aehijklmnoprstuvx\u09E6-\u09EF])'), (
      m,
    ) {
      final char = m[1]!;
      return _subscripts[char] ?? '_$char';
    });

    s = s.replaceAll(RegExp(r'\\log\b'), 'log');
    s = s.replaceAll(RegExp(r'\\ln\b'), 'ln');

    // 7. Roots
    s = s.replaceAllMapped(
      RegExp(r'\\sqrt\[([0-9\u09E6-\u09EF]+)\]\{([^{}]+)\}'),
      (m) => '${m[1]}√(${m[2]!.trim()})',
    );
    s = s.replaceAllMapped(
      RegExp(r'\\sqrt\{([^{}]+)\}'),
      (m) => '√(${m[1]!.trim()})',
    );
    s = s.replaceAll(RegExp(r'\\sqrt\b'), '√');

    // 8. Greek & Science Symbols
    s = s.replaceAll(RegExp(r'\\pi\b'), 'π');
    s = s.replaceAll(RegExp(r'\\theta\b'), 'θ');
    s = s.replaceAll(RegExp(r'\\alpha\b'), 'α');
    s = s.replaceAll(RegExp(r'\\beta\b'), 'β');
    s = s.replaceAll(RegExp(r'\\gamma\b'), 'γ');
    s = s.replaceAll(RegExp(r'\\lambda\b'), 'λ');
    s = s.replaceAll(RegExp(r'\\mu\b'), 'μ');
    s = s.replaceAll(RegExp(r'\\Delta\b'), 'Δ');
    s = s.replaceAll(RegExp(r'\\delta\b'), 'δ');
    s = s.replaceAll(RegExp(r'\\sigma\b'), 'σ');
    s = s.replaceAll(RegExp(r'\\omega\b'), 'ω');
    s = s.replaceAll(RegExp(r'\\Omega\b'), 'Ω');
    s = s.replaceAll(RegExp(r'\\sum\b'), '∑');
    s = s.replaceAll(RegExp(r'\\prod\b'), '∏');
    s = s.replaceAll(RegExp(r'\\int\b'), '∫');

    // 9. LaTeX formatting wrappers
    s = s.replaceAllMapped(
      RegExp(r'\\(?:text|mathrm|mathbf|mathit)\{([^{}]+)\}'),
      (m) => m[1]!,
    );
    s = s.replaceAll(RegExp(r'\\(?:quad|qquad|\,|\;|\!)'), ' ');

    // 10. Strip math delimiters $$ ... $$ and $ ... $
    s = s.replaceAllMapped(
      RegExp(r'\$\$(.*?)\$\$', dotAll: true),
      (m) => m[1]!.trim(),
    );
    // Un-wrap single dollar signs containing math expressions or numbers
    s = s.replaceAllMapped(RegExp(r'\$([^\$\n]+?)\$'), (m) {
      final inner = m[1]!.trim();
      // If it looks like a currency price ($100, $5.99), keep it
      if (RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(inner)) {
        return m[0]!;
      }
      return inner;
    });

    // 11. Harmonize Bengali Digits for degrees and numbers if in Bengali context
    if (isBengaliContext) {
      // Convert numbers attached to degree symbols (e.g. 180° -> ১৮০°)
      s = s.replaceAllMapped(
        RegExp(r'(\d+)\s*°'),
        (m) => '${toBengaliDigits(m[1]!)}°',
      );

      // Harmonize simple arithmetic expressions in Bengali text (e.g. "180° - 60° = 120°")
      s = s.replaceAllMapped(
        RegExp(r'(\d+)\s*([+\-×÷=])\s*(\d+)'),
        (m) => '${toBengaliDigits(m[1]!)} ${m[2]} ${toBengaliDigits(m[3]!)}',
      );
    }

    return s;
  }
}
