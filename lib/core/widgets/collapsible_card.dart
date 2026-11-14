import 'package:flutter/material.dart';

import '../theme/fluent_tokens.dart';

/// A card whose body can be folded away behind its own header.
///
/// Written for the dashboard, where the tall backward-looking sections pushed
/// the day's actual work off the first screen. The header stays visible so the
/// section is never lost — only quiet — and the whole header is the hit target,
/// because a chevron the size of a chevron is a poor thing to aim at.
///
/// The expanded state is passed in rather than held here: it is remembered
/// across launches by whoever owns it, and a card that forgets is not folded,
/// it is annoyed.
class CollapsibleCard extends StatelessWidget {
  const CollapsibleCard({
    super.key,
    required this.title,
    required this.icon,
    required this.iconColour,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Color iconColour;

  /// Shown under the title whether open or shut — the one line worth keeping
  /// visible when the body is away.
  final String? subtitle;

  /// Anything to sit at the right of the header, before the chevron.
  final Widget? trailing;

  final bool expanded;
  final ValueChanged<bool> onToggle;

  /// Built only while open, so a folded section costs nothing to draw.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final subtitle = this.subtitle;

    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: FluentStroke.side(brightness),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => onToggle(!expanded),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                FluentSpacing.l,
                FluentSpacing.m,
                FluentSpacing.m,
                expanded ? FluentSpacing.s : FluentSpacing.m,
              ),
              child: Row(
                children: [
                  Icon(icon, color: iconColour, size: 20),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.bodyStrong.copyWith(
                            fontSize: 15,
                            color: scheme.onSurface,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: FluentSpacing.xxs),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.caption.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: FluentSpacing.s),
                    trailing!,
                  ],
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 22,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FluentSpacing.l,
                0,
                FluentSpacing.l,
                FluentSpacing.l,
              ),
              child: child,
            ),
        ],
      ),
    );
  }
}
