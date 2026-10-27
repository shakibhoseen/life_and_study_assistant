import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';

class GithubStudyHeatmap extends ConsumerStatefulWidget {
  const GithubStudyHeatmap({super.key});

  @override
  ConsumerState<GithubStudyHeatmap> createState() => _GithubStudyHeatmapState();
}

class _GithubStudyHeatmapState extends ConsumerState<GithubStudyHeatmap> {
  final int _daysBack = 98; // 14 weeks × 7 days
  Map<String, dynamic>? _heatmapData;
  List<Map<String, dynamic>>? _subjectDistribution;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    final db = ref.read(appDatabaseProvider);
    final data = await db.getActivityHeatmapData(daysBack: _daysBack);
    final distribution = await db.getSubjectStudyDistribution();

    if (mounted) {
      setState(() {
        _heatmapData = data;
        _subjectDistribution = distribution;
        _isLoading = false;
      });
    }
  }

  Color _getCellColor(int score) {
    if (score == 0) return Colors.grey.shade200;
    if (score <= 2) return const Color(0xFF9BE9A8); // Light green
    if (score <= 5) return const Color(0xFF40C463); // Medium green
    if (score <= 9) return const Color(0xFF30A14E); // Darker green
    return const Color(0xFF216E39); // Deep green
  }

  void _showDayDetails(
    String dateKey,
    Map<String, dynamic>? details,
    int score,
  ) {
    final drills = details?['drills'] ?? 0;
    final questions = details?['questions'] ?? 0;
    final correct = details?['correct'] ?? 0;
    final hasEnergy = details?['hasEnergyLog'] ?? false;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1A1B36),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: _getCellColor(score),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                score == 0
                    ? '$dateKey: No study activity logged'
                    : '$dateKey: $drills Drills • $questions Questions ($correct correct)${hasEnergy ? ' • Energy logged' : ''}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final scores = (_heatmapData?['scores'] as Map<String, int>?) ?? {};
    final details =
        (_heatmapData?['details'] as Map<String, Map<String, dynamic>>?) ?? {};
    final activeDays = _heatmapData?['activeDays'] ?? 0;
    final currentStreak = _heatmapData?['currentStreak'] ?? 0;
    final totalDays = _heatmapData?['totalDays'] ?? 99;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDate = today.subtract(Duration(days: _daysBack));

    // Align startDate to nearest previous Sunday so the grid rows are Sun..Sat
    final leadingPaddingDays =
        startDate.weekday % 7; // Sunday = 0, Mon = 1, ...
    final alignedStartDate = startDate.subtract(
      Duration(days: leadingPaddingDays),
    );

    final totalGridDays = _daysBack + leadingPaddingDays + 1;
    final totalWeeks = (totalGridDays / 7).ceil();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Title & GitHub Style Badges
            Row(
              children: [
                const Icon(Icons.grid_on, color: Color(0xFF2DA44E), size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Study Activity Heatmap',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_fire_department,
                        size: 14,
                        color: Colors.deepOrange,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$currentStreak Days Streak',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$activeDays active study days in the last 14 weeks ($totalDays days track)',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),

            // Horizontal Scrollable GitHub Grid
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Weekday labels (M, W, F)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 14), // Sun
                        _buildWeekdayLabel('Mon'),
                        const SizedBox(height: 16), // Tue
                        _buildWeekdayLabel('Wed'),
                        const SizedBox(height: 16), // Thu
                        _buildWeekdayLabel('Fri'),
                      ],
                    ),
                  ),

                  // 14 Weeks Column Grid
                  Row(
                    children: List.generate(totalWeeks, (weekIndex) {
                      return Column(
                        children: List.generate(7, (dayOfWeek) {
                          final dayOffset = (weekIndex * 7) + dayOfWeek;
                          final cellDate = alignedStartDate.add(
                            Duration(days: dayOffset),
                          );

                          // Don't draw future days beyond today
                          if (cellDate.isAfter(today)) {
                            return const SizedBox(width: 14, height: 14);
                          }

                          // If before the requested start date, draw empty placeholder
                          if (cellDate.isBefore(startDate)) {
                            return const SizedBox(width: 14, height: 14);
                          }

                          final dateKey =
                              '${cellDate.year}-${cellDate.month.toString().padLeft(2, '0')}-${cellDate.day.toString().padLeft(2, '0')}';
                          final score = scores[dateKey] ?? 0;
                          final dayDetail = details[dateKey];

                          return GestureDetector(
                            onTap: () =>
                                _showDayDetails(dateKey, dayDetail, score),
                            child: Container(
                              width: 12,
                              height: 12,
                              margin: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: _getCellColor(score),
                                borderRadius: BorderRadius.circular(2.5),
                                border: Border.all(
                                  color: score > 0
                                      ? Colors.black.withValues(alpha: 0.08)
                                      : Colors.grey.shade300,
                                  width: 0.5,
                                ),
                              ),
                            ),
                          );
                        }),
                      );
                    }),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // GitHub Legend (Less [0][1][2][3][4] More)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Less',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 4),
                _buildLegendCell(Colors.grey.shade200),
                _buildLegendCell(const Color(0xFF9BE9A8)),
                _buildLegendCell(const Color(0xFF40C463)),
                _buildLegendCell(const Color(0xFF30A14E)),
                _buildLegendCell(const Color(0xFF216E39)),
                const SizedBox(width: 4),
                Text(
                  'More',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ],
            ),

            // Subject Distribution Breakdown (if available)
            if (_subjectDistribution != null &&
                _subjectDistribution!.isNotEmpty) ...[
              const Divider(height: 24),
              const Row(
                children: [
                  Icon(Icons.donut_small, color: Colors.indigo, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Subject Time & Focus Distribution',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Multi-segment horizontal bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 10,
                  child: Row(
                    children: _subjectDistribution!.map((item) {
                      final pct =
                          (item['percentage'] as num?)?.toDouble() ?? 0.0;
                      final color = _getSubjectColor(
                        item['subject']?.toString(),
                      );
                      return Expanded(
                        flex: (pct * 10).round().clamp(1, 1000),
                        child: Container(color: color),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Subject chips with percentages
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _subjectDistribution!.take(5).map((item) {
                  final subject = item['subject']?.toString() ?? 'General';
                  final pct = ((item['percentage'] as num?)?.toDouble() ?? 0.0)
                      .toStringAsFixed(0);
                  final color = _getSubjectColor(subject);

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$subject ($pct%)',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWeekdayLabel(String text) {
    return SizedBox(
      height: 12,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          color: Colors.grey.shade500,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildLegendCell(Color color) {
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
    );
  }

  Color _getSubjectColor(String? subject) {
    if (subject == null) return Colors.indigo;
    final s = subject.toLowerCase();
    if (s.contains('bangla') || s.contains('বাংলা')) return Colors.teal;
    if (s.contains('math') || s.contains('গণিত')) return Colors.orange;
    if (s.contains('science') || s.contains('বিজ্ঞান')) return Colors.blue;
    if (s.contains('english') || s.contains('ইংরেজি')) return Colors.purple;
    if (s.contains('gk') || s.contains('general') || s.contains('বাংলাদেশ')) {
      return Colors.green;
    }
    return Colors.indigo;
  }
}
