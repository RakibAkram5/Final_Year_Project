import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Sidebar/topbar/hover tokens for the web SaaS shell. Kept as its own
/// [ThemeExtension] — separate from the mobile [AppColorsExtension] in
/// `theme_extensions.dart` — so nothing about the mobile theme changes.
class WebColorsExtension extends ThemeExtension<WebColorsExtension> {
  final Color sidebarBackground;
  final Color topbarBackground;
  final Color hoverTint;
  final Color activeTint;
  final Color activeIndicator;
  final Color scrollTrack;
  final Color skeletonBase;
  final Color skeletonHighlight;

  const WebColorsExtension({
    required this.sidebarBackground,
    required this.topbarBackground,
    required this.hoverTint,
    required this.activeTint,
    required this.activeIndicator,
    required this.scrollTrack,
    required this.skeletonBase,
    required this.skeletonHighlight,
  });

  @override
  WebColorsExtension copyWith({
    Color? sidebarBackground,
    Color? topbarBackground,
    Color? hoverTint,
    Color? activeTint,
    Color? activeIndicator,
    Color? scrollTrack,
    Color? skeletonBase,
    Color? skeletonHighlight,
  }) {
    return WebColorsExtension(
      sidebarBackground: sidebarBackground ?? this.sidebarBackground,
      topbarBackground: topbarBackground ?? this.topbarBackground,
      hoverTint: hoverTint ?? this.hoverTint,
      activeTint: activeTint ?? this.activeTint,
      activeIndicator: activeIndicator ?? this.activeIndicator,
      scrollTrack: scrollTrack ?? this.scrollTrack,
      skeletonBase: skeletonBase ?? this.skeletonBase,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
    );
  }

  @override
  WebColorsExtension lerp(ThemeExtension<WebColorsExtension>? other, double t) {
    if (other is! WebColorsExtension) return this;
    return WebColorsExtension(
      sidebarBackground:
          Color.lerp(sidebarBackground, other.sidebarBackground, t)!,
      topbarBackground:
          Color.lerp(topbarBackground, other.topbarBackground, t)!,
      hoverTint: Color.lerp(hoverTint, other.hoverTint, t)!,
      activeTint: Color.lerp(activeTint, other.activeTint, t)!,
      activeIndicator: Color.lerp(activeIndicator, other.activeIndicator, t)!,
      scrollTrack: Color.lerp(scrollTrack, other.scrollTrack, t)!,
      skeletonBase: Color.lerp(skeletonBase, other.skeletonBase, t)!,
      skeletonHighlight:
          Color.lerp(skeletonHighlight, other.skeletonHighlight, t)!,
    );
  }

  static const light = WebColorsExtension(
    sidebarBackground: Colors.white,
    topbarBackground: Colors.white,
    hoverTint: Color(0x0F17E9DF),
    activeTint: Color(0x1A17E9DF),
    activeIndicator: AppColors.accentDark,
    scrollTrack: Color(0xFFF3F4F6),
    skeletonBase: Color(0xFFEDEEF1),
    skeletonHighlight: Color(0xFFF8F9FA),
  );

  static const dark = WebColorsExtension(
    sidebarBackground: Color(0xFF0A2626),
    topbarBackground: Color(0xFF0A2626),
    hoverTint: Color(0x1417E9DF),
    activeTint: Color(0x2417E9DF),
    activeIndicator: AppColors.accent,
    scrollTrack: Color(0xFF103A3A),
    skeletonBase: Color(0xFF123838),
    skeletonHighlight: Color(0xFF1B4747),
  );
}

extension WebThemeX on BuildContext {
  WebColorsExtension get webColors =>
      Theme.of(this).extension<WebColorsExtension>()!;
}

/// A gentle fade + upward-slide transition used only for the web theme's
/// [PageTransitionsTheme] — mobile keeps its platform-default transitions
/// since it never applies this theme.
class _WebPageTransitionsBuilder extends PageTransitionsBuilder {
  const _WebPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  }
}

const _webPageTransitionsTheme = PageTransitionsTheme(builders: {
  TargetPlatform.android: _WebPageTransitionsBuilder(),
  TargetPlatform.iOS: _WebPageTransitionsBuilder(),
  TargetPlatform.linux: _WebPageTransitionsBuilder(),
  TargetPlatform.macOS: _WebPageTransitionsBuilder(),
  TargetPlatform.windows: _WebPageTransitionsBuilder(),
  TargetPlatform.fuchsia: _WebPageTransitionsBuilder(),
});

/// Web-only theme: layered on top of [AppTheme] so the brand palette in
/// `app_colors.dart` stays the single source of truth, but with the Inter
/// font, softer/rounder surfaces, and smoother page transitions befitting a
/// desktop SaaS dashboard. Only ever assigned to `MaterialApp.theme` /
/// `darkTheme` behind a `kIsWeb` check in `main.dart`.
class AppWebTheme {
  AppWebTheme._();

  static ThemeData get light => _apply(AppTheme.light, WebColorsExtension.light,
      AppColors.borderLight, AppColors.surfaceLight);

  static ThemeData get dark => _apply(AppTheme.dark, WebColorsExtension.dark,
      AppColors.borderDark, AppColors.surfaceDark);

  static ThemeData _apply(ThemeData base, WebColorsExtension webColors,
      Color border, Color surface) {
    final interTextTheme = GoogleFonts.interTextTheme(base.textTheme);
    return base.copyWith(
      extensions: [...base.extensions.values, webColors],
      textTheme: interTextTheme,
      primaryTextTheme: GoogleFonts.interTextTheme(base.primaryTextTheme),
      pageTransitionsTheme: _webPageTransitionsTheme,
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: GoogleFonts.inter(
          textStyle: base.appBarTheme.titleTextStyle,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border.withValues(alpha: 0.5)),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
      ),
      // Denser-than-default controls for the desktop SaaS shell: this trims
      // every Material component's intrinsic size (buttons land in the
      // ~36-40px range, list tiles/inputs tighten) without per-widget edits.
      // Kept web-only so mobile touch targets stay comfortable.
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
