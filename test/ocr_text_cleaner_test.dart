import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/media/ocr_text_cleaner.dart';

void main() {
  test('OcrTextCleaner normalizes option bullets and ligatures', () {
    const raw = '''
পামটপ কম্পিউটার বা পিডিএ (PDA) এর পূর্ণরূপ কী?
© Personal Digital Assistant
ও) Programmable Data Analyzer
@ Pushdown Automaton
€) Portable Data Analyzer
চাপ, তাপ, তরল পদার্থের প্রবাহ               ১৪.
আ্যানালগ কম্পিউটার সাধারণত কী পরিমাপের জন্য ব্যবহত হয়?
''';

    final cleaned = OcrTextCleaner.clean(raw);
    expect(cleaned.contains('©'), isFalse);
    expect(cleaned.contains('@'), isFalse);
    expect(cleaned.contains('€'), isFalse);
    expect(cleaned.contains('(•) Personal Digital Assistant'), isTrue);
    expect(cleaned.contains('(•) Programmable Data Analyzer'), isTrue);
    expect(cleaned.contains('অ্যানালগ'), isTrue);
    expect(cleaned.contains('ব্যবহৃত'), isTrue);
  });
}
