import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'user_theme_preference';

  ThemeMode _themeMode = ThemeMode.system;

  /// Set once the user picks a theme, so a slower initial load of the saved
  /// preference can never overwrite that choice.
  bool _userChoseTheme = false;

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString(_themeKey);

    if (savedTheme != null && !_userChoseTheme) {
      final mode = ThemeMode.values.firstWhere(
        (e) => e.name == savedTheme,
        orElse: () => ThemeMode.system,
      );
      if (_themeMode != mode) {
        _themeMode = mode;
        notifyListeners();
      }
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _userChoseTheme = true;
    if (_themeMode == mode) return;

    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }
}
