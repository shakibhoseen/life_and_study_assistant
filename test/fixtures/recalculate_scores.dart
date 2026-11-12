// ignore_for_file: avoid_print, unused_local_variable
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

int levenshtein(String s1, String s2) {
  if (s1 == s2) return 0;
  if (s1.isEmpty) return s2.length;
  if (s2.isEmpty) return s1.length;
  List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
  List<int> v1 = List<int>.filled(s2.length + 1, 0);
  for (int i = 0; i < s1.length; i++) {
    v1[0] = i + 1;
    for (int j = 0; j < s2.length; j++) {
      int cost = (s1.codeUnitAt(i) == s2.codeUnitAt(j)) ? 0 : 1;
      v1[j + 1] = math.min(v1[j] + 1, math.min(v0[j + 1] + 1, v0[j] + cost));
    }
    for (int j = 0; j <= s2.length; j++) {
      v0[j] = v1[j];
    }
  }
  return v1[s2.length];
}

void main() {
  final gtFile = File('test_results/verified_ground_truth_inventory.json');
  final gtList = jsonDecode(gtFile.readAsStringSync()) as List<dynamic>;

  // Define line-by-line alignments
  // GT Lines 1 to 35
  final List<Map<String, String>> alignments = [
    {
      'id': 'L01',
      'gt': '১. এমবেডেড সিস্টেমে বিদ্যুৎ খরচ-',
      'fast': '১, এমবেডেড সিস্টেমে বিদ্যুৎ খরচ-',
      'best': '১. এমবেডেড সিস্টেমে বিদ্যুৎ খরচ_',
    },
    {
      'id': 'L02',
      'gt': 'সমাজসেবা অধিদপ্তরের (সমাজসেবা অফিসার): ১৩; বিজেএস (সহকারী জজ): ০৩',
      'fast': '(সমাজসেবা অধিদণডরের\n(সমাজসেবা অফিসার): ১৩; বিজেএস সেহকারী জজ): ০৩।',
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
    {
      'id': 'L15',
      'gt': 'ক. চিপস',
      'fast': '@ চিপস',
      'best': 'ও চিপস',
    },
    {
      'id': 'L16',
      'gt': 'খ. প্রসেসর',
      'fast': '© প্রসেসর',
      'best': '& প্রসেসর',
    },
    {
      'id': 'L17',
      'gt': 'গ. মাইক্রোপ্রসেসর ও মাইক্রোকন্ট্রোলার',
      'fast': 'Teor ও মাইক্রোকস্ট্রোলার.',
      'best': '© মাইক্রোপ্রসেসর ও মাইক্রোকন্ট্রোলার',
    },
    {
      'id': 'L18',
      'gt': 'ঘ. সবগুলো',
      'fast': 'উ.ঘ',
      'best': 'উ.ঘ',
    },
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
    {
      'id': 'L21',
      'gt': 'ক. রাউটার',
      'fast': '@ রাউটার',
      'best': '© রাউটার',
    },
    {
      'id': 'L22',
      'gt': 'খ. মোবাইল ফোন',
      'fast': '@ মোবাইল ফোন',
      'best': '@ মোবাইল ফোন',
    },
    {
      'id': 'L23',
      'gt': 'গ. ATM',
      'fast': '€ ATM',
      'best': '® ATM',
    },
    {
      'id': 'L24',
      'gt': 'ঘ. সবগুলো',
      'fast': '৪ সবগুলো',
      'best': 'ও) সবগুলো',
    },
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
    {
      'id': 'L32',
      'gt': 'a. Volt',
      'fast': '@Volt',
      'best': '®@Volt',
    },
    {
      'id': 'L33',
      'gt': 'b. Hertz',
      'fast': '@Hertz',
      'best': '@Hertz',
    },
    {
      'id': 'L34',
      'gt': 'c. Digits',
      'fast': '®@Digits',
      'best': '@ Digits',
    },
    {
      'id': 'L35',
      'gt': 'd. Watts',
      'fast': '৪ Watts',
      'best': '@ Watts',
    },
  ];

  int totalRefChars = 0;
  int benRefChars = 0;
  int engRefChars = 0;

  int fastTotalDist = 0;
  int fastBenDist = 0;
  int fastEngDist = 0;

  int bestTotalDist = 0;
  int bestBenDist = 0;
  int bestEngDist = 0;

  int fastExactOptionText = 0;
  int bestExactOptionText = 0;
  int totalOptions = 24; // 6 MCQ questions with 4 options

  for (final row in alignments) {
    final gt = row['gt']!;
    final fast = row['fast']!;
    final best = row['best']!;

    totalRefChars += gt.length;
    fastTotalDist += levenshtein(gt, fast);
    bestTotalDist += levenshtein(gt, best);

    // Bengali chars only
    final gtBen = gt.replaceAll(RegExp(r'[^\u0980-\u09FF]'), '');
    final fastBen = fast.replaceAll(RegExp(r'[^\u0980-\u09FF]'), '');
    final bestBen = best.replaceAll(RegExp(r'[^\u0980-\u09FF]'), '');

    benRefChars += gtBen.length;
    fastBenDist += levenshtein(gtBen, fastBen);
    bestBenDist += levenshtein(gtBen, bestBen);

    // English chars only
    final gtEng = gt.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    final fastEng = fast.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    final bestEng = best.replaceAll(RegExp(r'[^a-zA-Z]'), '');

    engRefChars += gtEng.length;
    fastEngDist += levenshtein(gtEng, fastEng);
    bestEngDist += levenshtein(gtEng, bestEng);
  }

  print('=== RECALCULATED METRICS ===');
  print('Reference Total Chars: $totalRefChars');
  print('Reference Bengali Chars: $benRefChars');
  print('Reference English Chars: $engRefChars');
  print('');
  print('CANDIDATE A (FAST):');
  print('  Total CER: $fastTotalDist / $totalRefChars = ${(fastTotalDist / totalRefChars * 100).toStringAsFixed(2)}%');
  print('  Bengali CER: $fastBenDist / $benRefChars = ${(fastBenDist / benRefChars * 100).toStringAsFixed(2)}%');
  print('  English CER: $fastEngDist / $engRefChars = ${(fastEngDist / engRefChars * 100).toStringAsFixed(2)}%');
  print('');
  print('CANDIDATE B (BEST):');
  print('  Total CER: $bestTotalDist / $totalRefChars = ${(bestTotalDist / totalRefChars * 100).toStringAsFixed(2)}%');
  print('  Bengali CER: $bestBenDist / $benRefChars = ${(bestBenDist / benRefChars * 100).toStringAsFixed(2)}%');
  print('  English CER: $bestEngDist / $engRefChars = ${(bestEngDist / engRefChars * 100).toStringAsFixed(2)}%');
}
