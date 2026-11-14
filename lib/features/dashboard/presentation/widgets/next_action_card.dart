import 'package:flutter/material.dart';

import '../../domain/next_study_action.dart';

/// The one thing to start now, at the top of the dashboard.
///
/// Everything below it offers a choice; this one makes it. The dashboard holds
/// six separate calls to action and ranks none of them, and for somebody
/// opening the app tired after work, choosing between six is the hard part —
/// which is the whole reason micro-commitments exist. The reason for the pick
/// is shown too, because a recommendation whose grounds are invisible is just
/// another thing to second-guess.
///
/// It knows nothing about how to carry the action out. [onStart] comes from
/// the dashboard, which already holds the code for each of these, so none of
/// it is written twice.
class NextActionCard extends StatelessWidget {
  const NextActionCard({
    super.key,
    required this.action,
    required this.onStart,
    this.streakDays = 0,
  });

  final NextStudyAction action;

  /// Null when there is nothing to start — the all-clear case.
  final VoidCallback? onStart;

  /// Shown only when a streak is live and today would break it. A streak is a
  /// reason to start; a streak of zero is a reproach, so it stays quiet.
  final int streakDays;

  ({IconData icon, Color colour}) get _look => switch (action.kind) {
    StudyActionKind.dueReviews => (
      icon: Icons.history_toggle_off,
      colour: const Color(0xFF6366F1),
    ),
    StudyActionKind.unfinishedTask => (
      icon: Icons.bolt,
      colour: const Color(0xFF0EA5E9),
    ),
    StudyActionKind.mistakeDrill => (
      icon: Icons.error_outline,
      colour: const Color(0xFFF59E0B),
    ),
    StudyActionKind.weakTopic => (
      icon: Icons.track_changes,
      colour: const Color(0xFF14B8A6),
    ),
    StudyActionKind.allClear => (
      icon: Icons.check_circle_outline,
      colour: const Color(0xFF10B981),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final look = _look;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            look.colour.withValues(alpha: isDark ? 0.26 : 0.12),
            look.colour.withValues(alpha: isDark ? 0.10 : 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: look.colour.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(look.icon, size: 18, color: look.colour),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  action.isAllClear ? 'আজকের কাজ শেষ' : 'এখন এটা করুন',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                    color: look.colour,
                  ),
                ),
              ),
              if (action.minutes > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: look.colour.withValues(alpha: isDark ? 0.3 : 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '~${action.minutes} মিনিট',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : look.colour,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            action.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              height: 1.3,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            action.why,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          if (streakDays > 0 && !action.isAllClear) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '$streakDays দিনের ধারা — আজ কিছু না করলে ভাঙবে',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.orange.shade200
                          : Colors.orange.shade800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (onStart != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onStart,
                style: FilledButton.styleFrom(
                  backgroundColor: look.colour,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text(
                  'শুরু করুন',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
