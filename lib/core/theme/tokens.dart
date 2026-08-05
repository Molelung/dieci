import 'package:flutter/material.dart';

/// 蓝白浅色设计令牌（0.0.2 改版）
class Tokens {
  Tokens._();

  // 背景：蓝白系
  static const Color bg = Color(0xFFF3F8FF);
  static const Color bgDeep = Color(0xFFE6F1FE);

  // 品牌：蓝色系
  static const Color brandBlue = Color(0xFF2E7CF6);
  static const Color brandSky = Color(0xFF5AC8FA);
  static const Color brandCyan = Color(0xFF00B8D9);
  static const Color brandIndigo = Color(0xFF4F6EF7);
  static const Color accentWarm = Color(0xFFFF8A5C); // 少量暖色点缀

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandSky, brandBlue, brandIndigo],
  );

  // 文字
  static const Color textPrimary = Color(0xFF1B2D4E);
  static const Color textSecondary = Color(0xFF5B76A0);
  static const Color textTertiary = Color(0xFF8CA6C9);

  // 玻璃（浅色）：白玻璃 + 蓝影
  static const Color glassFill = Color(0xB3FFFFFF); // 70%
  static const Color glassFillStrong = Color(0xE6FFFFFF); // 90%
  static const Color glassStroke = Color(0xA6FFFFFF); // 65%
  static const Color glassStrokeSoft = Color(0x66FFFFFF);

  static Color shadow = brandBlue.withValues(alpha: 0.12);

  // 状态色
  static const Color success = Color(0xFF2FBF7F);
  static const Color danger = Color(0xFFFF5B74);
  static const Color warn = Color(0xFFFFA940);

  static const double radiusLg = 20;
  static const double radiusMd = 14;
  static const double radiusSm = 10;

  static const Duration spring = Duration(milliseconds: 350);
  static const Curve springCurve = Curves.easeOutBack;
}

/// 笔记本封面渐变库（蓝白主色 + 少量柔和的蓝紫青点缀）
const List<List<Color>> notebookGradients = [
  [Color(0xFF5AC8FA), Color(0xFF2E7CF6)],
  [Color(0xFF4F6EF7), Color(0xFF2E7CF6)],
  [Color(0xFF00B8D9), Color(0xFF5AC8FA)],
  [Color(0xFF2E7CF6), Color(0xFF00B8D9)],
  [Color(0xFF7A8CFF), Color(0xFF5AC8FA)],
  [Color(0xFF3E9BFF), Color(0xFF00B8D9)],
];

LinearGradient notebookGradient(int index) {
  final colors = notebookGradients[index % notebookGradients.length];
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: colors,
  );
}
