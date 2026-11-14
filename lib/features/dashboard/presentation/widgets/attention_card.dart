import 'package:flutter/material.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/premium_ui_kit.dart';

/// One line of the backlog: what it is, how much of it, and where it goes.
@immutable
class AttentionItem {
  const AttentionItem({
    required this.label,
    required this.count,
    required this.icon,
    required this.colour,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color colour;
  final VoidCallback? onTap;
}

/// Everything waiting, with its size, in one place.
///
/// The card above this one picks a single job and says to start it. This is the
/// other half of the question: how much is behind it. They used to be answered
/// by three separate sections spread down the page — the mistake bank, the weak
/// topics, the healer — so comparing twelve unmastered questions against three
/// weak topics meant scrolling between them and holding both in your head.
///
/// The rows follow the same order as the recommendation above, so the two
/// never appear to disagree about what matters.
class AttentionCard extends StatelessWidget {
  const AttentionCard({super.key, required this.items});

  final List<AttentionItem> items;

  @override
  Widget build(BuildContext context) {
    final waiting = items.where((i) => i.count > 0).toList();
    // Nothing waiting needs no card. The recommendation above already says so.
    if (waiting.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;
    final onSurfaceMuted = onSurface.withValues(alpha: 0.65);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.cardColor,
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(brightness),
          width: FluentStroke.width,
        ),
        boxShadow: FluentElevation.card(brightness),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FluentSpacing.l,
              FluentSpacing.m,
              FluentSpacing.l,
              FluentSpacing.s,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.playlist_add_check_circle_outlined,
                  size: 17,
                  color: onSurfaceMuted,
                ),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Text(
                    'যা মনোযোগ চায়',
                    style: FluentType.bodyStrong.copyWith(color: onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          for (final item in waiting)
            InkWell(
              onTap: item.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FluentSpacing.l,
                  vertical: FluentSpacing.s,
                ),
                child: Row(
                  children: [
                    Icon(item.icon, size: 16, color: item.colour),
                    const SizedBox(width: FluentSpacing.m),
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.body.copyWith(color: onSurface),
                      ),
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    PremiumTag(label: '${item.count}', color: item.colour),
                    if (item.onTap != null) ...[
                      const SizedBox(width: FluentSpacing.xxs),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: onSurface.withValues(alpha: 0.5),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: FluentSpacing.xs),
        ],
      ),
    );
  }
}
