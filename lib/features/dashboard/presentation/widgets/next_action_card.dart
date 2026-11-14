import 'package:flutter/material.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/premium_ui_kit.dart';
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

  /// One accent: the card is the thing you act on, so it carries the theme
  /// accent. Colour beyond that is kept for status — amber for the backlog of
  /// mistakes, green for the all-clear.
  ({IconData icon, Color colour}) _look(ColorScheme scheme) =>
      switch (action.kind) {
        StudyActionKind.dueReviews => (
          icon: Icons.history_toggle_off,
          colour: scheme.primary,
        ),
        StudyActionKind.unfinishedTask => (
          icon: Icons.bolt,
          colour: scheme.primary,
        ),
        StudyActionKind.mistakeDrill => (
          icon: Icons.error_outline,
          colour: const Color(0xFFF59E0B),
        ),
        StudyActionKind.weakTopic => (
          icon: Icons.track_changes,
          colour: scheme.primary,
        ),
        StudyActionKind.allClear => (
          icon: Icons.check_circle_outline,
          colour: const Color(0xFF10B981),
        ),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;
    final look = _look(scheme);

    return Container(
      padding: const EdgeInsets.all(FluentSpacing.l),
      decoration: BoxDecoration(
        color: FluentLayer.subtle(look.colour, brightness),
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
          Row(
            children: [
              Icon(look.icon, size: 18, color: look.colour),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Text(
                  action.isAllClear ? 'আজকের কাজ শেষ' : 'এখন এটা করুন',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: look.colour,
                  ),
                ),
              ),
              if (action.minutes > 0) ...[
                const SizedBox(width: FluentSpacing.s),
                Flexible(
                  child: PremiumTag(
                    label: '~${action.minutes} মিনিট',
                    color: look.colour,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: FluentSpacing.s),
          Text(
            action.title,
            style: FluentType.bodyStrong.copyWith(
              fontSize: 15,
              color: onSurface,
            ),
          ),
          const SizedBox(height: FluentSpacing.xs),
          Text(
            action.why,
            style: FluentType.caption.copyWith(
              color: onSurface.withValues(alpha: 0.65),
            ),
          ),
          if (streakDays > 0 && !action.isAllClear) ...[
            const SizedBox(height: FluentSpacing.xs + 2),
            Row(
              children: [
                const Text('🔥', style: FluentType.caption),
                const SizedBox(width: FluentSpacing.xs),
                Expanded(
                  child: Text(
                    '$streakDays দিনের ধারা — আজ কিছু না করলে ভাঙবে',
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFF59E0B),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (onStart != null) ...[
            const SizedBox(height: FluentSpacing.m),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onStart,
                style: FilledButton.styleFrom(
                  backgroundColor: look.colour,
                  foregroundColor: scheme.onPrimary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    vertical: FluentSpacing.m,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text(
                  'শুরু করুন',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.bodyStrong,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
