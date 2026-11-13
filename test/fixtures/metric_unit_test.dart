// ignore_for_file: avoid_print
import 'dart:math' as math;

/// Levenshtein distance on generic lists (characters, runes, or words)
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

int runeLevenshtein(String s1, String s2) {
  return genericLevenshtein(s1.runes.toList(), s2.runes.toList());
}

int wordLevenshtein(String s1, String s2) {
  List<String> w1 = s1.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  List<String> w2 = s2.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  return genericLevenshtein(w1, w2);
}

/// Evaluates MCQ option body validity:
/// Rejects empty bodies, option markers as bodies, and answer keys (e.g. 'উ.ঘ')
bool isValidOptionBody({required String gtBody, required String predBody}) {
  final cleanPred = predBody.trim();
  if (cleanPred.isEmpty) return false;

  // Answer indicator patterns (e.g., 'উ.ঘ', 'Ans: A', 'উ-ক', 'উত্তর: গ')
  final answerPattern = RegExp(r'^(?:উ[\.\:\-]|ans[\.\:\-]|উত্তর[\.\:\-]|answer[\.\:\-])\s*[কখগঘabcdABCD]', caseSensitive: false);
  if (answerPattern.hasMatch(cleanPred)) {
    return false; // Rejected: answer key indicator is NOT option body text
  }

  // Bare option marker pattern (e.g. just 'ঘ', '(ঘ)', 'D.')
  final bareMarkerPattern = RegExp(r'^[\(\[]?[কখগঘabcdABCD][\)\]\.\:\-]?$');
  if (bareMarkerPattern.hasMatch(cleanPred)) {
    return false; // Rejected: bare marker is NOT option body text
  }

  // Similarity check against GT body
  final dist = runeLevenshtein(gtBody, cleanPred);
  final similarity = 1.0 - (dist / math.max(gtBody.runes.length, cleanPred.runes.length));
  return similarity >= 0.50; // At least 50% character similarity to qualify as complete
}

void main() {
  print('================================================================');
  print('🧪 TASK A: HAND-VERIFIED METRIC TEST CASES & VALIDATION');
  print('================================================================');

  int passed = 0;
  int failed = 0;

  void assertCase(String name, dynamic actual, dynamic expected) {
    if (actual == expected) {
      print('✅ [PASS] $name: Actual=$actual, Expected=$expected');
      passed++;
    } else {
      print('❌ [FAIL] $name: Actual=$actual, Expected=$expected');
      failed++;
    }
  }

  // Case 1: Bengali Danda Substitution
  // GT: 'এটি একটি বাক্য।' (15 runes, 1 danda)
  // Pred: 'এটি একটি বাক্য,' (comma instead of danda)
  final c1Gt = 'এটি একটি বাক্য।';
  final c1Pred = 'এটি একটি বাক্য,';
  final c1Dist = runeLevenshtein(c1Gt, c1Pred);
  assertCase('Case 1 - Bengali Danda Substitution (Edit Dist)', c1Dist, 1);
  final benRegex = RegExp(r'[\u0980-\u09FF\u0964\u0965]');
  final c1GtBen = c1Gt.runes.where((r) => benRegex.hasMatch(String.fromCharCode(r))).map(String.fromCharCode).join();
  final c1PredBen = c1Pred.runes.where((r) => benRegex.hasMatch(String.fromCharCode(r))).map(String.fromCharCode).join();
  final c1BenDist = runeLevenshtein(c1GtBen, c1PredBen);
  assertCase('Case 1 - Bengali Script Runes with Danda included', c1GtBen.runes.length, 13);
  assertCase('Case 1 - Bengali Script Levenshtein (Danda missing in pred)', c1BenDist, 1);

  // Case 2: Bengali Digit Substitution
  // GT: '৫' vs Pred: '৪'
  final c2Gt = '৫';
  final c2Pred = '৪';
  final c2Dist = runeLevenshtein(c2Gt, c2Pred);
  assertCase('Case 2 - Bengali Digit Substitution (৫ -> ৪)', c2Dist, 1);

  // Case 3: English Digit Substitution
  // GT: '15' vs Pred: '21'
  final c3Gt = '15';
  final c3Pred = '21';
  final c3Dist = runeLevenshtein(c3Gt, c3Pred);
  assertCase('Case 3 - English Digit Substitution (15 -> 21)', c3Dist, 2);

  // Case 4: Missing Word
  // GT: 'আমরা বাংলায় গান গাই' (4 words)
  // Pred: 'আমরা গান গাই' (3 words)
  final c4Gt = 'আমরা বাংলায় গান গাই';
  final c4Pred = 'আমরা গান গাই';
  final c4Dist = wordLevenshtein(c4Gt, c4Pred);
  assertCase('Case 4 - Missing Word (Word Levenshtein Deletion)', c4Dist, 1);

  // Case 5: Substituted Word
  // GT: 'আমরা বাংলায় গান গাই' (4 words)
  // Pred: 'আমরা বাংলায় কথা গাই' (4 words, গান -> কথা)
  final c5Gt = 'আমরা বাংলায় গান গাই';
  final c5Pred = 'আমরা বাংলায় কথা গাই';
  final c5Dist = wordLevenshtein(c5Gt, c5Pred);
  assertCase('Case 5 - Substituted Word (Word Levenshtein Substitution)', c5Dist, 1);

  // Case 6: Missing MCQ Option Body
  // GT body: 'সবগুলো', Pred body: ''
  final c6Valid = isValidOptionBody(gtBody: 'সবগুলো', predBody: '');
  assertCase('Case 6 - Missing MCQ Option Body is Rejected', c6Valid, false);

  // Case 7: Option Marker Incorrectly Detected as Option Body
  // GT body: 'সবগুলো', Pred body: 'উ.ঘ' (Printed answer marker)
  final c7Valid = isValidOptionBody(gtBody: 'সবগুলো', predBody: 'উ.ঘ');
  assertCase('Case 7 - Answer Indicator "উ.ঘ" as Option Body is Rejected', c7Valid, false);

  // Case 7b: Valid Option Body
  // GT body: 'ছোট কুকুর', Pred body: 'ছোট কুকুর'
  final c7bValid = isValidOptionBody(gtBody: 'ছোট কুকুর', predBody: 'ছোট কুকুর');
  assertCase('Case 7b - Valid Matching Option Body is Accepted', c7bValid, true);

  print('----------------------------------------------------------------');
  print('Result: $passed Passed, $failed Failed');
  print('================================================================');
}
