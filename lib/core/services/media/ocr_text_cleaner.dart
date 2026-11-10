/// Utility to clean up and normalize raw OCR outputs, especially for Bengali MCQs and study notes.
class OcrTextCleaner {
  OcrTextCleaner._();

  /// Cleans raw OCR text:
  /// 1. Fixes trailing question numbers from adjacent columns in multi-column pages.
  /// 2. Normalizes circular/symbol option bullets (©, ®, €, @, ও), etc.) into clean options.
  /// 3. Corrects common Bengali ligature/conjunct OCR misreadings.
  /// 4. Removes redundant blank lines while preserving paragraph spacing.
  static String clean(String raw) {
    if (raw.trim().isEmpty) return '';

    var text = raw;

    // 1. Separate inline multi-column question numbers sitting at the end of lines
    // e.g. "তরল পদার্থের প্রবাহ               ১৪." -> splits into separate lines
    text = text.replaceAllMapped(
      RegExp(r'(\S+)\s{3,}([০-৯0-9]{1,2}[\.\,])'),
      (m) => '${m[1]}\n\n${m[2]}',
    );

    // 2. Correct common Bengali OCR ligature misreadings
    final commonFixes = {
      'আ্যানালগ': 'অ্যানালগ',
      'SOMPM': 'অ্যানালগ',
      'ত্যামপ্রিফায়ার': 'অ্যাম্প্লিফায়ার',
      'মেইনক্েম': 'মেইনফ্রেম',
      'কভিশনার': 'কন্ডিশনার',
      'রক্রিয়াকরণের': 'প্রক্রিয়াকরণের',
      'পরক্রিয়াকরণের': 'প্রক্রিয়াকরণের',
      'নিন্নলিখিত': 'নিম্নলিখিত',
      'ব্যবহত': 'ব্যবহৃত',
      'মাইক্রোকম্পিউটার ও': 'মাইক্রোকম্পিউটার ৪.',
    };

    commonFixes.forEach((wrong, correct) {
      text = text.replaceAll(wrong, correct);
    });

    // 3. Clean line by line: normalize option bullets
    final lines = text.split('\n');
    final cleaned = <String>[];

    for (var line in lines) {
      var trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (cleaned.isNotEmpty && cleaned.last.isNotEmpty) {
          cleaned.add('');
        }
        continue;
      }

      // Convert common confused option bullet symbols:
      // ©, @, €, ® -> (•)
      // ও), তা), গু), ঘ) -> (•)
      trimmed = trimmed
          .replaceAll(RegExp(r'^[©@€®]\s*'), '(•) ')
          .replaceAll(RegExp(r'^[ওতাগুঘ]\)\s*'), '(•) ');

      cleaned.add(trimmed);
    }

    return cleaned.join('\n');
  }
}
