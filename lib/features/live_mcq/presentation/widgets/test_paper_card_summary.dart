import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../quiz/presentation/widgets/question_bank_scanner_modal.dart';
import '../../../quiz/presentation/widgets/quiz_batch_correction_sheet.dart';
import '../../../../core/utils/option_label.dart';

class TestPaperCardSummary extends ConsumerWidget {
  final ExamSchedule exam;
  final List<QuizQuestion> questions;
  final bool isExpanded;
  final VoidCallback onToggleExpand;

  const TestPaperCardSummary({
    super.key,
    required this.exam,
    required this.questions,
    required this.isExpanded,
    required this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E293B).withValues(alpha: 0.6)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5)
                      .withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  size: 16,
                  color: Color(0xFF4F46E5),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'টেস্ট পেপার প্রশ্নমালা (${BengaliMathSanitizer.toBengaliDigits('${questions.length}')}টি MCQ)',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              InkWell(
                onTap: onToggleExpand,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isExpanded ? 'সংক্ষেপ' : 'প্রশ্ন দেখুন',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? const Color(0xFFA5B4FC)
                              : const Color(0xFF4F46E5),
                        ),
                      ),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 16,
                        color: isDark
                            ? const Color(0xFFA5B4FC)
                            : const Color(0xFF4F46E5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // If Expanded: Show the list of questions cleanly formatted
          if (isExpanded) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...List.generate(questions.length, (idx) {
              final q = questions[idx];
              final hasLeadingNumber = RegExp(r'^(\d+|[০-৯]+)\.')
                  .hasMatch(q.questionText.trim());
              final displayText = hasLeadingNumber
                  ? q.questionText
                  : '${idx + 1}. ${q.questionText}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: q.options.asMap().entries.map((optEntry) {
                        final isCorrect = optEntry.key == q.correctIndex;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isCorrect
                                ? (isDark
                                      ? Colors.green.shade900.withValues(
                                          alpha: 0.3,
                                        )
                                      : Colors.green.shade50)
                                : (isDark
                                      ? const Color(0xFF0F172A)
                                      : Colors.white),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isCorrect
                                  ? Colors.green
                                  : (isDark
                                        ? Colors.white12
                                        : Colors.grey.shade300),
                              width: isCorrect ? 1.2 : 0.8,
                            ),
                          ),
                          child: Text(
                            optEntry.value,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: isCorrect
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCorrect
                                  ? (isDark
                                        ? Colors.green.shade300
                                        : Colors.green.shade800)
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (q.explanation.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '💡 ব্যাখ্যা: ${q.explanation}',
                        style: TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: isDark
                              ? Colors.amber.shade200
                              : Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              '১ম প্রশ্ন: ${questions.first.questionText}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Bottom Action Row
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  foregroundColor: isDark
                      ? const Color(0xFFA5B4FC)
                      : const Color(0xFF4F46E5),
                  side: BorderSide(
                    color: isDark
                        ? const Color(0xFF6366F1)
                        : const Color(0xFF4F46E5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(Icons.edit_note, size: 14),
                label: const Text(
                  'সম্পাদনা',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                onPressed: () => QuestionBankScannerModal.show(
                  context,
                  initialQuestions: questions,
                  initialTitle: exam.title,
                  initialSubject: exam.subject,
                  existingExamId: exam.id,
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  foregroundColor: isDark
                      ? const Color(0xFFA5B4FC)
                      : const Color(0xFF4F46E5),
                  side: BorderSide(
                    color: isDark
                        ? const Color(0xFF6366F1)
                        : const Color(0xFF4F46E5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(Icons.copy_rounded, size: 13),
                label: const Text(
                  'কপি',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                onPressed: () =>
                    copyExamQuestionsToClipboard(context, exam, questions),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(Icons.auto_fix_high_rounded, size: 13),
                label: const Text(
                  'AI ফিক্স',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                onPressed: () => QuizBatchCorrectionSheet.show(
                  context,
                  ref: ref,
                  questions: questions,
                  examId: exam.id,
                  topic: exam.topicsCovered,
                  subject: exam.title,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static void copyExamQuestionsToClipboard(
    BuildContext context,
    ExamSchedule exam,
    List<QuizQuestion> questions,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('পরীক্ষা: ${exam.title}');
    buffer.writeln('রেফারেন্স: E-${exam.id}');
    if (exam.subject.isNotEmpty) buffer.writeln('বিষয়: ${exam.subject}');
    buffer.writeln('মোট প্রশ্ন: ${questions.length}টি');
    buffer.writeln('==============================\n');

    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      buffer.writeln('প্রশ্ন ${i + 1}: ${q.questionText}');
      for (int optIdx = 0; optIdx < q.options.length; optIdx++) {
        buffer.writeln('  ${labelledOption(optIdx, q.options[optIdx])}');
      }
      final correctAns =
          q.correctIndex >= 0 && q.correctIndex < q.options.length
          ? q.options[q.correctIndex]
          : 'Unknown';
      buffer.writeln('• সঠিক উত্তর: $correctAns');
      if (q.explanation.isNotEmpty) {
        buffer.writeln('• ব্যাখ্যা: ${q.explanation}');
      }
      buffer.writeln('');
    }
    buffer.writeln('==============================');
    buffer.writeln(
      'নির্দেশনা: উপরের প্রশ্ন ও উত্তরগুলো যাচাই করে কোনো ভুল বা অসঙ্গতি থাকলে চিহ্নিত করুন।',
    );

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF10B981),
        content: Text(
          'পরীক্ষার সকল প্রশ্ন ক্লিপবোর্ডে কপি হয়েছে! অন্য AI-তে পেস্ট করতে পারেন।',
        ),
      ),
    );
  }
}
