import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';

/// A hover-lift wrapper shared by the web card widgets below — scales up
/// very slightly and raises its shadow on mouse-over, standard SaaS-dashboard
/// affordance for "this is clickable".
class _HoverLift extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  const _HoverLift(
      {required this.child, required this.borderRadius, this.onTap});

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor:
          widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0.0, _hovering ? -3.0 : 0.0, 0.0),
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hovering ? 0.10 : 0.05),
              blurRadius: _hovering ? 22 : 10,
              offset: Offset(0, _hovering ? 10 : 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: widget.borderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: widget.onTap, child: widget.child),
        ),
      ),
    );
  }
}

/// A statistic tile for the top of a dashboard — gradient accent icon badge,
/// big number, hover-lift.
class WebStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? accent;
  final String? trend;
  final bool trendUp;

  const WebStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
    this.accent,
    this.trend,
    this.trendUp = true,
  });

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? AppColors.accent;
    final radius = BorderRadius.circular(20);
    return _HoverLift(
      borderRadius: radius,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 130),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.appColors.surface,
          borderRadius: radius,
          border: Border.all(
              color: context.appColors.border.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        tint.withValues(alpha: 0.22),
                        tint.withValues(alpha: 0.08)
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: tint, size: 21),
                ),
                if (trend != null)
                  Row(
                    children: [
                      Icon(
                        trendUp
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 14,
                        color: trendUp ? AppColors.success : AppColors.danger,
                      ),
                      Text(trend!,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: trendUp
                                  ? AppColors.success
                                  : AppColors.danger)),
                    ],
                  ),
              ],
            ),
            // A Spacer here broke when the card sits in an unbounded Column
            // (narrow layouts); the container's minHeight keeps the shape.
            const SizedBox(height: 18),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: context.appColors.textPrimary)),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.appColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// A general-purpose modern card: rounded corners, soft shadow, optional
/// leading gradient accent bar, hover-lift when [onTap] is set.
class WebSectionCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool accentBar;

  const WebSectionCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(20),
    this.accentBar = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    final content = Container(
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: radius,
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (accentBar)
            Container(
              width: 4,
              decoration: const BoxDecoration(
                gradient: AppColors.accentButton,
                borderRadius:
                    BorderRadius.horizontal(left: Radius.circular(18)),
              ),
            ),
          Expanded(child: Padding(padding: padding, child: child)),
        ],
      ),
    );
    return _HoverLift(borderRadius: radius, onTap: onTap, child: content);
  }
}

/// A titled grid of [WebSectionCard]/[WebStatCard]-style tiles, replacing
/// the mobile `_gridSection` pattern for the web layout — same idea
/// (labeled group of a 2-4 column grid), wider columns on desktop.
class WebGridSection extends StatelessWidget {
  final String title;
  final List<Widget> tiles;
  final double tileMinWidth;
  final double tileAspectRatio;

  const WebGridSection({
    super.key,
    required this.title,
    required this.tiles,
    this.tileMinWidth = 240,
    this.tileAspectRatio = 1.35,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1)),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final columns =
                (constraints.maxWidth / tileMinWidth).floor().clamp(1, 4);
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: tileAspectRatio,
              children: tiles,
            );
          }),
        ],
      ),
    );
  }
}

/// A compact dashboard tile (icon + title + subtitle) rendered inside a
/// [WebGridSection] — the web equivalent of the mobile `_gridTile`.
class WebNavTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const WebNavTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return WebSectionCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: context.appColors.accentText, size: 20),
          ),
          const Spacer(),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: context.appColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5)),
          const SizedBox(height: 4),
          Text(subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(color: context.appColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
