import 'package:flutter/material.dart';

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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final done = progress.allTasksDone;
    final colour = done ? const Color(0xFF10B981) : const Color(0xFF6366F1);

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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: isDark ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colour.withValues(alpha: 0.3)),
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
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  parts.join(' · '),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          if (progress.hasPlan) ...[
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.taskFraction,
                minHeight: 5,
                backgroundColor: colour.withValues(alpha: 0.18),
                valueColor: AlwaysStoppedAnimation(colour),
              ),
            ),
          ],
          if (progress.routineMinutesTarget > 0) ...[
            const SizedBox(height: 5),
            Text(
              // Said plainly, because nothing in this app measures time and a
              // figure that looks measured would be read as measured.
              'মিনিটের হিসাব রুটিনে বরাদ্দ অনুযায়ী — ঘড়ি ধরে মাপা নয়',
              style: TextStyle(
                fontSize: 9.5,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
