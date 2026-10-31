import 'package:flutter/material.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
          ),
        ),
      ),
      child: Column(
        children: [
          // Search Input Bar
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: searchController,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                hintText: 'Search by topic, subject or routine...',
                hintStyle: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? Colors.white54 : Colors.grey.shade500,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: isDark ? Colors.white54 : Colors.grey,
                ),
                suffixIcon: searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          size: 16,
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
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
          const SizedBox(height: 8),

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
                  activeColor: isDark
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFF1E3A8A),
                  onTap: () => onFilterChanged(ExamTimelineFilter.upcoming),
                ),
                const SizedBox(width: 8),
                _buildTimelineChip(
                  context: context,
                  label: 'Past',
                  count: pastCount,
                  icon: Icons.history,
                  isSelected: currentFilter == ExamTimelineFilter.past,
                  activeColor: isDark
                      ? const Color(0xFFF43F5E)
                      : const Color(0xFFBE123C),
                  onTap: () => onFilterChanged(ExamTimelineFilter.past),
                ),
                const SizedBox(width: 8),
                _buildTimelineChip(
                  context: context,
                  label: 'Completed',
                  count: completedCount,
                  icon: Icons.check_circle_outline,
                  isSelected: currentFilter == ExamTimelineFilter.completed,
                  activeColor: isDark
                      ? const Color(0xFF10B981)
                      : const Color(0xFF047857),
                  onTap: () => onFilterChanged(ExamTimelineFilter.completed),
                ),
                const SizedBox(width: 8),
                _buildTimelineChip(
                  context: context,
                  label: 'All',
                  count: allCount,
                  icon: Icons.list_alt,
                  isSelected: currentFilter == ExamTimelineFilter.all,
                  activeColor: isDark
                      ? const Color(0xFF64748B)
                      : const Color(0xFF475569),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? activeColor
                : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected
                  ? Colors.white
                  : (isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (isDark
                          ? const Color(0xFFE2E8F0)
                          : const Color(0xFF334155)),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.25)
                    : (isDark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? Colors.white
                      : (isDark
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF475569)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
