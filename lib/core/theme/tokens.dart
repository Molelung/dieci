import 'package:flutter/material.dart';

class Tokens {
  Tokens._();

  static const Color bg = Color(0xFF0E0E16);
  static const Color bgDeep = Color(0xFF08080D);

  static const Color brandPink = Color(0xFFFB7299);
  static const Color brandBlue = Color(0xFF00AEEC);
  static const Color brandViolet = Color(0xFF7B6CFF);
  static const Color brandCyan = Color(0xFF35E0D0);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandPink, brandViolet, brandBlue],
  );

  static const Color textPrimary = Color(0xFFF5F5FA);
  static const Color textSecondary = Color(0xFF9A9AB0);
  static const Color textTertiary = Color(0xFF6A6A80);

  static const Color glassFill = Color(0x14FFFFFF); // 8%
  static const Color glassFillStrong = Color(0x1FFFFFFF); // 12%
  static const Color glassStroke = Color(0x33FFFFFF); // 20%
  static const Color glassStrokeSoft = Color(0x1FFFFFFF);

  static const Color success = Color(0xFF4CD68C);
  static const Color danger = Color(0xFFFF6B81);

  static const double radiusLg = 20;
  static const double radiusMd = 14;
  static const double radiusSm = 10;

  static const Duration spring = Duration(milliseconds: 350);
  static const Curve springCurve = Curves.easeOutBack;
}

/// 笔记本封面渐变库（哔哩粉蓝系）
const List<List<Color>> notebookGradients = [
  [Color(0xFFFB7299), Color(0xFF00AEEC)],
  [Color(0xFF7B6CFF), Color(0xFF00AEEC)],
  [Color(0xFFFB7299), Color(0xFFFF9A62)],
  [Color(0xFF35E0D0), Color(0xFF00AEEC)],
  [Color(0xFF8A5CFF), Color(0xFFFB7299)],
  [Color(0xFF2B9CFF), Color(0xFF35E0D0)],
];

LinearGradient notebookGradient(int index) {
  final colors = notebookGradients[index % notebookGradients.length];
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: colors,
  );
}
