import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// 液态玻璃卡片（浅色）：白玻璃 + 背景模糊 + 柔和蓝影 + 渐变描边
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final double blur;
  final Color fill;
  final double borderOpacity;
  final bool glow;
  final VoidCallback? onTap;
  final Gradient? borderGradient;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.radius = Tokens.radiusLg,
    this.blur = 20,
    this.fill = Tokens.glassFill,
    this.borderOpacity = 0.65,
    this.glow = false,
    this.onTap,
    this.borderGradient,
  });

  @override
  Widget build(BuildContext context) {
    final border = borderGradient ??
        const LinearGradient(colors: [
          Color(0xE6FFFFFF),
          Color(0x8CFFFFFF),
        ]);
    final glowShadow = [
      BoxShadow(
        color: Tokens.shadow,
        blurRadius: glow ? 30 : 18,
        spreadRadius: glow ? -4 : -8,
        offset: const Offset(0, 8),
      ),
    ];

    final inner = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.85),
                fill,
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: borderOpacity),
            ),
          ),
          child: child,
        ),
      ),
    );

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: glowShadow,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius + 1.5),
          gradient: border,
        ),
        child: Padding(
          padding: const EdgeInsets.all(1.2),
          child: onTap != null
              ? GestureDetector(onTap: onTap, child: inner)
              : inner,
        ),
      ),
    );
  }
}
