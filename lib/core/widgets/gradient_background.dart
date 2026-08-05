import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// 玻璃背后的「世界」：蓝白天光 + 柔和漂浮的浅蓝光斑
class GradientBackground extends StatefulWidget {
  final Widget child;

  const GradientBackground({super.key, required this.child});

  @override
  State<GradientBackground> createState() => _GradientBackgroundState();
}

class _GradientBackgroundState extends State<GradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(seconds: 90))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Tokens.bgDeep, Tokens.bg, Tokens.bgDeep],
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value * 2 * math.pi;
            return LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                if (w == 0 || h == 0) return const SizedBox.shrink();
                return Stack(
                  children: [
                    _blob(
                      w: w,
                      h: h,
                      color: Tokens.brandSky,
                      center: Offset(
                        0.25 + 0.18 * math.sin(t * 0.7),
                        0.22 + 0.15 * math.cos(t * 0.9),
                      ),
                      radius: 0.5,
                      opacity: 0.30,
                    ),
                    _blob(
                      w: w,
                      h: h,
                      color: Tokens.brandCyan,
                      center: Offset(
                        0.80 + 0.16 * math.cos(t * 0.6),
                        0.32 + 0.18 * math.sin(t * 0.8),
                      ),
                      radius: 0.42,
                      opacity: 0.18,
                    ),
                    _blob(
                      w: w,
                      h: h,
                      color: Tokens.brandIndigo,
                      center: Offset(
                        0.55 + 0.2 * math.sin(t * 0.5 + 1.2),
                        0.88 + 0.12 * math.cos(t * 0.7 + 0.6),
                      ),
                      radius: 0.4,
                      opacity: 0.14,
                    ),
                    _blob(
                      w: w,
                      h: h,
                      color: Colors.white,
                      center: Offset(
                        0.10 + 0.1 * math.cos(t * 0.4),
                        0.70 + 0.1 * math.sin(t * 0.6 + 2.0),
                      ),
                      radius: 0.3,
                      opacity: 0.5,
                    ),
                  ],
                );
              },
            );
          },
        ),
        widget.child,
      ],
    );
  }

  Widget _blob({
    required double w,
    required double h,
    required Color color,
    required Offset center,
    required double radius,
    required double opacity,
  }) {
    return Positioned(
      left: center.dx * w - radius * w / 2,
      top: center.dy * h - radius * h / 2,
      child: Container(
        width: radius * w,
        height: radius * h,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: opacity), Colors.transparent],
          ),
        ),
      ),
    );
  }
}
