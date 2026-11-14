import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/ui_style_provider.dart';

/// The backdrop painted behind a scaffold body.
///
/// What it actually draws depends on the active [AppUiStyle]:
///
/// * [AppUiStyle.classic] — nothing but the flat scaffold colour. No
///   animation controller is driven at all, so it costs nothing.
/// * [AppUiStyle.mica] — one still, very subtle accent tint, the way
///   Windows 11 Mica tints a window background.
/// * [AppUiStyle.acrylic] — the full animated gradient that slowly shifts.
///
/// Usage:
/// ```dart
/// Scaffold(
///   body: AnimatedGradientBackground(child: YourContent()),
/// )
/// ```
class AnimatedGradientBackground extends ConsumerStatefulWidget {
  const AnimatedGradientBackground({
    super.key,
    required this.child,
    this.duration = const Duration(seconds: 8),
  });

  final Widget child;

  /// How long one gradient cycle takes (slower = more relaxing).
  final Duration duration;

  @override
  ConsumerState<AnimatedGradientBackground> createState() =>
      _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState
    extends ConsumerState<AnimatedGradientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Keeps the ticker off unless the active style actually animates, so
  /// Classic and Mica never wake the raster thread 60 times a second.
  ///
  /// Deferred to after the frame: stopping the controller resets its value,
  /// which notifies the [AnimatedBuilder] that is still mounted from the
  /// previous style — calling that synchronously inside build would be a
  /// setState-during-build error.
  void _syncTicker(bool shouldAnimate) {
    if (shouldAnimate == _controller.isAnimating) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (shouldAnimate) {
        if (!_controller.isAnimating) _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = 0.0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = ref.watch(appUiStyleProvider);
    final scaffold = Theme.of(context).scaffoldBackgroundColor;

    _syncTicker(style.usesMotion);

    if (!style.usesBackdropTint) {
      return ColoredBox(color: scaffold, child: widget.child);
    }

    final colorScheme = Theme.of(context).colorScheme;

    if (!style.usesMotion) {
      // Mica: a single still tint. Kept weaker than Acrylic's so text on top
      // of it stays at full contrast without any blur layer to lift it.
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(scaffold, colorScheme.primary, 0.12) ?? scaffold,
              Color.lerp(scaffold, colorScheme.secondary, 0.07) ?? scaffold,
              scaffold,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        final t = _controller.value;
        // Stronger presence: primary orb moves diagonally, secondary follows
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(math.cos(t * math.pi) * 0.8 - 0.6, -1.0),
              end: Alignment(math.sin(t * math.pi) * 0.8 + 0.2, 1.0),
              colors: [
                // Primary glow — noticeably tinted
                Color.lerp(scaffold, colorScheme.primary, 0.22 + t * 0.12) ??
                    scaffold,
                // Secondary tint at center
                Color.lerp(
                      scaffold,
                      colorScheme.secondary,
                      0.14 + (1 - t) * 0.08,
                    ) ??
                    scaffold,
                // Plain scaffold at the edges
                scaffold,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Floating orb accent — a large, blurry, low-opacity circle that drifts
/// very gently, adding depth and atmosphere to the background.
///
/// Draws nothing in [AppUiStyle.classic], and sits still (no drift) in
/// [AppUiStyle.mica].
///
/// Place inside a [Stack] behind your content.
///
/// ```dart
/// Stack(children: [
///   AnimatedGradientBackground(child: content),
///   const FloatingOrb(top: 60, left: -40, size: 220),
///   const FloatingOrb(bottom: 100, right: -60, size: 180),
/// ])
/// ```
class FloatingOrb extends ConsumerStatefulWidget {
  const FloatingOrb({
    super.key,
    this.top,
    this.bottom,
    this.left,
    this.right,
    this.size = 200,
    this.opacity = 0.12,
  });

  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final double size;
  final double opacity;

  @override
  ConsumerState<FloatingOrb> createState() => _FloatingOrbState();
}

class _FloatingOrbState extends ConsumerState<FloatingOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _drift;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    _drift = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 12),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// See the note on the backdrop's `_syncTicker`: deferred so a style
  /// change never resets the controller in the middle of a build.
  void _syncTicker(bool shouldAnimate) {
    if (shouldAnimate == _controller.isAnimating) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (shouldAnimate) {
        if (!_controller.isAnimating) _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = 0.0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = ref.watch(appUiStyleProvider);

    _syncTicker(style.usesMotion);

    if (!style.usesBackdropTint) {
      return const SizedBox.shrink();
    }

    final primary = Theme.of(context).colorScheme.primary;
    // Mica keeps the depth cue but dials it right back — Windows' Mica is a
    // hint of colour, not a glow.
    final opacity = style.usesMotion ? widget.opacity : widget.opacity * 0.55;

    final orb = RepaintBoundary(
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              primary.withValues(alpha: opacity),
              primary.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );

    return Positioned(
      top: widget.top,
      bottom: widget.bottom,
      left: widget.left,
      right: widget.right,
      child: style.usesMotion
          ? AnimatedBuilder(
              animation: _drift,
              builder: (_, _) =>
                  Transform.translate(offset: _drift.value, child: orb),
            )
          : orb,
    );
  }
}
