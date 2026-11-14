import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/premium_glass_card.dart';
import '../../../live_mcq/presentation/providers/exam_schedule_provider.dart';

/// Tracks exams dismissed from the accountability card during the current app session.
final dismissedAccountabilityExamsProvider =
    NotifierProvider<DismissedExamsNotifier, Set<int>>(() {
      return DismissedExamsNotifier();
    });

class DismissedExamsNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => <int>{};

  void dismiss(int examId) {
    state = {...state, examId};
  }

  void reset() {
    state = <int>{};
  }
}

/// An interactive accountability card that prompts the user if today's or a
/// recent exam is pending completion and asks for their score.
class ExamAccountabilityCard extends ConsumerWidget {
  const ExamAccountabilityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allExamsAsync = ref.watch(allExamsStreamProvider);
    final dismissedIds = ref.watch(dismissedAccountabilityExamsProvider);

    return allExamsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (exams) {
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);

        // Find uncompleted exams that are scheduled for today or up to 2 days past
        final pendingExams = exams.where((exam) {
          if (exam.completedStatus) return false;
          if (dismissedIds.contains(exam.id)) return false;

          final examDateOnly = DateTime(
            exam.examDate.year,
            exam.examDate.month,
            exam.examDate.day,
          );
          final daysDiff = examDateOnly.difference(todayStart).inDays;
          // Today (0) or past up to 2 days (-1, -2)
          return daysDiff <= 0 && daysDiff >= -2;
        }).toList();

        if (pendingExams.isEmpty) return const SizedBox.shrink();

        // Sort: today's exam first, then most recent past
        pendingExams.sort((a, b) => b.examDate.compareTo(a.examDate));
        final exam = pendingExams.first;

        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final brightness = theme.brightness;
        final onSurface = scheme.onSurface;
        final onSurfaceMuted = onSurface.withValues(alpha: 0.65);
        // Amber: this card is a prompt about something outstanding.
        const amber = Color(0xFFF59E0B);
        final examDateOnly = DateTime(
          exam.examDate.year,
          exam.examDate.month,
          exam.examDate.day,
        );
        final isToday = examDateOnly.difference(todayStart).inDays == 0;

        return Container(
          margin: const EdgeInsets.only(bottom: FluentSpacing.m),
          decoration: BoxDecoration(
            color: FluentLayer.subtle(amber, brightness),
            borderRadius: FluentRadius.cardBorder,
            border: Border.all(
              color: amber.withValues(alpha: 0.4),
              width: FluentStroke.width,
            ),
            boxShadow: FluentElevation.card(brightness),
          ),
          child: Padding(
            padding: const EdgeInsets.all(FluentSpacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header badge row
                Row(
                  children: [
                    const PremiumIconBadge(
                      icon: Icons.live_help_rounded,
                      size: 32,
                      iconSize: 18,
                      color: amber,
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isToday
                                ? 'আজকের পরীক্ষা কি দিয়েছেন?'
                                : 'পরীক্ষা সম্পন্ন হয়েছে?',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.bodyStrong.copyWith(
                              color: onSurface,
                            ),
                          ),
                          Text(
                            '${exam.trackName} • ${exam.examTime}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.caption.copyWith(
                              color: onSurfaceMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      color: onSurfaceMuted,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'পরে জানাব',
                      onPressed: () {
                        ref
                            .read(dismissedAccountabilityExamsProvider.notifier)
                            .dismiss(exam.id);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: FluentSpacing.s),

                // Exam Title
                Text(
                  exam.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.bodyStrong.copyWith(
                    fontSize: 15,
                    color: onSurface,
                  ),
                ),
                const SizedBox(height: FluentSpacing.xs),

                // Topic summary
                Text(
                  'সিলেবাস: ${exam.topicsCovered}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.caption.copyWith(color: onSurfaceMuted),
                ),
                const SizedBox(height: FluentSpacing.m),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          padding: const EdgeInsets.symmetric(
                            vertical: FluentSpacing.s,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: FluentRadius.controlBorder,
                          ),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: Text(
                          'হ্যাঁ, স্কোর লিখুন',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.bodyStrong.copyWith(fontSize: 13),
                        ),
                        onPressed: () =>
                            _showScoreEntryModal(context, ref, exam),
                      ),
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FluentSpacing.m,
                          vertical: FluentSpacing.s,
                        ),
                        side: BorderSide(
                          color: FluentStroke.card(brightness),
                          width: FluentStroke.width,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: FluentRadius.controlBorder,
                        ),
                      ),
                      onPressed: () {
                        ref
                            .read(dismissedAccountabilityExamsProvider.notifier)
                            .dismiss(exam.id);
                      },
                      child: Text(
                        'অংশ নিইনি',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.body.copyWith(color: onSurface),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showScoreEntryModal(
    BuildContext context,
    WidgetRef ref,
    ExamSchedule exam,
  ) {
    final scoreController = TextEditingController();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(FluentSpacing.xl),
            decoration: BoxDecoration(
              color: theme.cardTheme.color ?? theme.cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(FluentRadius.large),
              ),
              border: Border(
                top: BorderSide(
                  color: FluentStroke.card(brightness),
                  width: FluentStroke.width,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: FluentSpacing.l),
                    decoration: BoxDecoration(
                      color: onSurface.withValues(alpha: 0.25),
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                ),
                Text(
                  'পরীক্ষার স্কোর সংরক্ষণ',
                  style: FluentType.subtitle.copyWith(
                    fontSize: 16,
                    color: onSurface,
                  ),
                ),
                const SizedBox(height: FluentSpacing.xs),
                Text(
                  exam.title,
                  style: FluentType.body.copyWith(
                    color: onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: FluentSpacing.l),
                TextField(
                  controller: scoreController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'আপনার প্রাপ্ত নম্বর (Marks)',
                    hintText: 'যেমন: 12.5 বা 45',
                    prefixIcon: const Icon(Icons.grade_outlined),
                    border: OutlineInputBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                ),
                const SizedBox(height: FluentSpacing.l),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          // Mark complete without score
                          await ref
                              .read(examScheduleNotifierProvider.notifier)
                              .markCompleted(exam.id);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'পরীক্ষা সম্পন্ন হিসেবে চিহ্নিত করা হয়েছে',
                                ),
                              ),
                            );
                          }
                        },
                        child: const Text('স্কোর ছাড়া সম্পন্ন করুন'),
                      ),
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            vertical: FluentSpacing.m,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: FluentRadius.controlBorder,
                          ),
                        ),
                        onPressed: () async {
                          final text = scoreController.text.trim();
                          final score = double.tryParse(text);
                          await ref
                              .read(examScheduleNotifierProvider.notifier)
                              .markCompleted(exam.id, score: score);

                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  score != null
                                      ? 'অভিনন্দন! স্কোর ${score.toStringAsFixed(1)} সংরক্ষিত হয়েছে 🎉'
                                      : 'পরীক্ষা সম্পন্ন হিসেবে চিহ্নিত করা হয়েছে',
                                ),
                                backgroundColor: const Color(0xFF10B981),
                              ),
                            );
                          }
                        },
                        child: const Text(
                          'সংরক্ষণ করুন',
                          style: FluentType.bodyStrong,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
