import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../quiz/presentation/widgets/quiz_drill_modal.dart';
import '../../domain/exam_revision_match.dart';

/// What to revise tonight, for the exam that comes next.
///
/// The app knew the exam and what it covers, and separately knew which topics
/// the user is weak at and which questions they have got wrong. Nothing put
/// the two together, so the night before a literature exam nothing pointed at
/// the literature cards already sitting in the deck.
class NextExamRevisionCard extends ConsumerWidget {
  const NextExamRevisionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(_nextExamRevisionProvider);

    return plan.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) {
        if (data == null || data.items.isEmpty) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final onSurface = scheme.onSurface;
        final onSurfaceMuted = onSurface.withValues(alpha: 0.65);

        return Card(
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: FluentSpacing.s),
          shape: RoundedRectangleBorder(
            borderRadius: FluentRadius.cardBorder,
            side: FluentStroke.side(theme.brightness),
          ),
          child: Padding(
            padding: const EdgeInsets.all(FluentSpacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_stories_rounded,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Expanded(
                      child: Text(
                        data.daysAway == 0
                            ? 'আজকের পরীক্ষার আগে'
                            : data.daysAway == 1
                            ? 'কালকের পরীক্ষার আগে'
                            : '${data.daysAway} দিন পরের পরীক্ষার আগে',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.bodyStrong.copyWith(color: onSurface),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FluentSpacing.xxs),
                Text(
                  data.examTitle,
                  style: FluentType.caption.copyWith(color: onSurfaceMuted),
                ),
                const SizedBox(height: FluentSpacing.m),
                Text(
                  'এই পরীক্ষার বিষয়ে আপনার দুর্বল জায়গা:',
                  style: FluentType.caption.copyWith(color: onSurfaceMuted),
                ),
                const SizedBox(height: FluentSpacing.s),
                for (final item in data.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FluentSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '• ${item.label}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.body.copyWith(color: onSurface),
                          ),
                        ),
                        const SizedBox(width: FluentSpacing.s),
                        TextButton(
                          onPressed: () => QuizDrillModal.show(
                            context,
                            topic: item.label,
                            subject: item.subject,
                          ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: scheme.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: FluentSpacing.s,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: FluentRadius.controlBorder,
                            ),
                          ),
                          child: Text('অনুশীলন', style: FluentType.caption),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The next exam and what to revise for it.
class _ExamRevision {
  final String examTitle;
  final int daysAway;
  final List<RevisionCandidate> items;

  const _ExamRevision({
    required this.examTitle,
    required this.daysAway,
    required this.items,
  });
}

final _nextExamRevisionProvider = FutureProvider<_ExamRevision?>((ref) async {
  final db = ref.watch(appDatabaseProvider);

  final upcoming = await db.getUpcomingExams();
  if (upcoming.isEmpty) return null;
  final exam = upcoming.first;

  final candidates = <RevisionCandidate>[
    for (final topic in await db.select(db.weakTopics).get())
      RevisionCandidate(
        subject: topic.subject,
        label: topic.topicName,
        source: 'দুর্বল টপিক',
      ),
  ];

  final items = revisionForExam(
    examTitle: exam.title,
    examTopics: exam.topicsCovered,
    candidates: candidates,
  );
  if (items.isEmpty) return null;

  final now = DateTime.now();
  final examDay = DateTime(
    exam.examDate.year,
    exam.examDate.month,
    exam.examDate.day,
  );
  final today = DateTime(now.year, now.month, now.day);

  return _ExamRevision(
    examTitle: exam.title,
    daysAway: examDay.difference(today).inDays,
    items: items,
  );
});
