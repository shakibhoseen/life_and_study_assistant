import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/premium_glass_card.dart';
import '../../../live_mcq/presentation/providers/exam_schedule_provider.dart';

class WeeklyStudyGoalCard extends ConsumerStatefulWidget {
  const WeeklyStudyGoalCard({super.key});

  @override
  ConsumerState<WeeklyStudyGoalCard> createState() =>
      _WeeklyStudyGoalCardState();
}

class _WeeklyStudyGoalCardState extends ConsumerState<WeeklyStudyGoalCard> {
  int _targetHours = 15;
  int _targetExams = 5;

  @override
  void initState() {
    super.initState();
    _loadGoalSettings();
  }

  Future<void> _loadGoalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _targetHours = prefs.getInt('weekly_goal_hours') ?? 15;
        _targetExams = prefs.getInt('weekly_goal_exams') ?? 5;
      });
    }
  }

  Future<void> _saveGoalSettings(int hours, int exams) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('weekly_goal_hours', hours);
    await prefs.setInt('weekly_goal_exams', exams);
    if (mounted) {
      setState(() {
        _targetHours = hours;
        _targetExams = exams;
      });
    }
  }

  void _showEditGoalDialog() {
    int tempHours = _targetHours;
    int tempExams = _targetExams;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: FluentRadius.cardBorder,
            ),
            title: const Text('সাপ্তাহিক লক্ষ্যমাত্রা নির্ধারণ'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'সাপ্তাহিক স্টাডি আওয়ার্স টার্গেট:',
                  style: FluentType.bodyStrong,
                ),
                Slider(
                  value: tempHours.toDouble(),
                  min: 5,
                  max: 40,
                  divisions: 7,
                  label: '$tempHours ঘণ্টা',
                  onChanged: (val) {
                    setModalState(() {
                      tempHours = val.toInt();
                    });
                  },
                ),
                Center(
                  child: Text(
                    '$tempHours ঘণ্টা / সপ্তাহ',
                    style: FluentType.bodyStrong.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'সাপ্তাহিক মডেল টেস্ট টার্গেট:',
                  style: FluentType.bodyStrong,
                ),
                Slider(
                  value: tempExams.toDouble(),
                  min: 1,
                  max: 14,
                  divisions: 13,
                  label: '$tempExams টি',
                  onChanged: (val) {
                    setModalState(() {
                      tempExams = val.toInt();
                    });
                  },
                ),
                Center(
                  child: Text(
                    '$tempExams টি পরীক্ষা / সপ্তাহ',
                    style: FluentType.bodyStrong.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('বাতিল'),
              ),
              ElevatedButton(
                onPressed: () {
                  _saveGoalSettings(tempHours, tempExams);
                  Navigator.pop(ctx);
                },
                child: const Text('সংরক্ষণ করুন'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allExamsAsync = ref.watch(allExamsStreamProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;
    final onSurfaceMuted = onSurface.withValues(alpha: 0.65);

    final now = DateTime.now();
    // Calculate start of current week (Monday)
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final weekStart = DateTime(monday.year, monday.month, monday.day);
    final weekEnd = weekStart.add(const Duration(days: 7));

    return allExamsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (exams) {
        // Count exams completed this week
        final completedThisWeek = exams.where((e) {
          if (!e.completedStatus) return false;
          return e.examDate.isAfter(weekStart) && e.examDate.isBefore(weekEnd);
        }).length;

        final examProgress =
            (_targetExams > 0 ? (completedThisWeek / _targetExams) : 0.0).clamp(
              0.0,
              1.0,
            );

        final totalProgress = examProgress;

        return PremiumGlassCard(
          margin: const EdgeInsets.only(bottom: FluentSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  const PremiumIconBadge(
                    icon: Icons.flag_circle_rounded,
                    size: 34,
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'সাপ্তাহিক স্টাডি ও এক্সাম গোল',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.bodyStrong.copyWith(
                            color: onSurface,
                          ),
                        ),
                        Text(
                          'চলতি সপ্তাহের লক্ষ্যমাত্রা অর্জন',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.caption.copyWith(
                            color: onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune, size: 18),
                    tooltip: 'টার্গেট পরিবর্তন করুন',
                    color: onSurfaceMuted,
                    onPressed: _showEditGoalDialog,
                  ),
                ],
              ),
              const SizedBox(height: FluentSpacing.m),

              // Progress metric 1: Exams Completed
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.assignment_turned_in_outlined,
                          size: 15,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: FluentSpacing.xs + 2),
                        Flexible(
                          child: Text(
                            'মডেল টেস্ট সম্পন্ন:',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.body.copyWith(color: onSurface),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  Text(
                    '$completedThisWeek / $_targetExams টি',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.bodyStrong.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FluentSpacing.xs + 2),
              ClipRRect(
                borderRadius: FluentRadius.controlBorder,
                child: LinearProgressIndicator(
                  value: examProgress,
                  minHeight: 6,
                  backgroundColor: FluentLayer.subtle(onSurface, brightness),
                  valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                ),
              ),

              const SizedBox(height: FluentSpacing.m),

              // Encouraging footer
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: FluentSpacing.m,
                  vertical: FluentSpacing.s,
                ),
                decoration: BoxDecoration(
                  color: FluentLayer.subtle(onSurface, brightness),
                  borderRadius: FluentRadius.controlBorder,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.celebration_outlined,
                      size: 15,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: FluentSpacing.xs + 2),
                    Expanded(
                      child: Text(
                        totalProgress >= 1.0
                            ? 'অভিনন্দন! এই সপ্তাহের সব লক্ষ্য সম্পন্ন হয়েছে 🎉'
                            : 'সপ্তাহের ${(totalProgress * 100).toInt()}% লক্ষ্য শেষ। এগিয়ে যান!',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.caption.copyWith(color: onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
