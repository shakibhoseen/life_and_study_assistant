import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
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

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final examDateOnly = DateTime(
          exam.examDate.year,
          exam.examDate.month,
          exam.examDate.day,
        );
        final isToday = examDateOnly.difference(todayStart).inDays == 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                  : [const Color(0xFFFFFBEB), const Color(0xFFFEF3C7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.6)
                  : const Color(0xFFF59E0B),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.15 : 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header badge row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.live_help_rounded,
                        size: 18,
                        color: Color(0xFFD97706),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isToday ? 'আজকের পরীক্ষা কি দিয়েছেন?' : 'পরীক্ষা সম্পন্ন হয়েছে?',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                            ),
                          ),
                          Text(
                            '${exam.trackName} • ${exam.examTime}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      color: isDark ? Colors.white54 : Colors.black45,
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
                const SizedBox(height: 10),

                // Exam Title
                Text(
                  exam.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),

                // Topic summary
                Text(
                  'সিলেবাস: ${exam.topicsCovered}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 14),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text(
                          'হ্যাঁ, স্কোর লিখুন',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () => _showScoreEntryModal(context, ref, exam),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        side: BorderSide(
                          color: isDark ? Colors.white30 : Colors.black26,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        ref
                            .read(dismissedAccountabilityExamsProvider.notifier)
                            .dismiss(exam.id);
                      },
                      child: Text(
                        'অংশ নিইনি',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? Colors.white70 : Colors.black87,
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

  void _showScoreEntryModal(
    BuildContext context,
    WidgetRef ref,
    ExamSchedule exam,
  ) {
    final scoreController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'পরীক্ষার স্কোর সংরক্ষণ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  exam.title,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: scoreController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'আপনার প্রাপ্ত নম্বর (Marks)',
                    hintText: 'যেমন: 12.5 বা 45',
                    prefixIcon: const Icon(Icons.grade_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
                                content: Text('পরীক্ষা সম্পন্ন হিসেবে চিহ্নিত করা হয়েছে'),
                              ),
                            );
                          }
                        },
                        child: const Text('স্কোর ছাড়া সম্পন্ন করুন'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
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
                          style: TextStyle(fontWeight: FontWeight.bold),
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
