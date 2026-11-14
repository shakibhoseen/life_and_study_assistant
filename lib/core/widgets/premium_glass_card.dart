import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/fluent_tokens.dart';
import '../theme/ui_style_provider.dart';

/// A Fluent card: a solid layer on top of the window backdrop, defined by a
/// 1px stroke and an 8px radius rather than by a shadow.
///
/// Only [AppUiStyle.acrylic] frosts it. Classic and Mica both render a solid
/// surface, because in Windows 11 it is the *window* that is tinted, not the
/// content sitting on it.
///
/// Usage:
/// ```dart
/// PremiumGlassCard(
///   child: Text('Hello'),
/// )
/// ```
class PremiumGlassCard extends ConsumerWidget {
  const PremiumGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(FluentSpacing.l),
    this.borderRadius = FluentRadius.card,
    this.blurSigma = 10.0,
    this.margin,
    this.height,
    this.width,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  /// How strong the backdrop blur is, in Acrylic only. Keep ≤ 12.
  final double blurSigma;

  final EdgeInsetsGeometry? margin;
  final double? height;
  final double? width;

  /// When set the whole card becomes the hit target, with a Fluent press
  /// ripple clipped to the card's radius.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(appUiStyleProvider);
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(borderRadius);

    // Acrylic is the only style that lets the backdrop through. Elsewhere the
    // card is a solid layer — Fluent's "Layer on Mica", not frosted glass.
    final surfaceColor = style.usesAcrylic
        ? scheme.surface.withValues(alpha: 0.72)
        : (theme.cardTheme.color ?? theme.cardColor);

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: radius,
        border: Border.all(
          color: FluentStroke.card(brightness),
          width: FluentStroke.width,
        ),
      ),
      child: child,
    );

    if (onTap != null) {
      content = Stack(
        children: [
          content,
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(borderRadius: radius, onTap: onTap),
            ),
          ),
        ],
      );
    }

    if (style.usesAcrylic) {
      content = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: content,
      );
    }

    return RepaintBoundary(
      child: Container(
        height: height,
        width: width,
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: FluentElevation.card(brightness),
        ),
        child: ClipRRect(borderRadius: radius, child: content),
      ),
    );
  }
}

/// A Fluent icon backplate: a rounded *square*, not a circle, filled with the
/// accent at low opacity. Windows 11 uses this shape for list and nav icons;
/// the previous circular badge with an outer glow was not a Fluent idiom.
class PremiumIconBadge extends StatelessWidget {
  const PremiumIconBadge({
    super.key,
    required this.icon,
    this.size = 40,
    this.iconSize = 20,
    this.color,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: FluentLayer.subtle(c, theme.brightness),
          borderRadius: FluentRadius.controlBorder,
        ),
        child: Icon(icon, size: iconSize, color: c),
      ),
    );
  }
}

/// A Fluent accent button: flat accent fill, 4px radius, no gradient and no
/// glow. The press state darkens the fill instead of scaling the button,
/// which is how WinUI's AccentButton behaves.
class PremiumButton extends StatefulWidget {
  const PremiumButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.width,
    this.compact = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final double? width;

  /// Trailing actions inside a dense card. Keeps the button from eating the
  /// row's width and squeezing the text beside it.
  final bool compact;

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = _pressed
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.16), scheme.primary)
        : scheme.primary;

    final labelStyle = FluentType.bodyStrong.copyWith(
      color: scheme.onPrimary,
      fontSize: widget.compact ? 13 : 14,
    );

    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: widget.width,
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? FluentSpacing.m : FluentSpacing.l,
            vertical: widget.compact ? 7 : FluentSpacing.s,
          ),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: FluentRadius.controlBorder,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  color: scheme.onPrimary,
                  size: widget.compact ? 14 : 16,
                ),
                const SizedBox(width: FluentSpacing.xs + 2),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
