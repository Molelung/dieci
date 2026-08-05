import 'package:flutter/material.dart';
import 'tokens.dart';

ThemeData buildAppTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: Tokens.bg,
    colorScheme: const ColorScheme.dark(
      primary: Tokens.brandPink,
      secondary: Tokens.brandBlue,
      surface: Tokens.bg,
      error: Tokens.danger,
    ),
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Tokens.textPrimary,
      displayColor: Tokens.textPrimary,
    ),
    dividerColor: Colors.white10,
    splashFactory: NoSplash.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Tokens.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xEE1C1C28),
      contentTextStyle: const TextStyle(color: Tokens.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
