import 'package:flutter/material.dart';

/// Token màu Modern Neo-Widget theo canvas thiết kế (docs/plan.md, Global Constraints).
abstract final class AppColors {
  static const primary = Color(0xFF4F46E5);
  static const primarySoft = Color(0xFFEEF2FF);
  static const focus = Color(0xFF6366F1);
  static const background = Color(0xFFF6F8FC);
  static const hero = Color(0xFF090D16);
  static const heroBorder = Color(0xCC1E293B);
  static const heroText = Color(0xFFCBD5E1);
  static const heroChipText = Color(0xFFE2E8F0);
  static const text = Color(0xFF0F172A);
  static const textLabel = Color(0xFF334155);
  static const textSecondary = Color(0xFF475569);
  static const textMuted = Color(0xFF64748B);
  static const cardBorder = Color(0xFFF1F5F9);
  static const inputBorder = Color(0xFFE2E8F0);
  static const inputFill = Color(0xFFF8FAFC);
  static const present = Color(0xFF10B981);
  static const presentText = Color(0xFF047857);
  static const presentSoft = Color(0xFFECFDF5);
  static const presentBorder = Color(0xFFD1FAE5);
  static const absent = Color(0xFFF43F5E);
  static const absentText = Color(0xFFBE123C);
  static const absentSoft = Color(0xFFFFF1F2);
  static const absentBorder = Color(0xFFFFE4E6);
  static const glowIndigo = Color(0x594F46E5);
  static const glowEmerald = Color(0x3310B981);
}

/// Bề rộng tối đa của nội dung trang web (không tính lề 32 hai bên). Canvas: 1180 ở màn 1280;
/// nới lên để màn Full HD không trống hai bên quá nhiều.
const webContentMaxWidth = 1376.0;

/// Nút chính trong hộp thoại: gọn (nút mặc định của app cao 52 và kéo hết chiều ngang).
final dialogButtonStyle = FilledButton.styleFrom(minimumSize: const Size(96, 44), elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 20));

ThemeData appTheme() {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: c, width: w),
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      error: AppColors.absent,
      surface: Colors.white,
      onSurface: AppColors.text,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      barrierColor: const Color(0x66090D16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: const TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text),
      contentTextStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, height: 20 / 14, color: AppColors.textSecondary),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 520),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(64, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.inputFill,
      hoverColor: AppColors.inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      enabledBorder: border(AppColors.inputBorder),
      focusedBorder: border(AppColors.focus, 2),
      errorBorder: border(AppColors.absent, 2),
      focusedErrorBorder: border(AppColors.absent, 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        elevation: 8,
        shadowColor: AppColors.primary.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ).copyWith(
        // Nút bị vô hiệu không đổ bóng tím (trông như quầng sáng quanh nút xám).
        elevation: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? 0 : 8),
      ),
    ),
  );
}
