import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/web/web_breakpoints.dart';
import '../../core/web/web_theme.dart';
import '../../data/models/app_user.dart';
import '../../logic/auth_provider.dart';
import '../academy_logo.dart';
import 'web_nav_items.dart';
import 'web_topbar.dart';

const double _kExpandedWidth = 264;
const double _kRailWidth = 78;
const String _kCollapsedPrefKey = 'web_sidebar_collapsed';

/// Shared sign-out action for every web screen's account menu — the same
/// sign-out + redirect-to-login logic already duplicated as `_logout` across
/// the four mobile dashboards, factored out once so the ~30 sub-screens
/// don't each need their own copy.
Future<void> performWebLogout(BuildContext context) async {
  await context.read<AuthProvider>().signOut();
  if (context.mounted) {
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (r) => false);
  }
}

/// The persistent SaaS-style chrome for the Flutter Web redesign: a
/// collapsible sidebar (becomes a [Drawer] under [WebBreakpoints.medium]),
/// a fixed top bar, and a width-capped, centered content area. Every screen
/// renders its own instance of this (there is no nested/persistent-route
/// shell — see the plan's "Core safety mechanism" — so this widget is what
/// makes the sidebar *feel* persistent across pushes).
class WebAppShell extends StatefulWidget {
  final String title;
  final IconData titleIcon;
  final List<WebNavSection> navSections;
  final String activeNavId;
  final Widget body;
  final AppUser? user;
  final VoidCallback onLogout;
  final VoidCallback? onSecuritySettings;
  final VoidCallback? onAcademyInfo;
  final EdgeInsetsGeometry? contentPadding;
  final double maxContentWidth;

  const WebAppShell({
    super.key,
    required this.title,
    required this.titleIcon,
    required this.navSections,
    required this.activeNavId,
    required this.body,
    required this.user,
    required this.onLogout,
    this.onSecuritySettings,
    this.onAcademyInfo,
    this.contentPadding,
    this.maxContentWidth = 1600,
  });

  @override
  State<WebAppShell> createState() => _WebAppShellState();
}

class _WebAppShellState extends State<WebAppShell> {
  bool _collapsed = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getBool(_kCollapsedPrefKey);
      if (saved != null && mounted) setState(() => _collapsed = saved);
    });
  }

  void _toggleCollapsed() {
    final next = !_collapsed;
    setState(() => _collapsed = next);
    SharedPreferences.getInstance()
        .then((p) => p.setBool(_kCollapsedPrefKey, next));
  }

  @override
  Widget build(BuildContext context) {
    final webColors = context.webColors;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: WebBreakpoints.isMedium(context)
          ? Drawer(
              backgroundColor: webColors.sidebarBackground,
              child: SafeArea(
                child: _SidebarContent(
                  title: widget.title,
                  titleIcon: widget.titleIcon,
                  navSections: widget.navSections,
                  activeNavId: widget.activeNavId,
                  collapsed: false,
                  user: widget.user,
                  onNavigate: () => Navigator.of(context).maybePop(),
                ),
              ),
            )
          : null,
      body: LayoutBuilder(builder: (context, constraints) {
        final showSidebar = constraints.maxWidth >= WebBreakpoints.medium;
        return Row(
          children: [
            if (showSidebar)
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: _collapsed ? _kRailWidth : _kExpandedWidth,
                decoration: BoxDecoration(
                  color: webColors.sidebarBackground,
                  border: Border(
                      right: BorderSide(
                          color:
                              context.appColors.border.withValues(alpha: 0.5))),
                ),
                child: SafeArea(
                  right: false,
                  child: _SidebarContent(
                    title: widget.title,
                    titleIcon: widget.titleIcon,
                    navSections: widget.navSections,
                    activeNavId: widget.activeNavId,
                    collapsed: _collapsed,
                    user: widget.user,
                    onToggleCollapse: _toggleCollapsed,
                  ),
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  WebTopBar(
                    user: widget.user,
                    navSections: widget.navSections,
                    showSidebarToggle: !showSidebar,
                    onToggleSidebar: () =>
                        _scaffoldKey.currentState?.openDrawer(),
                    onLogout: widget.onLogout,
                    onSecuritySettings: widget.onSecuritySettings,
                    onAcademyInfo: widget.onAcademyInfo,
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(maxWidth: widget.maxContentWidth),
                        child: Padding(
                          padding:
                              widget.contentPadding ?? const EdgeInsets.all(24),
                          child: widget.body,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _SidebarContent extends StatelessWidget {
  final String title;
  final IconData titleIcon;
  final List<WebNavSection> navSections;
  final String activeNavId;
  final bool collapsed;
  final AppUser? user;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onNavigate;

  const _SidebarContent({
    required this.title,
    required this.titleIcon,
    required this.navSections,
    required this.activeNavId,
    required this.collapsed,
    this.user,
    this.onToggleCollapse,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final academyName = user?.academyName?.trim();
    final hasAcademy = academyName != null && academyName.isNotEmpty;
    return Column(
      children: [
        // The academy's own identity heads the sidebar; the platform name
        // appears only as a discreet attribution at the bottom.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Row(
            mainAxisAlignment:
                collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              if (hasAcademy)
                AcademyLogo.forUser(user, size: 36, radius: 10)
              else
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      gradient: AppColors.accentButton,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.school_rounded,
                      color: AppColors.textOnAccent, size: 20),
                ),
              if (!collapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(hasAcademy ? academyName : 'Academy Portal',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: context.appColors.textPrimary)),
                      if (user != null)
                        Text(user!.role.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: context.appColors.accentText)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Divider(
            height: 1, color: context.appColors.border.withValues(alpha: 0.6)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            children: [
              for (final section in navSections) ...[
                if (section.title != null && !collapsed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
                    child: Text(section.title!,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: context.appColors.textMuted)),
                  ),
                for (final item in section.items)
                  _NavTile(
                    item: item,
                    active: item.id == activeNavId,
                    collapsed: collapsed,
                    onNavigate: onNavigate,
                  ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: Row(
            mainAxisAlignment: collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.spaceBetween,
            children: [
              if (!collapsed)
                const Expanded(
                    child: Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: PoweredByTaleemPlus(centered: false))),
              if (onToggleCollapse != null)
                IconButton(
                  icon: Icon(
                      collapsed
                          ? Icons.chevron_right_rounded
                          : Icons.chevron_left_rounded,
                      color: context.appColors.textSecondary),
                  tooltip: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggleCollapse,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavTile extends StatefulWidget {
  final WebNavItem item;
  final bool active;
  final bool collapsed;
  final VoidCallback? onNavigate;

  const _NavTile({
    required this.item,
    required this.active,
    required this.collapsed,
    this.onNavigate,
  });

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final webColors = context.webColors;
    final bg = widget.active
        ? webColors.activeTint
        : (_hovering ? webColors.hoverTint : Colors.transparent);
    final fg = widget.active
        ? webColors.activeIndicator
        : context.appColors.textSecondary;

    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              widget.item.onTap();
              widget.onNavigate?.call();
            },
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: widget.collapsed ? 0 : 14, vertical: 11),
              child: widget.collapsed
                  ? Icon(widget.item.icon, size: 20, color: fg)
                  : Row(
                      children: [
                        Icon(widget.item.icon, size: 19, color: fg),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(widget.item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: widget.active
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: fg)),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );

    return widget.collapsed
        ? Tooltip(message: widget.item.label, child: tile)
        : tile;
  }
}
