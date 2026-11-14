import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/widgets/collapsible_card.dart';
import '../../../dashboard/domain/dashboard_section_prefs.dart';

class GithubStudyHeatmap extends ConsumerStatefulWidget {
  const GithubStudyHeatmap({super.key});

  @override
  ConsumerState<GithubStudyHeatmap> createState() => _GithubStudyHeatmapState();
}

class _GithubStudyHeatmapState extends ConsumerState<GithubStudyHeatmap> {
  final int _daysBack = 98; // 14 weeks × 7 days
  Map<String, dynamic>? _heatmapData;
  List<Map<String, dynamic>>? _subjectDistribution;
  bool _isLoading = false;
  bool _expanded = DashboardSectionPrefs.heatmapExpandedByDefault;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// Folded is the default, so nothing is read from the database until the
  /// section is actually open. Two queries over fourteen weeks of activity and
  /// ninety-eight cells of grid used to be paid for on every dashboard open,
  /// whether or not anybody looked at the result.
  Future<void> _restore() async {
    final expanded = await DashboardSectionPrefs.heatmapExpanded();
    if (!mounted) return;
    setState(() => _expanded = expanded);
    if (expanded) _loadAnalytics();
  }

  Future<void> _toggle(bool expanded) async {
    setState(() => _expanded = expanded);
    await DashboardSectionPrefs.setHeatmapExpanded(expanded);
    if (expanded && _heatmapData == null && !_isLoading) _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);
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

  Color _getCellColor(int score, {required bool isDark}) {
    if (score == 0) {
      return isDark ? const Color(0xFF1E293B) : Colors.grey.shade200;
    }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                color: _getCellColor(score, isDark: isDark),
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
    final activeDays = _heatmapData?['activeDays'];

    return CollapsibleCard(
      title: 'Study Activity Heatmap',
      icon: Icons.grid_on,
      iconColour: const Color(0xFF2DA44E),
      // Nothing is counted until it is opened, so there is nothing to say
      // about the fortnight until then. The streak badge that used to sit here
      // is gone: the dashboard already shows the streak at the top of the
      // screen, and saying it twice made the card look like news.
      subtitle: activeDays == null
          ? 'শেষ ১৪ সপ্তাহের পড়ার ছক — দেখতে চাপুন'
          : '$activeDays active study days in the last 14 weeks',
      expanded: _expanded,
      onToggle: _toggle,
      child: _isLoading
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final scores = (_heatmapData?['scores'] as Map<String, int>?) ?? {};
    final details =
        (_heatmapData?['details'] as Map<String, Map<String, dynamic>>?) ?? {};

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                    _buildWeekdayLabel('Mon', isDark: isDark),
                    const SizedBox(height: 16), // Tue
                    _buildWeekdayLabel('Wed', isDark: isDark),
                    const SizedBox(height: 16), // Thu
                    _buildWeekdayLabel('Fri', isDark: isDark),
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
                        onTap: () => _showDayDetails(dateKey, dayDetail, score),
                        child: Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: _getCellColor(score, isDark: isDark),
                            borderRadius: BorderRadius.circular(2.5),
                            border: Border.all(
                              color: score > 0
                                  ? (isDark
                                        ? Colors.black.withValues(alpha: 0.3)
                                        : Colors.black.withValues(alpha: 0.08))
                                  : (isDark
                                        ? const Color(0xFF334155)
                                        : Colors.grey.shade300),
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
            Flexible(
              child: Text(
                'Less',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            _buildLegendCell(_getCellColor(0, isDark: isDark), isDark: isDark),
            _buildLegendCell(const Color(0xFF9BE9A8), isDark: isDark),
            _buildLegendCell(const Color(0xFF40C463), isDark: isDark),
            _buildLegendCell(const Color(0xFF30A14E), isDark: isDark),
            _buildLegendCell(const Color(0xFF216E39), isDark: isDark),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'More',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
              Flexible(
                child: Text(
                  'Subject Time & Focus Distribution',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
                  final pct = (item['percentage'] as num?)?.toDouble() ?? 0.0;
                  final color = _getSubjectColor(item['subject']?.toString());
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
    );
  }

  Widget _buildWeekdayLabel(String text, {required bool isDark}) {
    return SizedBox(
      height: 12,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          color: isDark ? Colors.white54 : Colors.grey.shade500,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildLegendCell(Color color, {required bool isDark}) {
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: isDark
              ? const Color(0xFF334155)
              : Colors.black.withValues(alpha: 0.06),
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
