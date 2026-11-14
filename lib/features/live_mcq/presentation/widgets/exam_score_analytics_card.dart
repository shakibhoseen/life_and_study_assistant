import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/exam_schedule_provider.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/premium_glass_card.dart';

class ExamScoreAnalyticsCard extends ConsumerWidget {
  const ExamScoreAnalyticsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allExamsAsync = ref.watch(allExamsStreamProvider);
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

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
            margin: const EdgeInsets.only(bottom: FluentSpacing.l),
            padding: const EdgeInsets.all(FluentSpacing.l),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: FluentRadius.cardBorder,
              border: Border.all(
                color: FluentStroke.card(brightness),
                width: FluentStroke.width,
              ),
              boxShadow: FluentElevation.card(brightness),
            ),
            child: Row(
              children: [
                PremiumIconBadge(
                  icon: Icons.insights_rounded,
                  size: 44,
                  iconSize: 24,
                  color: scheme.primary,
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'মডেল টেস্ট স্কোর অ্যানালিটিক্স',
                        style: FluentType.bodyStrong.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: FluentSpacing.xxs),
                      Text(
                        'পরীক্ষা দিয়ে স্কোর লিখুন, এখানে আপনার প্রগ্রেস গ্রাফ তৈরি হবে!',
                        style: FluentType.caption.copyWith(
                          color: scheme.onSurface
                              .withValues(alpha: 0.65),
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
          margin: const EdgeInsets.only(bottom: FluentSpacing.l),
          padding: const EdgeInsets.all(FluentSpacing.l),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: FluentRadius.cardBorder,
            border: Border.all(
              color: FluentStroke.card(brightness),
              width: FluentStroke.width,
            ),
            boxShadow: FluentElevation.card(brightness),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  PremiumIconBadge(
                    icon: Icons.insights_rounded,
                    size: 32,
                    iconSize: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'মডেল টেস্ট পারফরম্যান্স গ্রাফ',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.bodyStrong.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          'সর্বশেষ $totalExams টি পরীক্ষার ট্রেন্ড ও স্কোর',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.caption.copyWith(
                            color: scheme.onSurface
                                .withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.s,
                        vertical: FluentSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: FluentLayer.subtle(scheme.primary, brightness),
                        borderRadius: FluentRadius.controlBorder,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.trending_up_rounded,
                            size: 14,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: FluentSpacing.xs),
                          Flexible(
                            child: Text(
                              'গড়: ${avgScore.toStringAsFixed(1)}',
                              style: FluentType.caption.copyWith(
                                fontWeight: FontWeight.w600,
                                color: scheme.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FluentSpacing.l),

              // KPI stats row
              Row(
                children: [
                  _buildStatTile(
                    context,
                    'সর্বশেষ স্কোর',
                    latestScore.toStringAsFixed(1),
                    scheme.primary,
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  _buildStatTile(
                    context,
                    'সর্বোচ্চ স্কোর',
                    maxScore.toStringAsFixed(1),
                    const Color(0xFF10B981),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  _buildStatTile(
                    context,
                    'মোট পরীক্ষা',
                    '$totalExams টি',
                    scheme.onSurface.withValues(alpha: 0.75),
                  ),
                ],
              ),
              const SizedBox(height: FluentSpacing.xl),

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
                        padding: const EdgeInsets.symmetric(horizontal: FluentSpacing.xs),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Score text above bar
                            Text(
                              score.toStringAsFixed(score % 1 == 0 ? 0 : 1),
                              style: FluentType.caption.copyWith(
                                fontSize: 10,
                                fontWeight: isLatest
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isLatest
                                    ? scheme.primary
                                    : scheme.onSurface
                                          .withValues(alpha: 0.75),
                              ),
                            ),
                            const SizedBox(height: FluentSpacing.xs),

                            // Animated/styled vertical bar
                            Flexible(
                              child: FractionallySizedBox(
                                heightFactor: ratio,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isLatest
                                        ? scheme.primary
                                        : scheme.primary
                                              .withValues(alpha: 0.45),
                                    borderRadius:
                                        const BorderRadius.vertical(
                                          top: Radius.circular(
                                            FluentRadius.control,
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: FluentSpacing.s),

                            // Date/Exam short label
                            Text(
                              '${e.examDate.day}/${e.examDate.month}',
                              style: FluentType.caption.copyWith(
                                fontSize: 10,
                                color: scheme.onSurface
                                    .withValues(alpha: 0.55),
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
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: FluentSpacing.s,
          horizontal: FluentSpacing.m,
        ),
        decoration: BoxDecoration(
          color: FluentLayer.subtle(color, brightness),
          borderRadius: FluentRadius.controlBorder,
          border: Border.all(
            color: FluentStroke.card(brightness),
            width: FluentStroke.width,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: FluentType.caption.copyWith(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: FluentSpacing.xxs),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentType.bodyStrong.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
