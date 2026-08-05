import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// 空态插画：渐变圆 + 光晕环 + 主题图标（蓝白系）
class HeroArt extends StatelessWidget {
  final IconData icon;
  final double size;

  const HeroArt({super.key, required this.icon, this.size = 92});

  @override
  Widget build(BuildContext context) {
    final s = size;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 外圈光晕
          Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Tokens.brandSky.withValues(alpha: 0.25),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // 半透明环
          Container(
            width: s * 0.78,
            height: s * 0.78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Tokens.brandBlue.withValues(alpha: 0.18),
                width: 2,
              ),
            ),
          ),
          // 主渐变圆
          Container(
            width: s * 0.58,
            height: s * 0.58,
            decoration: BoxDecoration(
              gradient: Tokens.brandGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Tokens.brandBlue.withValues(alpha: 0.35),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: s * 0.30),
          ),
          // 装饰小点
          Positioned(
            top: s * 0.08,
            right: s * 0.10,
            child: Container(
              width: s * 0.08,
              height: s * 0.08,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Tokens.brandCyan.withValues(alpha: 0.5),
              ),
            ),
          ),
          Positioned(
            bottom: s * 0.10,
            left: s * 0.06,
            child: Container(
              width: s * 0.06,
              height: s * 0.06,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Tokens.brandSky.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
