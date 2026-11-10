import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';

/// One action shown on a [ResponsiveActionTile] (or in an app bar via
/// [responsiveAppBarActions]).
///
/// The same spec renders either as an inline icon button (with [label] as its
/// tooltip / accessibility label) or as an entry of the overflow menu, so the
/// caller never has to build two variants of the same action.
class TileAction {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;
  final Color? color;

  const TileAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.color,
  });

  Color resolveColor() =>
      color ?? (destructive ? AppColors.danger : AppColors.accent);
}

/// A list card with a leading badge, a flexible text block and a set of
/// actions that never starves the text of space.
///
/// Layout rule (the fix for the Class Management card that split class names
/// mid-word): the text block is guaranteed at least [minTextWidth] logical
/// pixels. Actions are shown inline only while that guarantee holds; the
/// remainder moves into a "More actions" overflow menu. On the narrowest
/// phones every action lives in the menu and the title keeps the full row.
/// Titles wrap at word boundaries and are never ellipsized, so long class
/// names stay readable.
class ResponsiveActionTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final TextStyle? titleStyle;

  /// Secondary lines under the title (teacher, counts, dates...). Each line is
  /// rendered with soft wrapping; pass widgets for custom styling.
  final List<Widget> subtitles;

  /// Optional widget placed after the subtitles (chips, status badges...).
  final Widget? footer;
  final List<TileAction> actions;
  final VoidCallback? onTap;
  final double minTextWidth;
  final EdgeInsetsGeometry padding;
  final Color? background;

  /// Maximum number of actions ever shown inline, even on wide screens.
  final int maxInline;

  const ResponsiveActionTile({
    super.key,
    this.leading,
    required this.title,
    this.titleStyle,
    this.subtitles = const [],
    this.footer,
    this.actions = const [],
    this.onTap,
    this.minTextWidth = 168,
    this.padding = const EdgeInsets.all(14),
    this.background,
    this.maxInline = 4,
  });

  /// Size of one inline action button (Material minimum touch target).
  static const double actionExtent = 44;
  static const double _leadingGap = 12;
  static const double _actionsGap = 4;

  /// How many actions fit inline next to a text block of at least
  /// [minTextWidth], given the full tile [width]. Exposed for tests.
  static int inlineActionCount({
    required double width,
    required int actionCount,
    required double leadingWidth,
    required double horizontalPadding,
    double minTextWidth = 168,
    int maxInline = 4,
  }) {
    if (actionCount == 0) return 0;
    final available = width -
        horizontalPadding -
        leadingWidth -
        (leadingWidth > 0 ? _leadingGap : 0) -
        _actionsGap -
        minTextWidth;
    final slots = (available / actionExtent).floor();
    final cap = actionCount < maxInline ? actionCount : maxInline;
    if (slots >= actionCount && actionCount <= cap) return actionCount;
    // One slot is reserved for the overflow ("more") button.
    final inline = slots - 1;
    if (inline <= 0) return 0;
    return inline < cap ? inline : cap - 1;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final resolvedPadding = padding.resolve(Directionality.of(context));
    return Material(
      color: background ?? colors.surface.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.border.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: resolvedPadding,
          child: LayoutBuilder(builder: (context, constraints) {
            final leadingWidth = leading == null ? 0.0 : 44.0;
            final inline = inlineActionCount(
              width: constraints.maxWidth,
              actionCount: actions.length,
              leadingWidth: leadingWidth,
              horizontalPadding: 0,
              minTextWidth: minTextWidth,
              maxInline: maxInline,
            );
            final inlineActions = actions.take(inline).toList();
            final overflow = actions.skip(inline).toList();
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (leading != null) ...[
                  SizedBox(width: leadingWidth, child: leading),
                  const SizedBox(width: _leadingGap),
                ],
                Expanded(child: _textBlock(context)),
                if (inlineActions.isNotEmpty || overflow.isNotEmpty)
                  const SizedBox(width: _actionsGap),
                for (final a in inlineActions) _inlineButton(a),
                if (overflow.isNotEmpty)
                  OverflowActionsButton(actions: overflow),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _textBlock(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          softWrap: true,
          style: titleStyle ??
              TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                height: 1.25,
              ),
        ),
        for (final line in subtitles) ...[
          const SizedBox(height: 2),
          line,
        ],
        if (footer != null) ...[
          const SizedBox(height: 6),
          footer!,
        ],
      ],
    );
  }

  Widget _inlineButton(TileAction a) {
    return SizedBox(
      width: actionExtent,
      height: actionExtent,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: a.label,
        icon: Icon(a.icon, color: a.resolveColor(), size: 22),
        onPressed: a.onPressed,
      ),
    );
  }
}

/// A "More actions" button listing [actions] in a popup menu.
class OverflowActionsButton extends StatelessWidget {
  final List<TileAction> actions;
  final Color? iconColor;
  final String tooltip;

  const OverflowActionsButton({
    super.key,
    required this.actions,
    this.iconColor,
    this.tooltip = 'More actions',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ResponsiveActionTile.actionExtent,
      height: ResponsiveActionTile.actionExtent,
      child: PopupMenuButton<int>(
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        icon: Icon(Icons.more_vert_rounded,
            color: iconColor ?? context.appColors.textSecondary),
        onSelected: (i) => actions[i].onPressed?.call(),
        itemBuilder: (_) => [
          for (var i = 0; i < actions.length; i++)
            PopupMenuItem<int>(
              value: i,
              enabled: actions[i].onPressed != null,
              child: Row(
                children: [
                  Icon(actions[i].icon,
                      size: 20, color: actions[i].resolveColor()),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      actions[i].label,
                      style: actions[i].destructive
                          ? const TextStyle(color: AppColors.danger)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// App-bar action that can collapse into an overflow menu.
class AppBarActionSpec {
  /// The widget shown when the action fits in the app bar.
  final Widget inline;

  /// Representation in the overflow menu. Null means the action is pinned
  /// and is always shown inline (e.g. the notification bell).
  final TileAction? menu;

  const AppBarActionSpec.pinned(this.inline) : menu = null;
  const AppBarActionSpec.collapsible(
      {required this.inline, required TileAction this.menu});
}

/// Builds app-bar actions that never squeeze the title: on narrow screens
/// only pinned actions (plus as many collapsible ones as fit) stay inline and
/// the rest move into a single overflow menu.
///
/// Budget: the title keeps at least [minTitleWidth] pixels; every action is
/// [kMinInteractiveDimension] wide.
List<Widget> responsiveAppBarActions(
  BuildContext context,
  List<AppBarActionSpec> specs, {
  double minTitleWidth = 150,
  double leadingWidth = 56,
}) {
  final width = MediaQuery.sizeOf(context).width;
  const extent = kMinInteractiveDimension;
  final pinned = specs.where((s) => s.menu == null).length;
  final collapsible = specs.where((s) => s.menu != null).toList();
  final budget = width - leadingWidth - minTitleWidth;
  var slots = (budget / extent).floor() - pinned;
  final bool needsMenu = slots < collapsible.length;
  if (needsMenu) slots -= 1; // reserve the overflow button
  if (slots < 0) slots = 0;

  final result = <Widget>[];
  final overflow = <TileAction>[];
  var used = 0;
  for (final s in specs) {
    if (s.menu == null) {
      result.add(s.inline);
    } else if (!needsMenu || used < slots) {
      result.add(s.inline);
      used++;
    } else {
      overflow.add(s.menu!);
    }
  }
  if (overflow.isNotEmpty) {
    result.add(OverflowActionsButton(
      actions: overflow,
      iconColor: AppColors.accent,
      tooltip: 'More options',
    ));
  }
  return result;
}
