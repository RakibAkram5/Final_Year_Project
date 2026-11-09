import 'package:flutter/material.dart';

import '../../core/theme/theme_extensions.dart';
import '../../data/remote/file_service.dart';
import '../../widgets/attachments_section.dart';
import '../../widgets/gradient_background.dart';

/// Documents kept for one person: admission papers and certificates for a
/// student, CV and qualifications for a teacher. Admins manage them
/// ([canEdit]); the person (and a student's linked parents) can view and
/// download. Access is enforced by the server.
class DocumentsScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final FileCategory category;
  final String ownerId;
  final bool canEdit;

  const DocumentsScreen({
    super.key,
    required this.title,
    required this.category,
    required this.ownerId,
    this.subtitle = '',
    this.canEdit = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: GradientBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (subtitle.isNotEmpty) ...[
                    Text(subtitle,
                        style:
                            TextStyle(color: context.appColors.textSecondary)),
                    const SizedBox(height: 16),
                  ],
                  AttachmentsSection(
                    category: category,
                    ownerId: ownerId,
                    canEdit: canEdit,
                    title: 'Documents',
                    emptyText: canEdit
                        ? 'No documents yet. Upload PDF, Word or image files (max 4 MB).'
                        : 'No documents have been shared yet.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
