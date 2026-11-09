import 'package:flutter/material.dart';
import '../core/theme/theme_extensions.dart';
import 'package:provider/provider.dart';

import '../logic/theme_provider.dart';
import 'responsive/responsive_action_tile.dart';
import 'theme_toggle_widget.dart';

/// App-bar actions shared by the four portal dashboards.
///
/// The notification bell always stays visible; academy info, security,
/// theme and logout collapse into a "More options" menu when the screen is
/// too narrow to show them next to a readable title.
List<Widget> dashboardAppBarActions(
  BuildContext context, {
  required Widget notificationBell,
  required VoidCallback onSecurity,
  required VoidCallback onLogout,
  VoidCallback? onAcademyInfo,
}) {
  return responsiveAppBarActions(context, [
    AppBarActionSpec.pinned(notificationBell),
    if (onAcademyInfo != null)
      AppBarActionSpec.collapsible(
        inline: IconButton(
          icon:
              Icon(Icons.business_rounded, color: context.appColors.accentText),
          tooltip: 'Academy info',
          onPressed: onAcademyInfo,
        ),
        menu: TileAction(
            icon: Icons.business_rounded,
            label: 'Academy info',
            onPressed: onAcademyInfo),
      ),
    AppBarActionSpec.collapsible(
      inline: IconButton(
        icon: Icon(Icons.security_rounded, color: context.appColors.accentText),
        tooltip: 'Security settings',
        onPressed: onSecurity,
      ),
      menu: TileAction(
          icon: Icons.security_rounded,
          label: 'Security settings',
          onPressed: onSecurity),
    ),
    AppBarActionSpec.collapsible(
      inline: const ThemeToggle(),
      menu: TileAction(
        icon: Icons.brightness_6_rounded,
        label: 'Theme',
        onPressed: () => showThemePicker(context),
      ),
    ),
    AppBarActionSpec.collapsible(
      inline: IconButton(
        icon:
            Icon(Icons.logout_rounded, color: context.appColors.textSecondary),
        tooltip: 'Log out',
        onPressed: onLogout,
      ),
      menu: TileAction(
          icon: Icons.logout_rounded,
          label: 'Log out',
          color: context.appColors.textSecondary,
          onPressed: onLogout),
    ),
  ]);
}

/// Theme chooser used when the inline theme toggle is collapsed.
Future<void> showThemePicker(BuildContext context) async {
  final provider = context.read<ThemeProvider>();
  final mode = await showDialog<ThemeMode>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Theme'),
      children: [
        for (final entry in const [
          (ThemeMode.light, Icons.light_mode_rounded, 'Light mode'),
          (ThemeMode.dark, Icons.dark_mode_rounded, 'Dark mode'),
          (ThemeMode.system, Icons.brightness_auto_rounded, 'System default'),
        ])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, entry.$1),
            child: Row(children: [
              Icon(entry.$2,
                  size: 20,
                  color: provider.themeMode == entry.$1
                      ? context.appColors.accentText
                      : null),
              const SizedBox(width: 12),
              Expanded(child: Text(entry.$3)),
            ]),
          ),
      ],
    ),
  );
  if (mode != null) await provider.setThemeMode(mode);
}
