// ignore_for_file: avoid_print, unused_local_variable
import 'dart:math' as math;

/// Levenshtein distance on generic lists (characters or words)
int genericLevenshtein<T>(List<T> s1, List<T> s2) {
  if (s1.isEmpty) return s2.length;
  if (s2.isEmpty) return s1.length;
  List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
  List<int> v1 = List<int>.filled(s2.length + 1, 0);

  for (int i = 0; i < s1.length; i++) {
    v1[0] = i + 1;
    for (int j = 0; j < s2.length; j++) {
      int cost = (s1[i] == s2[j]) ? 0 : 1;
      v1[j + 1] = math.min(v1[j] + 1, math.min(v0[j + 1] + 1, v0[j] + cost));
    }
    for (int j = 0; j <= s2.length; j++) {
      v0[j] = v1[j];
    }
  }
  return v1[s2.length];
}

/// Character-level Levenshtein on Unicode runes
int runeLevenshtein(String s1, String s2) {
  return genericLevenshtein(s1.runes.toList(), s2.runes.toList());
}

/// Word-level Levenshtein on whitespace-delimited tokens
int wordLevenshtein(String s1, String s2) {
  List<String> w1 = s1
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  List<String> w2 = s2
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  return genericLevenshtein(w1, w2);
}

void main() {
  final alignments = [
    {
      'id': 'L01',
      'gt': '১. এমবেডেড সিস্টেমে বিদ্যুৎ খরচ-',
      'fast': '১, এমবেডেড সিস্টেমে বিদ্যুৎ খরচ-',
      'best': '১. এমবেডেড সিস্টেমে বিদ্যুৎ খরচ_',
    },
    {
      'id': 'L02',
      'gt': 'সমাজসেবা অধিদপ্তরের (সমাজসেবা অফিসার): ১৩; বিজেএস (সহকারী জজ): ০৩',
      'fast':
          '(সমাজসেবা অধিদণডরের\n(সমাজসেবা অফিসার): ১৩; বিজেএস সেহকারী জজ): ০৩।',
      'best': '/সমাজসেবা অধিদপ্জরের\n(সমাজসেবা অফিসার): ১৩; বিজেএস (সহকারী জজ): ০৩!',
    },
    {
      'id': 'L03',
      'gt': 'ক. কম (low)',
      'fast': 'ও কম (low)',
      'best': 'ও কম (low)',
    },
    {
      'id': 'L04',
      'gt': 'খ. বেশি (many)',
      'fast': '@ বেশি (many)',
      'best': '@ বেশি (many)',
    },
    {
      'id': 'L05',
      'gt': 'গ. কম (a few)',
      'fast': '@ নগণ্য (a few)',
      'best': '@ নগণ্য (a few)',
    },
    {
      'id': 'L06',
      'gt': 'ঘ. কোনোটিই নয়',
      'fast': 'OHMS রায় es',
      'best': 'ও কোনোটিই নয়',
    },
    {
      'id': 'L07',
      'gt': '৪. পামটপ কি?',
      'fast': '8. পামটপ কি?',
      'best': '৪. পামটপ কি?',
    },
    {
      'id': 'L08',
      'gt': 'শিক্ষক নিবন্ধন ও প্রত্যয়ন পরীক্ষা (শিক্ষক) BA: ১২',
      'fast': 'শিক্ষক Fm ওরা ara (শিক) ফুল:১২|',
      'best': '[শিক্ষক নিবন্ধন ও প্রত্যয়ন পরীক্ষা (শিক্ষক) স্কুল: ১২',
    },
    {
      'id': 'L09',
      'gt': 'ক. ছোট কুকুর',
      'fast': '@ ছোট কুকুর',
      'best': 'ও ছোট কুকুর',
    },
    {
      'id': 'L10',
      'gt': 'খ. পর্বতারোহণ সামগ্রী',
      'fast': '22',
      'best': 'ও) পর্বতারোহণ সামগ্রী',
    },
    {
      'id': 'L11',
      'gt': 'গ. বাদ্যযন্ত্র',
      'fast': 'টির',
      'best': '& বাদ্যযন্ত্র',
    },
    {
      'id': 'L12',
      'gt': 'ঘ. ছোট কম্পিউটার',
      'fast': '৪ ছোট কম্পিউটার. Bx',
      'best': '© ছোট কম্পিউটার',
    },
    {
      'id': 'L13',
      'gt': '৫. আধুনিক এমবেডেড সিস্টেমে কীসের ব্যবহার পরিলক্ষিত হয়?',
      'fast': '€. আধুনিক এমবেডেড সিস্টেমে কীসের ব্যবহার পরিলক্ষিত হয়?',
      'best': '৫. আধুনিক এমবেডেড সিস্টেমে কীসের ব্যবহার পরিলক্ষিত হয়?',
    },
    {
      'id': 'L14',
      'gt': 'বাংলাদেশ প্রাণিসম্পদ অধিদপ্তরের (সহকারী পরিচালক): ০৫',
      'fast': '[বাংলাদেশ প্রাণিসম্পদ অধিদপ্ুরের (সহকারী পরিচালক): ০৫/',
      'best': '[বাংলাদেশ প্রাণিসম্পদ অধিদপ্তরের (সহকারী পরিচালক): ০৫]',
    },
    {'id': 'L15', 'gt': 'ক. চিপস', 'fast': '@ চিপস', 'best': 'ও চিপস'},
    {'id': 'L16', 'gt': 'খ. প্রসেসর', 'fast': '© প্রসেসর', 'best': '& প্রসেসর'},
    {
      'id': 'L17',
      'gt': 'গ. মাইক্রোপ্রসেসর ও মাইক্রোকন্ট্রোলার',
      'fast': 'Teor ও মাইক্রোকস্ট্রোলার.',
      'best': '© মাইক্রোপ্রসেসর ও মাইক্রোকন্ট্রোলার',
    },
    {'id': 'L18', 'gt': 'ঘ. সবগুলো', 'fast': 'উ.ঘ', 'best': 'উ.ঘ'},
    {
      'id': 'L19',
      'gt': '৬. এমবেডেড সিস্টেমে ব্যবহৃত হয় কোনটি?',
      'fast': '৬. এমবেডেড সিস্টেমে ব্যবহৃত হয় কোনটি?',
      'best': '৬. এমবেডেড সিস্টেমে ব্যবহৃত হয় কোনটি?',
    },
    {
      'id': 'L20',
      'gt': 'খাদ্য অধিদপ্তরের খাদ্য পরিদর্শক/উপ-খাদ্য পরিদর্শক: ০২',
      'fast': 'fra whereas (amar পরিদশর্ক/উপ-খাদ্য পরিদর্শর্ক): ০২]',
      'best': '/খাদ্য অধিদপ্তরের খোদ্য পরিদরশ্ক/উপ-খাদ্য পরিদরশর্ক): ০২]',
    },
    {'id': 'L21', 'gt': 'ক. রাউটার', 'fast': '@ রাউটার', 'best': '© রাউটার'},
    {
      'id': 'L22',
      'gt': 'খ. মোবাইল ফোন',
      'fast': '@ মোবাইল ফোন',
      'best': '@ মোবাইল ফোন',
    },
    {'id': 'L23', 'gt': 'গ. ATM', 'fast': '€ ATM', 'best': '® ATM'},
    {'id': 'L24', 'gt': 'ঘ. সবগুলো', 'fast': '৪ সবগুলো', 'best': 'ও) সবগুলো'},
    {
      'id': 'L25',
      'gt': '৭. ATM এর পূর্ণরূপ কী?',
      'fast': '১, ATM-4F পূর্ণরূপ Sl?',
      'best': '১. ATM-a9 পূর্ণরূপ PN?',
    },
    {
      'id': 'L26',
      'gt': 'ক. Auto Timking Machine',
      'fast': '@ Auto Timking Machine',
      'best': '® Auto Timking Machine',
    },
    {
      'id': 'L27',
      'gt': 'খ. Automated Teller Machine',
      'fast': '@ Automated Teller Machine',
      'best': 'ও) Automated Teller Machine',
    },
    {
      'id': 'L28',
      'gt': 'গ. Auto Touch Mobile',
      'fast': '@ Auto Touch Mobile',
      'best': '® Auto Touch Mobile',
    },
    {
      'id': 'L29',
      'gt': 'ঘ. Automatic Talking Mobile',
      'fast': '© Automatic Talking Mobile',
      'best': '® Automatic Talking Mobile',
    },
    {
      'id': 'L30',
      'gt': '২. Analog signal is measured in -',
      'fast': '২ Analog signal is measured in -',
      'best': '২. Analog signal is measured ip -',
    },
    {
      'id': 'L31',
      'gt': 'Rupali Bank (ANE): 15',
      'fast': '[Rupali Bank (ANE): 21]',
      'best': '[Rupali Bank (ANE): 21]',
    },
    {'id': 'L32', 'gt': 'a. Volt', 'fast': '@Volt', 'best': '®@Volt'},
    {'id': 'L33', 'gt': 'b. Hertz', 'fast': '@Hertz', 'best': '@Hertz'},
    {'id': 'L34', 'gt': 'c. Digits', 'fast': '®@Digits', 'best': '@ Digits'},
    {'id': 'L35', 'gt': 'd. Watts', 'fast': '৪ Watts', 'best': '@ Watts'},
  ];

  // Regex patterns
  // Bengali block + Bengali Danda (U+0964, U+0965)
  final benRegex = RegExp(r'[\u0980-\u09FF\u0964\u0965]');
  final engRegex = RegExp(r'[a-zA-Z]');
  final digitRegex = RegExp(r'[০-৯0-9]');

  int totalRefRunes = 0;
  int benRefRunes = 0;
  int engRefRunes = 0;
  int digitRefRunes = 0;
  int totalRefWords = 0;

  int fastTotalRuneDist = 0;
  int bestTotalRuneDist = 0;

  int fastBenRuneDist = 0;
  int bestBenRuneDist = 0;

  int fastEngRuneDist = 0;
  int bestEngRuneDist = 0;

  int fastDigitRuneDist = 0;
  int bestDigitRuneDist = 0;

  int fastWordDist = 0;
  int bestWordDist = 0;

  // Question number tracking
  final qNumLines = ['L01', 'L07', 'L13', 'L19', 'L25', 'L30']; // 6 questions
  int fastCorrectQNum = 0;
  int bestCorrectQNum = 0;

  for (final row in alignments) {
    final gt = row['gt']!;
    final fast = row['fast']!;
    final best = row['best']!;

    totalRefRunes += gt.runes.length;
    fastTotalRuneDist += runeLevenshtein(gt, fast);
    bestTotalRuneDist += runeLevenshtein(gt, best);

    // Bengali runes (with Danda included!)
    final gtBen = gt.runes
        .where((r) => benRegex.hasMatch(String.fromCharCode(r)))
        .map(String.fromCharCode)
        .join();
    final fastBen = fast.runes
        .where((r) => benRegex.hasMatch(String.fromCharCode(r)))
        .map(String.fromCharCode)
        .join();
    final bestBen = best.runes
        .where((r) => benRegex.hasMatch(String.fromCharCode(r)))
        .map(String.fromCharCode)
        .join();
    benRefRunes += gtBen.runes.length;
    fastBenRuneDist += runeLevenshtein(gtBen, fastBen);
    bestBenRuneDist += runeLevenshtein(gtBen, bestBen);

    // English runes
    final gtEng = gt.runes
        .where((r) => engRegex.hasMatch(String.fromCharCode(r)))
        .map(String.fromCharCode)
        .join();
    final fastEng = fast.runes
        .where((r) => engRegex.hasMatch(String.fromCharCode(r)))
        .map(String.fromCharCode)
        .join();
    final bestEng = best.runes
        .where((r) => engRegex.hasMatch(String.fromCharCode(r)))
        .map(String.fromCharCode)
        .join();
    engRefRunes += gtEng.runes.length;
    fastEngRuneDist += runeLevenshtein(gtEng, fastEng);
    bestEngRuneDist += runeLevenshtein(gtEng, bestEng);

    // Digit runes (Bengali + English digits)
    final gtDigit = gt.runes
        .where((r) => digitRegex.hasMatch(String.fromCharCode(r)))
        .map(String.fromCharCode)
        .join();
    final fastDigit = fast.runes
        .where((r) => digitRegex.hasMatch(String.fromCharCode(r)))
        .map(String.fromCharCode)
        .join();
    final bestDigit = best.runes
        .where((r) => digitRegex.hasMatch(String.fromCharCode(r)))
        .map(String.fromCharCode)
        .join();
    digitRefRunes += gtDigit.runes.length;
    fastDigitRuneDist += runeLevenshtein(gtDigit, fastDigit);
    bestDigitRuneDist += runeLevenshtein(gtDigit, bestDigit);

    // Words
    final words = gt
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    totalRefWords += words.length;
    fastWordDist += wordLevenshtein(gt, fast);
    bestWordDist += wordLevenshtein(gt, best);
  }

  print('================================================================');
  print('CORRECTED SCIENTIFIC METRIC AUDIT (SET-01: 35 LINES / 777 RUNES)');
  print('================================================================');
  print('Total Reference Runes: $totalRefRunes');
  print('Bengali Reference Runes (incl Danda): $benRefRunes');
  print('English Reference Runes: $engRefRunes');
  print('Digit Reference Runes: $digitRefRunes');
  print('Total Reference Words: $totalRefWords');
  print('');
  print('1. TOTAL CER (All runes, punctuation, and formatting):');
  print(
    '   - Fast: $fastTotalRuneDist / $totalRefRunes = ${(fastTotalRuneDist / totalRefRunes * 100).toStringAsFixed(2)}%',
  );
  print(
    '   - Best: $bestTotalRuneDist / $totalRefRunes = ${(bestTotalRuneDist / totalRefRunes * 100).toStringAsFixed(2)}%',
  );
  print(
    '   - Delta: ${((bestTotalRuneDist - fastTotalRuneDist) / totalRefRunes * 100).toStringAsFixed(2)}%',
  );
  print('');
  print('2. BENGALI SCRIPT CER (Letters, diacritics, danda, Bengali digits):');
  print(
    '   - Fast: $fastBenRuneDist / $benRefRunes = ${(fastBenRuneDist / benRefRunes * 100).toStringAsFixed(2)}%',
  );
  print(
    '   - Best: $bestBenRuneDist / $benRefRunes = ${(bestBenRuneDist / benRefRunes * 100).toStringAsFixed(2)}%',
  );
  print(
    '   - Delta: ${((bestBenRuneDist - fastBenRuneDist) / benRefRunes * 100).toStringAsFixed(2)}%',
  );
  print('');
  print('3. ENGLISH SCRIPT CER (Latin characters):');
  print(
    '   - Fast: $fastEngRuneDist / $engRefRunes = ${(fastEngRuneDist / engRefRunes * 100).toStringAsFixed(2)}%',
  );
  print(
    '   - Best: $bestEngRuneDist / $engRefRunes = ${(bestEngRuneDist / engRefRunes * 100).toStringAsFixed(2)}%',
  );
  print(
    '   - Delta: ${((bestEngRuneDist - fastEngRuneDist) / engRefRunes * 100).toStringAsFixed(2)}%',
  );
  print('');
  print('4. DIGIT CER (Bengali & English numerals):');
  print(
    '   - Fast: $fastDigitRuneDist / $digitRefRunes = ${(fastDigitRuneDist / digitRefRunes * 100).toStringAsFixed(2)}%',
  );
  print(
    '   - Best: $bestDigitRuneDist / $digitRefRunes = ${(bestDigitRuneDist / digitRefRunes * 100).toStringAsFixed(2)}%',
  );
  print(
    '   - Delta: ${((bestDigitRuneDist - fastDigitRuneDist) / digitRefRunes * 100).toStringAsFixed(2)}%',
  );
  print('');
  print('5. WORD ERROR RATE (WER - Token-level Levenshtein):');
  print(
    '   - Fast: $fastWordDist / $totalRefWords = ${(fastWordDist / totalRefWords * 100).toStringAsFixed(2)}%',
  );
  print(
    '   - Best: $bestWordDist / $totalRefWords = ${(bestWordDist / totalRefWords * 100).toStringAsFixed(2)}%',
  );
  print(
    '   - Delta: ${((bestWordDist - fastWordDist) / totalRefWords * 100).toStringAsFixed(2)}%',
  );
}
