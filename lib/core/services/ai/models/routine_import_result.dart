class RoutineImportResult {
  final int totalParsed;
  final int insertedCount;
  final int skippedCount;
  final int updatedCount;

  const RoutineImportResult({
    required this.totalParsed,
    required this.insertedCount,
    required this.skippedCount,
    this.updatedCount = 0,
  });

  bool get hasDuplicates => skippedCount > 0 || updatedCount > 0;
  bool get allDuplicates => insertedCount == 0 && totalParsed > 0;
  bool get isAllNew => insertedCount == totalParsed;

  /// User-friendly Bengali summary message for Snackbars & dialogs
  String toBengaliMessage() {
    if (totalParsed == 0) {
      return 'রুটিন থেকে কোনো পরীক্ষার তথ্য পাওয়া যায়নি।';
    }
    if (allDuplicates) {
      return '⚠️ এই রুটিনের সব $totalParsedটি পরীক্ষা ইতোমধ্যে আপনার তালিকায় যুক্ত রয়েছে! কোনো ডুপ্লিকেট যুক্ত হয়নি।';
    }
    if (isAllNew) {
      return '🎉 সফলভাবে $insertedCountটি নতুন পরীক্ষা রুটিনে যুক্ত হয়েছে!';
    }
    final updatedText = updatedCount > 0
        ? ', $updatedCountটি আগের তথ্য আপডেট হয়েছে'
        : '';
    return '✅ $insertedCountটি নতুন পরীক্ষা যুক্ত হয়েছে$updatedText ($skippedCountটি ডুপ্লিকেট স্কিপ করা হয়েছে)।';
  }
}
