import 'package:flutter/material.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../domain/today_progress.dart';

/// A line saying how much of today is done, under the thing that says what to
/// do next.
///
/// Placed there on purpose: it answers the question somebody asks right before
/// deciding whether to stop — have I done enough? The heatmap answers it for
/// last month and the streak answers it in days, and neither of them was any
/// help at nine in the evening.
///
/// A strip rather than a card, because the dashboard already has ten cards and
/// this is one sentence.
class TodayProgressStrip extends StatelessWidget {
  const TodayProgressStrip({super.key, required this.progress});

  final TodayProgress progress;

  @override
  Widget build(BuildContext context) {
    // Nothing to report is not worth a row of zeroes.
    if (progress.isUntouched) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;
    final done = progress.allTasksDone;
    // Green only when it carries the "finished" status; otherwise the accent.
    final colour = done ? const Color(0xFF10B981) : scheme.primary;

    final parts = <String>[
      if (progress.hasPlan)
        'আজ ${progress.tasksDone}/${progress.tasksTotal} টাস্ক',
      if (progress.routineMinutesTarget > 0)
        'রুটিনের ${progress.routineMinutesDone}/'
            '${progress.routineMinutesTarget} মিনিট',
      if (progress.questionsAnswered > 0)
        '${progress.questionsAnswered} টি প্রশ্ন দেখা হয়েছে',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.m,
        vertical: FluentSpacing.s,
      ),
      decoration: BoxDecoration(
        color: FluentLayer.subtle(colour, brightness),
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(brightness),
          width: FluentStroke.width,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                done ? Icons.task_alt : Icons.timelapse,
                size: 15,
                color: colour,
              ),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Text(
                  parts.join(' · '),
                  style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (progress.hasPlan) ...[
            const SizedBox(height: FluentSpacing.s),
            ClipRRect(
              borderRadius: FluentRadius.controlBorder,
              child: LinearProgressIndicator(
                value: progress.taskFraction,
                minHeight: 4,
                backgroundColor: colour.withValues(alpha: 0.18),
                valueColor: AlwaysStoppedAnimation(colour),
              ),
            ),
          ],
          if (progress.routineMinutesTarget > 0) ...[
            const SizedBox(height: FluentSpacing.xs),
            Text(
              // Said plainly, because nothing in this app measures time and a
              // figure that looks measured would be read as measured.
              'মিনিটের হিসাব রুটিনে বরাদ্দ অনুযায়ী — ঘড়ি ধরে মাপা নয়',
              style: FluentType.caption.copyWith(
                color: onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
