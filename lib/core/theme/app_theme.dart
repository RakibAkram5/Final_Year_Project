import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'theme_extensions.dart';

class AppTheme {
  AppTheme._();

  static final ThemeData dark = _buildDark();

  static ThemeData _buildDark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      extensions: [AppColorsExtension.dark],
      scaffoldBackgroundColor: AppColors.bgBottomDark,
      primaryColor: AppColors.accent,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        secondary: AppColors.accent,
        surface: AppColors.surfaceDark,
        surfaceContainerHighest: AppColors.surfaceAltDark,
        error: AppColors.danger,
        onPrimary: AppColors.textOnAccent,
        onSurface: AppColors.textPrimaryDark,
        outline: AppColors.borderDark,
        // Material 3 tints elevated surfaces (Card/AppBar-on-scroll/Dialog)
        // with `primary` by default — since primary is the bright cyan
        // accent, that shows up as an unwanted color cast on every raised
        // surface. Disabling it keeps elevation purely shadow-based.
        surfaceTint: Colors.transparent,
      ),
      textTheme: _textTheme(base.textTheme, AppColors.textPrimaryDark,
          AppColors.textSecondaryDark),
      appBarTheme: _appBarTheme(AppColors.textPrimaryDark),
      cardTheme: _cardTheme(AppColors.surfaceDark, AppColors.borderDark),
      dialogTheme: _dialogTheme(AppColors.surfaceAltDark),
      listTileTheme: _listTileTheme(AppColors.textPrimaryDark),
      dividerTheme:
          const DividerThemeData(color: AppColors.borderDark, thickness: 1),
      chipTheme:
          _chipTheme(AppColors.surfaceAltDark, AppColors.textPrimaryDark),
      navigationBarTheme: _navigationBarTheme(
          AppColors.surfaceDark, AppColors.textSecondaryDark),
      elevatedButtonTheme: _elevatedButtonTheme(),
      filledButtonTheme: _filledButtonTheme(),
      outlinedButtonTheme:
          _outlinedButtonTheme(AppColors.accent, AppColors.borderDark),
      iconTheme: const IconThemeData(color: AppColors.textPrimaryDark),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputFillDark,
        hintStyle: const TextStyle(color: AppColors.textMutedDark),
        labelStyle: const TextStyle(color: AppColors.textSecondaryDark),
        floatingLabelStyle: const TextStyle(color: AppColors.accent),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: _inputBorder(AppColors.borderDark),
        enabledBorder: _inputBorder(AppColors.borderDark),
        focusedBorder: _inputBorder(AppColors.accent, width: 1.4),
        errorBorder: _inputBorder(AppColors.danger),
        focusedErrorBorder: _inputBorder(AppColors.danger, width: 1.4),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.accent,
        selectionColor: AppColors.accent,
        selectionHandleColor: AppColors.accent,
      ),
      snackBarTheme:
          _snackBarTheme(AppColors.surfaceAltDark, AppColors.textPrimaryDark),
    );
  }

  static final ThemeData light = _buildLight();

  static ThemeData _buildLight() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      extensions: [AppColorsExtension.light],
      scaffoldBackgroundColor: AppColors.bgBottomLight,
      primaryColor: AppColors.accent,
      colorScheme: const ColorScheme.light(
        primary: AppColors.accent,
        secondary: AppColors.accentDark,
        surface: AppColors.surfaceLight,
        surfaceContainerHighest: AppColors.surfaceAltLight,
        error: AppColors.danger,
        onPrimary: AppColors.textOnAccent,
        onSurface: AppColors.textPrimaryLight,
        outline: AppColors.borderLight,
        // See the matching comment in `dark` — removes MD3's default cyan
        // elevation tint on cards/AppBar/dialogs in light mode too.
        surfaceTint: Colors.transparent,
      ),
      textTheme: _textTheme(base.textTheme, AppColors.textPrimaryLight,
          AppColors.textSecondaryLight),
      appBarTheme: _appBarTheme(AppColors.textPrimaryLight),
      cardTheme: _cardTheme(AppColors.surfaceLight, AppColors.borderLight),
      dialogTheme: _dialogTheme(AppColors.surfaceLight),
      listTileTheme: _listTileTheme(AppColors.textPrimaryLight),
      dividerTheme:
          const DividerThemeData(color: AppColors.borderLight, thickness: 1),
      chipTheme:
          _chipTheme(AppColors.surfaceAltLight, AppColors.textPrimaryLight),
      navigationBarTheme: _navigationBarTheme(
          AppColors.surfaceLight, AppColors.textSecondaryLight),
      elevatedButtonTheme: _elevatedButtonTheme(),
      filledButtonTheme: _filledButtonTheme(),
      outlinedButtonTheme:
          _outlinedButtonTheme(AppColors.accentDark, AppColors.borderLight),
      iconTheme: const IconThemeData(color: AppColors.textPrimaryLight),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputFillLight,
        hintStyle: const TextStyle(color: AppColors.textMutedLight),
        labelStyle: const TextStyle(color: AppColors.textSecondaryLight),
        floatingLabelStyle: const TextStyle(color: AppColors.accentDark),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: _inputBorder(AppColors.borderLight),
        enabledBorder: _inputBorder(AppColors.borderLight),
        focusedBorder: _inputBorder(AppColors.accentDark, width: 1.4),
        errorBorder: _inputBorder(AppColors.danger),
        focusedErrorBorder: _inputBorder(AppColors.danger, width: 1.4),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.accentDark,
        selectionColor: AppColors.accent.withValues(alpha: 0.3),
        selectionHandleColor: AppColors.accentDark,
      ),
      snackBarTheme:
          _snackBarTheme(AppColors.surfaceAltLight, AppColors.textPrimaryLight),
    );
  }

  static TextTheme _textTheme(TextTheme base, Color primary, Color secondary) {
    return base.apply(bodyColor: primary, displayColor: primary).copyWith(
          titleLarge: base.titleLarge
              ?.copyWith(color: primary, fontWeight: FontWeight.w700),
          titleMedium: base.titleMedium
              ?.copyWith(color: primary, fontWeight: FontWeight.w600),
          bodyMedium: base.bodyMedium?.copyWith(color: secondary),
          bodySmall: base.bodySmall?.copyWith(color: secondary),
        );
  }

  static AppBarTheme _appBarTheme(Color textColor) => AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textColor,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: textColor),
      );

  static CardThemeData _cardTheme(Color surface, Color border) => CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border.withValues(alpha: 0.6)),
        ),
        margin: EdgeInsets.zero,
      );

  static DialogThemeData _dialogTheme(Color surface) => DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );

  static ListTileThemeData _listTileTheme(Color textColor) => ListTileThemeData(
        iconColor: AppColors.accent,
        textColor: textColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      );

  static ChipThemeData _chipTheme(Color background, Color textColor) =>
      ChipThemeData(
        backgroundColor: background,
        selectedColor: AppColors.accent.withValues(alpha: 0.2),
        labelStyle: TextStyle(color: textColor, fontSize: 12),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      );

  static NavigationBarThemeData _navigationBarTheme(
          Color background, Color unselected) =>
      NavigationBarThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.accent.withValues(alpha: 0.18),
        elevation: 2,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.accentDark : unselected,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
              color: selected ? AppColors.accentDark : unselected);
        }),
      );

  static ElevatedButtonThemeData _elevatedButtonTheme() =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.textOnAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          minimumSize: const Size(0, 42),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  static FilledButtonThemeData _filledButtonTheme() => FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.textOnAccent,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          minimumSize: const Size(0, 42),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  static OutlinedButtonThemeData _outlinedButtonTheme(
          Color foreground, Color border) =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          minimumSize: const Size(0, 42),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  static SnackBarThemeData _snackBarTheme(Color surface, Color content) =>
      SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(color: content),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
