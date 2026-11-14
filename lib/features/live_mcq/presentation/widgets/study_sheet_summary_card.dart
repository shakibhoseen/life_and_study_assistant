import 'package:flutter/material.dart';

import '../../../../core/services/ai/models/study_sheet_summary.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../../../core/widgets/premium_glass_card.dart';
import '../../../quiz/presentation/widgets/quiz_drill_modal.dart';

class StudySheetSummaryCard extends StatelessWidget {
  final StudySheetSummary summary;
  final String? subject;

  const StudySheetSummaryCard({super.key, required this.summary, this.subject});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;
    final secondary = onSurface.withValues(alpha: 0.65);
    final effectiveSubject = (subject != null && subject!.trim().isNotEmpty)
        ? subject!.trim()
        : 'LiveMCQ Study Sheet';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: FluentStroke.side(brightness),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.stars, color: scheme.primary, size: 20),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Text(
                    summary.title,
                    style: FluentType.bodyStrong.copyWith(
                      fontSize: 16,
                      color: onSurface,
                    ),
                  ),
                ),
              ],
            ),
            Divider(
              height: FluentSpacing.xxl,
              color: FluentStroke.divider(brightness),
            ),
            Text(
              '🎯 5 High-Yield Bullet Points:',
              style: FluentType.bodyStrong.copyWith(color: onSurface),
            ),
            const SizedBox(height: FluentSpacing.s),
            ...summary.highYieldPoints.asMap().entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: FluentSpacing.s),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.key + 1}. ',
                      style: FluentType.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        BengaliMathSanitizer.sanitize(entry.value),
                        style: FluentType.body.copyWith(color: onSurface),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (summary.recurringPastQuestions.isNotEmpty) ...[
              const SizedBox(height: FluentSpacing.m),
              Text(
                '🔄 Recurring Past Exam Traps:',
                style: FluentType.bodyStrong.copyWith(color: onSurface),
              ),
              const SizedBox(height: FluentSpacing.s),
              ...summary.recurringPastQuestions.map(
                (q) => Padding(
                  padding: const EdgeInsets.only(bottom: FluentSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• ',
                        style: FluentType.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          BengaliMathSanitizer.sanitize(q),
                          style: FluentType.caption.copyWith(color: secondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (summary.mnemonics.isNotEmpty) ...[
              const SizedBox(height: FluentSpacing.m),
              Text(
                '🧠 Memory Shortcut (Mnemonic):',
                style: FluentType.bodyStrong.copyWith(color: onSurface),
              ),
              const SizedBox(height: FluentSpacing.s),
              ...summary.mnemonics.map(
                (m) => Container(
                  margin: const EdgeInsets.only(bottom: FluentSpacing.xs),
                  padding: const EdgeInsets.all(FluentSpacing.s),
                  decoration: BoxDecoration(
                    color: FluentLayer.subtle(scheme.primary, brightness),
                    borderRadius: FluentRadius.controlBorder,
                    border: Border.all(
                      color: FluentStroke.card(brightness),
                      width: FluentStroke.width,
                    ),
                  ),
                  child: Text(
                    m,
                    style: FluentType.caption.copyWith(color: onSurface),
                  ),
                ),
              ),
            ],
            const SizedBox(height: FluentSpacing.l),
            PremiumButton(
              width: double.infinity,
              icon: Icons.psychology,
              label: '🎯 5-Question LiveMCQ Drill',
              onPressed: () {
                QuizDrillModal.show(
                  context,
                  topic: summary.title,
                  subject: effectiveSubject,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
