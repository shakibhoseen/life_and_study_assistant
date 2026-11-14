import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../quiz/presentation/widgets/question_bank_scanner_modal.dart';
import '../../../quiz/presentation/widgets/quiz_batch_correction_sheet.dart';
import '../../../../core/utils/option_label.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/premium_glass_card.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(top: FluentSpacing.s),
      padding: const EdgeInsets.all(FluentSpacing.m),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(brightness),
          width: FluentStroke.width,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              PremiumIconBadge(
                icon: Icons.menu_book_rounded,
                size: 28,
                iconSize: 16,
                color: scheme.primary,
              ),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Text(
                  'টেস্ট পেপার প্রশ্নমালা (${BengaliMathSanitizer.toBengaliDigits('${questions.length}')}টি MCQ)',
                  style: FluentType.bodyStrong.copyWith(fontSize: 13),
                ),
              ),
              InkWell(
                onTap: onToggleExpand,
                borderRadius: FluentRadius.controlBorder,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.s,
                    vertical: FluentSpacing.xs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          isExpanded ? 'সংক্ষেপ' : 'প্রশ্ন দেখুন',
                          style: FluentType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 16,
                        color: scheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // If Expanded: Show the list of questions cleanly formatted
          if (isExpanded) ...[
            const SizedBox(height: FluentSpacing.m),
            Divider(height: 1, color: FluentStroke.divider(brightness)),
            const SizedBox(height: FluentSpacing.s),
            ...List.generate(questions.length, (idx) {
              final q = questions[idx];
              final hasLeadingNumber = RegExp(r'^(\d+|[০-৯]+)\.')
                  .hasMatch(q.questionText.trim());
              final displayText = hasLeadingNumber
                  ? q.questionText
                  : '${idx + 1}. ${q.questionText}';
              return Padding(
                padding: const EdgeInsets.only(bottom: FluentSpacing.s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayText,
                      style: FluentType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: FluentSpacing.xs),
                    Wrap(
                      spacing: FluentSpacing.s,
                      runSpacing: FluentSpacing.xs,
                      children: q.options.asMap().entries.map((optEntry) {
                        final isCorrect = optEntry.key == q.correctIndex;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FluentSpacing.s,
                            vertical: FluentSpacing.xxs,
                          ),
                          decoration: BoxDecoration(
                            color: isCorrect
                                ? FluentLayer.subtle(
                                    Colors.green,
                                    brightness,
                                  )
                                : scheme.surface,
                            borderRadius: FluentRadius.controlBorder,
                            border: Border.all(
                              color: isCorrect
                                  ? Colors.green.withValues(alpha: 0.5)
                                  : FluentStroke.card(brightness),
                              width: FluentStroke.width,
                            ),
                          ),
                          child: Text(
                            optEntry.value,
                            style: FluentType.caption.copyWith(
                              fontSize: 11,
                              fontWeight: isCorrect
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isCorrect
                                  ? (isDark
                                        ? Colors.green.shade300
                                        : Colors.green.shade800)
                                  : scheme.onSurface
                                        .withValues(alpha: 0.75),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (q.explanation.isNotEmpty) ...[
                      const SizedBox(height: FluentSpacing.xs),
                      Text(
                        '💡 ব্যাখ্যা: ${q.explanation}',
                        style: FluentType.caption.copyWith(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: scheme.onSurface
                              .withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ] else ...[
            const SizedBox(height: FluentSpacing.s),
            Text(
              '১ম প্রশ্ন: ${questions.first.questionText}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentType.caption.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],

          const SizedBox(height: FluentSpacing.s),

          // Bottom Action Row
          Wrap(
            spacing: FluentSpacing.s,
            runSpacing: FluentSpacing.s,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.m,
                    vertical: FluentSpacing.xs + 2,
                  ),
                  foregroundColor: scheme.primary,
                  side: FluentStroke.side(brightness),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
                icon: const Icon(Icons.edit_note, size: 14),
                label: Text(
                  'সম্পাদনা',
                  style: FluentType.caption.copyWith(fontWeight: FontWeight.w600),
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
                    horizontal: FluentSpacing.m,
                    vertical: FluentSpacing.xs + 2,
                  ),
                  foregroundColor: scheme.primary,
                  side: FluentStroke.side(brightness),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
                icon: const Icon(Icons.copy_rounded, size: 13),
                label: Text(
                  'কপি',
                  style: FluentType.caption.copyWith(fontWeight: FontWeight.w600),
                ),
                onPressed: () =>
                    copyExamQuestionsToClipboard(context, exam, questions),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.m,
                    vertical: FluentSpacing.xs + 2,
                  ),
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
                icon: const Icon(Icons.auto_fix_high_rounded, size: 13),
                label: Text(
                  'AI ফিক্স',
                  style: FluentType.caption.copyWith(fontWeight: FontWeight.w600),
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
