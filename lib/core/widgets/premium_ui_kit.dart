import 'package:flutter/material.dart';

import '../theme/fluent_tokens.dart';

/// A Fluent section header: accent selection bar, icon, title.
///
/// The bar is the same 3px rounded accent mark Windows 11 puts beside the
/// selected item in a NavigationView — reused here as a section marker. It no
/// longer glows; in Fluent the accent carries the emphasis on its own.
class PremiumSectionHeader extends StatelessWidget {
  const PremiumSectionHeader({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.xs,
        vertical: FluentSpacing.xxs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: subtitle != null ? 32 : 20,
            decoration: BoxDecoration(
              color: primary,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: FluentSpacing.m),
          Icon(icon, size: 18, color: primary),
          const SizedBox(width: FluentSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.bodyStrong.copyWith(
                    fontSize: 15,
                    color: onSurface,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.caption.copyWith(
                      color: onSurface.withValues(alpha: 0.65),
                    ),
                  ),
              ],
            ),
          ),
          // ignore: use_null_aware_elements
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// A shimmer placeholder shown while content loads.
class PremiumShimmer extends StatefulWidget {
  const PremiumShimmer({
    super.key,
    this.width = double.infinity,
    this.height = 60,
    this.borderRadius = FluentRadius.control,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  State<PremiumShimmer> createState() => _PremiumShimmerState();
}

class _PremiumShimmerState extends State<PremiumShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _animation = Tween<double>(begin: -1.5, end: 1.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF2A2A3A)
        : const Color(0xFFE8ECF0);
    final highlightColor = isDark
        ? const Color(0xFF3A3A50)
        : const Color(0xFFF5F5F8);

    return AnimatedBuilder(
      animation: _animation,
      builder: (_, _) => ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value + 1, 0),
              colors: [baseColor, highlightColor, baseColor],
            ),
          ),
        ),
      ),
    );
  }
}

/// A Fluent badge — a 4px-radius tinted backplate, not a pill. Used for
/// counts and short status words.
class PremiumTag extends StatelessWidget {
  const PremiumTag({super.key, required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.s,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: FluentLayer.subtle(c, theme.brightness),
        borderRadius: FluentRadius.controlBorder,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: FluentSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentType.caption.copyWith(
                color: c,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A stat tile — icon backplate, value, label.
class PremiumStatTile extends StatelessWidget {
  const PremiumStatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(FluentSpacing.s),
          decoration: BoxDecoration(
            color: FluentLayer.subtle(c, theme.brightness),
            borderRadius: FluentRadius.controlBorder,
          ),
          child: Icon(icon, color: c, size: 20),
        ),
        const SizedBox(height: FluentSpacing.xs + 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FluentType.subtitle.copyWith(fontSize: 18, color: c),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: FluentType.caption.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
      ],
    );
  }
}
