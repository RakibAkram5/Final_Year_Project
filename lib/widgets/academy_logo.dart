import 'package:flutter/material.dart';

import '../core/branding/branding_utils.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/theme_extensions.dart';
import '../data/models/app_user.dart';

/// The academy's own logo (stored image or legacy URL) with a neutral
/// placeholder — the academy's initials — when none is configured.
///
/// Never shows TaleemPlus branding: the academy's identity is primary on
/// every portal screen and document.
class AcademyLogo extends StatelessWidget {
  final String? logo;
  final String? academyName;
  final double size;
  final double radius;
  final bool showShadow;

  const AcademyLogo({
    super.key,
    required this.logo,
    required this.academyName,
    this.size = 40,
    this.radius = 10,
    this.showShadow = false,
  });

  /// Convenience constructor from the signed-in user's academy fields.
  AcademyLogo.forUser(AppUser? user,
      {super.key, this.size = 40, this.radius = 10, this.showShadow = false})
      : logo = user?.academyLogo,
        academyName = user?.academyName;

  @override
  Widget build(BuildContext context) {
    final bytes = BrandingUtils.decodeLogo(logo);
    Widget image;
    if (bytes != null) {
      image = Image.memory(bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _placeholder(context));
    } else if (BrandingUtils.isNetworkUrl(logo)) {
      image = Image.network(logo!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(context));
    } else {
      image = _placeholder(context);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.6)),
        boxShadow: showShadow
            ? [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }

  Widget _placeholder(BuildContext context) => Container(
        color: AppColors.accent.withValues(alpha: 0.14),
        alignment: Alignment.center,
        child: Text(
          BrandingUtils.initials(academyName),
          style: TextStyle(
            color: context.appColors.accentText,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.38,
            letterSpacing: 0.5,
          ),
        ),
      );
}

/// Logo + academy name used as an app-bar title on every portal, with the
/// portal name as a small subtitle. Falls back to the portal name alone
/// before the profile has loaded.
class AcademyTitle extends StatelessWidget {
  final AppUser? user;
  final String portalLabel;
  final IconData portalIcon;

  const AcademyTitle({
    super.key,
    required this.user,
    required this.portalLabel,
    required this.portalIcon,
  });

  @override
  Widget build(BuildContext context) {
    final name = user?.academyName?.trim();
    final hasAcademy = name != null && name.isNotEmpty;
    return Row(
      children: [
        if (hasAcademy)
          AcademyLogo.forUser(user, size: 34, radius: 9)
        else
          Icon(portalIcon, color: context.appColors.accentText, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hasAcademy ? name : portalLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: hasAcademy ? 16 : 18,
                      color: context.appColors.textPrimary)),
              if (hasAcademy)
                Text(portalLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                        color: context.appColors.accentText)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Discreet platform attribution. Academy identity stays primary; this is
/// the only place TaleemPlus appears on academy-facing screens.
class PoweredByTaleemPlus extends StatelessWidget {
  final bool centered;
  const PoweredByTaleemPlus({super.key, this.centered = true});

  @override
  Widget build(BuildContext context) {
    final text = Text('Powered by TaleemPlus',
        textAlign: centered ? TextAlign.center : TextAlign.start,
        style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 0.2,
            color: context.appColors.textMuted));
    return centered ? Center(child: text) : text;
  }
}
