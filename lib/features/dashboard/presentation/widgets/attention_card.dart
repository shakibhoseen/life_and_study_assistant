import 'package:flutter/material.dart';

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

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(
                  Icons.playlist_add_check_circle_outlined,
                  size: 17,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'যা মনোযোগ চায়',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
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
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(item.icon, size: 16, color: item.colour),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: item.colour.withValues(
                          alpha: isDark ? 0.3 : 0.14,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${item.count}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : item.colour,
                        ),
                      ),
                    ),
                    if (item.onTap != null) ...[
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
