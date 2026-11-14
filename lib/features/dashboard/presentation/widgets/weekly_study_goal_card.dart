import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
            title: const Text('সাপ্তাহিক লক্ষ্যমাত্রা নির্ধারণ'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'সাপ্তাহিক স্টাডি আওয়ার্স টার্গেট:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'সাপ্তাহিক মডেল টেস্ট টার্গেট:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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

        final examProgress = (_targetExams > 0
                ? (completedThisWeek / _targetExams)
                : 0.0)
            .clamp(0.0, 1.0);

        final totalProgress = examProgress;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
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
              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.flag_circle_rounded,
                      color: Color(0xFF10B981),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'সাপ্তাহিক স্টাডি ও এক্সাম গোল',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'চলতি সপ্তাহের লক্ষ্যমাত্রা অর্জন',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune, size: 18),
                    tooltip: 'টার্গেট পরিবর্তন করুন',
                    color: isDark ? Colors.white54 : Colors.black45,
                    onPressed: _showEditGoalDialog,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Progress metric 1: Exams Completed
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.assignment_turned_in_outlined,
                        size: 15,
                        color: Color(0xFF10B981),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'মডেল টেস্ট সম্পন্ন:',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '$completedThisWeek / $_targetExams টি',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: examProgress,
                  minHeight: 7,
                  backgroundColor: isDark
                      ? Colors.grey.shade800
                      : Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF10B981),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Encouraging footer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.celebration_outlined,
                      size: 15,
                      color: Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        totalProgress >= 1.0
                            ? 'অভিনন্দন! এই সপ্তাহের সব লক্ষ্য সম্পন্ন হয়েছে 🎉'
                            : 'সপ্তাহের ${(totalProgress * 100).toInt()}% লক্ষ্য শেষ। এগিয়ে যান!',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white70 : const Color(0xFF334155),
                        ),
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
