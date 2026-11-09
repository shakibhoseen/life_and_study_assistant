import 'package:flutter/material.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitle = this.subtitle;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => onToggle(!expanded),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 10, expanded ? 6 : 14),
              child: Row(
                children: [
                  Icon(icon, color: iconColour, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 22,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
        ],
      ),
    );
  }
}
