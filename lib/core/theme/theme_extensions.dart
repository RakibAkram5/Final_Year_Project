import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color inputFill;

  /// Accent colour for *text* and small icons. The brand cyan is unreadable
  /// on white (1.45:1), so light mode uses a darker teal (about 5:1).
  final Color accentText;

  const AppColorsExtension({
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.inputFill,
    required this.accentText,
  });

  @override
  AppColorsExtension copyWith({
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? inputFill,
    Color? accentText,
  }) {
    return AppColorsExtension(
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      border: border ?? this.border,
      inputFill: inputFill ?? this.inputFill,
      accentText: accentText ?? this.accentText,
    );
  }

  @override
  AppColorsExtension lerp(ThemeExtension<AppColorsExtension>? other, double t) {
    if (other is! AppColorsExtension) return this;
    return AppColorsExtension(
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
    );
  }

  static const dark = AppColorsExtension(
    textPrimary: AppColors.textPrimaryDark,
    textSecondary: AppColors.textSecondaryDark,
    textMuted: AppColors.textMutedDark,
    surface: AppColors.surfaceDark,
    surfaceAlt: AppColors.surfaceAltDark,
    border: AppColors.borderDark,
    inputFill: AppColors.inputFillDark,
    accentText: AppColors.accent,
  );

  static const light = AppColorsExtension(
    textPrimary: AppColors.textPrimaryLight,
    textSecondary: AppColors.textSecondaryLight,
    textMuted: AppColors.textMutedLight,
    surface: AppColors.surfaceLight,
    surfaceAlt: AppColors.surfaceAltLight,
    border: AppColors.borderLight,
    inputFill: AppColors.inputFillLight,
    accentText: Color(0xFF0B7A75),
  );
}

extension AppThemeX on BuildContext {
  AppColorsExtension get appColors =>
      Theme.of(this).extension<AppColorsExtension>()!;
}
