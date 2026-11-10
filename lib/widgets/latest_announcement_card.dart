import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/theme_extensions.dart';
import '../data/models/announcement.dart';
import '../data/remote/announcement_service.dart';

/// Compact "latest announcement for my role" widget — reused wherever a
/// dashboard wants a one-glance preview instead of sending the user
/// straight to the full announcements list.
class LatestAnnouncementCard extends StatelessWidget {
  final String role;
  final String academyId;
  final VoidCallback? onTap;

  const LatestAnnouncementCard({
    super.key,
    required this.role,
    required this.academyId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Announcement>>(
      stream: AnnouncementService().watchForRole(role, academyId),
      builder: (context, snap) {
        final list = snap.data ?? const [];
        final latest = list.isEmpty ? null : list.first;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.campaign_rounded,
                        color: context.appColors.accentText, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LATEST ANNOUNCEMENT',
                            style: TextStyle(
                                color: context.appColors.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 2),
                        Text(
                          latest?.title ?? 'No announcements yet',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.appColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13),
                        ),
                        if (latest != null)
                          Text(
                            latest.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.appColors.textSecondary,
                                fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  if (onTap != null)
                    Icon(Icons.chevron_right,
                        color: context.appColors.textMuted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
