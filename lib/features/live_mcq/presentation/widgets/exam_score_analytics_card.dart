import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/exam_schedule_provider.dart';

class ExamScoreAnalyticsCard extends ConsumerWidget {
  const ExamScoreAnalyticsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allExamsAsync = ref.watch(allExamsStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return allExamsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (exams) {
        // Filter exams that have recorded scores
        final scoredExams = exams
            .where((e) => e.completedStatus && e.score != null)
            .toList();

        // Sort chronologically (oldest to newest) for chart progression
        scoredExams.sort((a, b) => a.examDate.compareTo(b.examDate));

        if (scoredExams.isEmpty) {
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.insights_rounded,
                    color: Color(0xFF6366F1),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'মডেল টেস্ট স্কোর অ্যানালিটিক্স',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'পরীক্ষা দিয়ে স্কোর লিখুন, এখানে আপনার প্রগ্রেস গ্রাফ তৈরি হবে!',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        // Calculate metrics
        final scores = scoredExams.map((e) => e.score!).toList();
        final totalExams = scores.length;
        final avgScore = scores.reduce((a, b) => a + b) / totalExams;
        final maxScore = scores.reduce(math.max);
        final latestScore = scores.last;

        // Take last 8 exams for the chart
        final recentExams = scoredExams.length > 8
            ? scoredExams.sublist(scoredExams.length - 8)
            : scoredExams;

        final chartMax = math.max(
          recentExams.map((e) => e.score!).reduce(math.max),
          20.0,
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.insights_rounded,
                      color: Color(0xFF6366F1),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'মডেল টেস্ট পারফরম্যান্স গ্রাফ',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'সর্বশেষ $totalExams টি পরীক্ষার ট্রেন্ড ও স্কোর',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.trending_up_rounded,
                          size: 14,
                          color: Color(0xFF10B981),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'গড়: ${avgScore.toStringAsFixed(1)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // KPI stats row
              Row(
                children: [
                  _buildStatTile(
                    'সর্বশেষ স্কোর',
                    latestScore.toStringAsFixed(1),
                    const Color(0xFF3B82F6),
                    isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildStatTile(
                    'সর্বোচ্চ স্কোর',
                    maxScore.toStringAsFixed(1),
                    const Color(0xFF10B981),
                    isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildStatTile(
                    'মোট পরীক্ষা',
                    '$totalExams টি',
                    const Color(0xFFF59E0B),
                    isDark,
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Visual Bar Chart
              SizedBox(
                height: 110,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: recentExams.map((e) {
                    final score = e.score!;
                    final ratio = (score / chartMax).clamp(0.08, 1.0);
                    final isLatest = e.id == recentExams.last.id;

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Score text above bar
                            Text(
                              score.toStringAsFixed(score % 1 == 0 ? 0 : 1),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: isLatest
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isLatest
                                    ? (isDark
                                        ? const Color(0xFF6EE7B7)
                                        : const Color(0xFF059669))
                                    : (isDark ? Colors.white70 : Colors.black87),
                              ),
                            ),
                            const SizedBox(height: 4),

                            // Animated/styled vertical bar
                            Flexible(
                              child: FractionallySizedBox(
                                heightFactor: ratio,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: isLatest
                                          ? [
                                              const Color(0xFF10B981),
                                              const Color(0xFF059669),
                                            ]
                                          : [
                                              const Color(0xFF6366F1),
                                              const Color(0xFF4F46E5),
                                            ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(5),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),

                            // Date/Exam short label
                            Text(
                              '${e.examDate.day}/${e.examDate.month}',
                              style: TextStyle(
                                fontSize: 9,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatTile(
    String label,
    String value,
    Color color,
    bool isDark,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: isDark
              ? color.withValues(alpha: 0.12)
              : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
