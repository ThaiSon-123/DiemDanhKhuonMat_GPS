import 'package:flutter/material.dart';

/// Token màu theo canvas thiết kế v3 (docs/plan.md, Global Constraints).
abstract final class AppColors {
  static const primary = Color(0xFF4F46E5);
  static const primaryDark = Color(0xFF3730A3);
  static const primarySub = Color(0xFF4338CA);
  static const primarySoft = Color(0xFFEEF2FF);
  static const onPrimaryMuted = Color(0xFFE0E7FF);
  static const background = Color(0xFFF5F6FB);
  static const surfaceMuted = Color(0xFFF4F5FB);
  static const inputFill = Color(0xFFF9FAFD);
  static const text = Color(0xFF1E1B4B);
  static const textMuted = Color(0xFF5B6478);
  static const textSecondary = Color(0xFF3A4458);
  static const border = Color(0xFFE6E8F3);
  static const inputBorder = Color(0xFFD7DBEA);
  static const present = Color(0xFF12803C);
  static const suspicious = Color(0xFFB45309);
  static const absent = Color(0xFFC2261D);
}

ThemeData appTheme() {
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'BeVietnamPro',
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      error: AppColors.absent,
      surface: Colors.white,
      onSurface: AppColors.text,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.inputFill,
      hoverColor: AppColors.inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      enabledBorder: border(AppColors.inputBorder),
      focusedBorder: border(AppColors.primary, 2),
      errorBorder: border(AppColors.absent, 2),
      focusedErrorBorder: border(AppColors.absent, 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        elevation: 6,
        shadowColor: AppColors.primary.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: 'BeVietnamPro', fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
  );
}
