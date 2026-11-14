import 'package:flutter/material.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../providers/exam_schedule_provider.dart';

class LiveMcqTimelineFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final ExamTimelineFilter currentFilter;
  final int upcomingCount;
  final int pastCount;
  final int completedCount;
  final int allCount;
  final ValueChanged<ExamTimelineFilter> onFilterChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchClear;

  const LiveMcqTimelineFilterBar({
    super.key,
    required this.searchController,
    required this.currentFilter,
    required this.upcomingCount,
    required this.pastCount,
    required this.completedCount,
    required this.allCount,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.onSearchClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final secondary = scheme.onSurface.withValues(alpha: 0.65);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        FluentSpacing.l,
        FluentSpacing.s,
        FluentSpacing.l,
        FluentSpacing.s,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(
            color: FluentStroke.card(brightness),
            width: FluentStroke.width,
          ),
        ),
      ),
      child: Column(
        children: [
          // Search Input Bar
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(
                alpha: brightness == Brightness.dark ? 0.08 : 0.04,
              ),
              borderRadius: FluentRadius.controlBorder,
              border: Border.all(
                color: FluentStroke.card(brightness),
                width: FluentStroke.width,
              ),
            ),
            child: TextField(
              controller: searchController,
              style: FluentType.body.copyWith(color: scheme.onSurface),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: FluentSpacing.m,
                  vertical: FluentSpacing.s,
                ),
                hintText: 'Search by topic, subject or routine...',
                hintStyle: FluentType.caption.copyWith(color: secondary),
                prefixIcon: Icon(Icons.search, size: 18, color: secondary),
                suffixIcon: searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          size: 16,
                          color: secondary,
                        ),
                        onPressed: onSearchClear,
                      )
                    : null,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: onSearchChanged,
            ),
          ),
          const SizedBox(height: FluentSpacing.s),

          // Timeline Filter Chips Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTimelineChip(
                  context: context,
                  label: 'Upcoming',
                  count: upcomingCount,
                  icon: Icons.upcoming,
                  isSelected: currentFilter == ExamTimelineFilter.upcoming,
                  activeColor: scheme.primary,
                  onTap: () => onFilterChanged(ExamTimelineFilter.upcoming),
                ),
                const SizedBox(width: FluentSpacing.s),
                _buildTimelineChip(
                  context: context,
                  label: 'Past',
                  count: pastCount,
                  icon: Icons.history,
                  isSelected: currentFilter == ExamTimelineFilter.past,
                  activeColor: scheme.primary,
                  onTap: () => onFilterChanged(ExamTimelineFilter.past),
                ),
                const SizedBox(width: FluentSpacing.s),
                _buildTimelineChip(
                  context: context,
                  label: 'Completed',
                  count: completedCount,
                  icon: Icons.check_circle_outline,
                  isSelected: currentFilter == ExamTimelineFilter.completed,
                  activeColor: scheme.primary,
                  onTap: () => onFilterChanged(ExamTimelineFilter.completed),
                ),
                const SizedBox(width: FluentSpacing.s),
                _buildTimelineChip(
                  context: context,
                  label: 'All',
                  count: allCount,
                  icon: Icons.list_alt,
                  isSelected: currentFilter == ExamTimelineFilter.all,
                  activeColor: scheme.primary,
                  onTap: () => onFilterChanged(ExamTimelineFilter.all),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineChip({
    required BuildContext context,
    required String label,
    required int count,
    required IconData icon,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final restForeground = scheme.onSurface.withValues(alpha: 0.65);

    return InkWell(
      onTap: onTap,
      borderRadius: FluentRadius.controlBorder,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
          horizontal: FluentSpacing.m,
          vertical: FluentSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor
              : scheme.onSurface.withValues(
                  alpha: brightness == Brightness.dark ? 0.08 : 0.04,
                ),
          borderRadius: FluentRadius.controlBorder,
          border: Border.all(
            color: isSelected ? activeColor : FluentStroke.card(brightness),
            width: FluentStroke.width,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? scheme.onPrimary : restForeground,
            ),
            const SizedBox(width: FluentSpacing.xs),
            Text(
              label,
              style: FluentType.caption.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
            const SizedBox(width: FluentSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FluentSpacing.xs,
                vertical: FluentSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? scheme.onPrimary.withValues(alpha: 0.25)
                    : scheme.onSurface.withValues(alpha: 0.08),
                borderRadius: FluentRadius.controlBorder,
              ),
              child: Text(
                '$count',
                style: FluentType.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isSelected ? scheme.onPrimary : restForeground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
