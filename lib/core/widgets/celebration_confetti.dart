import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A lightweight, 60fps native Flutter celebration confetti burst widget.
/// Zero external package dependencies, highly performant, auto-disposing.
class CelebrationConfetti extends StatefulWidget {
  final Widget child;
  final bool trigger;
  final Duration duration;

  const CelebrationConfetti({
    super.key,
    required this.child,
    this.trigger = true,
    this.duration = const Duration(milliseconds: 2500),
  });

  @override
  State<CelebrationConfetti> createState() => _CelebrationConfettiState();
}

class _CelebrationConfettiState extends State<CelebrationConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<ConfettiParticle> _particles = [];
  final math.Random _random = math.Random();

  static const List<Color> _confettiColors = [
    Color(0xFFFF5252), // Vibrant Red
    Color(0xFFFFD700), // Gold
    Color(0xFF4CAF50), // Green
    Color(0xFF2196F3), // Blue
    Color(0xFF9C27B0), // Purple
    Color(0xFFFF9800), // Orange
    Color(0xFF00E5FF), // Cyan
    Color(0xFFFF4081), // Pink
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    if (widget.trigger) {
      _spawnParticles();
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant CelebrationConfetti oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger && !oldWidget.trigger) {
      _spawnParticles();
      _controller.reset();
      _controller.forward();
    }
  }

  void _spawnParticles() {
    _particles.clear();
    const int count = 45;
    for (int i = 0; i < count; i++) {
      final color = _confettiColors[_random.nextInt(_confettiColors.length)];
      final double angle = -math.pi / 2 + (_random.nextDouble() - 0.5) * 1.5;
      final double speed = 250.0 + _random.nextDouble() * 380.0;
      final double size = 6.0 + _random.nextDouble() * 6.0;
      final double rotationSpeed = (_random.nextDouble() - 0.5) * 12.0;
      final double flutterSpeed = 3.0 + _random.nextDouble() * 5.0;
      final bool isCircle = _random.nextBool();

      _particles.add(
        ConfettiParticle(
          color: color,
          dx: math.cos(angle) * speed,
          dy: math.sin(angle) * speed,
          size: size,
          rotationSpeed: rotationSpeed,
          flutterSpeed: flutterSpeed,
          isCircle: isCircle,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            if (!_controller.isAnimating &&
                (_controller.isDismissed || _controller.isCompleted)) {
              return const SizedBox.shrink();
            }
            return Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: ConfettiPainter(
                    progress: _controller.value,
                    particles: _particles,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class ConfettiParticle {
  final Color color;
  final double dx;
  final double dy;
  final double size;
  final double rotationSpeed;
  final double flutterSpeed;
  final bool isCircle;

  ConfettiParticle({
    required this.color,
    required this.dx,
    required this.dy,
    required this.size,
    required this.rotationSpeed,
    required this.flutterSpeed,
    required this.isCircle,
  });
}

class ConfettiPainter extends CustomPainter {
  final double progress;
  final List<ConfettiParticle> particles;

  ConfettiPainter({required this.progress, required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1.0) return;

    final double gravity = 480.0; // Gravity pulling downward
    final double originX = size.width / 2;
    final double originY = size.height * 0.35; // Center-upper burst

    final double opacity = (1.0 - progress * progress).clamp(0.0, 1.0);

    for (final p in particles) {
      final double t = progress;
      final double x = originX + p.dx * t;
      final double y = originY + p.dy * t + 0.5 * gravity * t * t;

      final double rotation = t * p.rotationSpeed;
      final double scaleX = math.cos(t * p.flutterSpeed);

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      canvas.scale(scaleX.abs().clamp(0.15, 1.0), 1.0);

      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size,
              height: p.size * 0.6,
            ),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant ConfettiPainter oldDelegate) => true;
}
