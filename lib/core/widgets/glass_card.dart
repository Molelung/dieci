import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// 液态玻璃卡片：背景模糊 + 渐变填充 + 半透明描边 + 可选品牌色光晕
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
    this.blur = 18,
    this.fill = Tokens.glassFill,
    this.borderOpacity = 0.20,
    this.glow = false,
    this.onTap,
    this.borderGradient,
  });

  @override
  Widget build(BuildContext context) {
    final border = borderGradient ?? const LinearGradient(colors: [
      Color(0x66FFFFFF),
      Color(0x22FFFFFF),
    ]);
    final glowShadow = glow
        ? [
            BoxShadow(
              color: Tokens.brandPink.withValues(alpha: 0.28),
              blurRadius: 28,
              spreadRadius: -6,
            ),
          ]
        : null;

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
                Colors.white.withValues(alpha: 0.12),
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
