import 'package:flutter/material.dart';
import '../core/theme/theme_extensions.dart';
import 'package:provider/provider.dart';
import '../logic/theme_provider.dart';
import '../core/theme/app_colors.dart';

class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;

    return PopupMenuButton<ThemeMode>(
      icon: Icon(
        _getIcon(themeProvider.themeMode),
        color:
            isDark ? context.appColors.accentText : AppColors.textPrimaryLight,
      ),
      onSelected: (ThemeMode mode) => themeProvider.setThemeMode(mode),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: ThemeMode.light,
          child: Row(
            children: [
              Icon(Icons.light_mode_rounded, color: Colors.orange, size: 20),
              SizedBox(width: 10),
              Text('Light Mode'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: ThemeMode.dark,
          child: Row(
            children: [
              Icon(Icons.dark_mode_rounded,
                  color: Colors.indigoAccent, size: 20),
              SizedBox(width: 10),
              Text('Dark Mode'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: ThemeMode.system,
          child: Row(
            children: [
              Icon(Icons.brightness_auto_rounded,
                  color: Colors.blueGrey, size: 20),
              SizedBox(width: 10),
              Text('System Default'),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_rounded;
      case ThemeMode.dark:
        return Icons.dark_mode_rounded;
      case ThemeMode.system:
        return Icons.brightness_auto_rounded;
    }
  }
}
