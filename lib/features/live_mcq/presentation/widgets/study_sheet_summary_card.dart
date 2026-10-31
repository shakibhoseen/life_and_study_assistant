import 'package:flutter/material.dart';

import '../../../../core/services/ai/models/study_sheet_summary.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../quiz/presentation/widgets/quiz_drill_modal.dart';

class StudySheetSummaryCard extends StatelessWidget {
  final StudySheetSummary summary;
  final String? subject;

  const StudySheetSummaryCard({super.key, required this.summary, this.subject});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveSubject = (subject != null && subject!.trim().isNotEmpty)
        ? subject!.trim()
        : 'LiveMCQ Study Sheet';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : Colors.transparent,
        ),
      ),
      color: isDark ? const Color(0xFF111827) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.stars, color: Colors.amber, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    summary.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
            Divider(
              height: 24,
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
            Text(
              '🎯 5 High-Yield Bullet Points:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            ...summary.highYieldPoints.asMap().entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.key + 1}. ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFF818CF8) : Colors.indigo,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        BengaliMathSanitizer.sanitize(entry.value),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: isDark
                              ? const Color(0xFFE2E8F0)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (summary.recurringPastQuestions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                '🔄 Recurring Past Exam Traps:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              ...summary.recurringPastQuestions.map(
                (q) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? const Color(0xFF818CF8)
                              : Colors.indigo,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          BengaliMathSanitizer.sanitize(q),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: isDark
                                ? const Color(0xFFCBD5E1)
                                : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (summary.mnemonics.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                '🧠 Memory Shortcut (Mnemonic):',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              ...summary.mnemonics.map(
                (m) => Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.purple.withValues(alpha: 0.25)
                        : Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? Colors.purple.withValues(alpha: 0.5)
                          : Colors.purple.shade100,
                    ),
                  ),
                  child: Text(
                    m,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.purple.shade200
                          : Colors.purple.shade900,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFF1E3A8A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.psychology, size: 18),
                label: const Text(
                  '🎯 5-Question LiveMCQ Drill',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () {
                  QuizDrillModal.show(
                    context,
                    topic: summary.title,
                    subject: effectiveSubject,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
