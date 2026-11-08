import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/class_entity.dart';
import '../../../data/models/shared_resource.dart';
import '../../../data/remote/classroom_service.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/class_provider.dart';
import '../models/ocr_document_model.dart';

/// Publishes one or more OCR documents as [SharedResource]s to a
/// teacher-picked class. This is the only way resources get added to a
/// class now that manual link-paste uploads have been removed from
/// Classroom Management — reused by both the OCR History multi-select
/// "Publish" action and the single-document view screen.
Future<void> publishOcrDocumentsToClass(
    BuildContext context, List<OcrDocumentModel> docs) async {
  if (docs.isEmpty) return;
  final user = context.read<AuthProvider>().currentUser;
  if (user == null) return;

  final classes = context
      .read<ClassProvider>()
      .classes
      .where((c) => c.primaryTeacherId == user.uid)
      .toList();

  if (classes.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('You have no assigned classes to publish to.')));
    return;
  }

  final target = await showDialog<ClassEntity>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
          'Publish ${docs.length} document${docs.length == 1 ? '' : 's'} to...'),
      content: SizedBox(
        width: 320,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: classes.length,
          itemBuilder: (_, i) => ListTile(
            title: Text('${classes[i].className} (${classes[i].section})'),
            subtitle: Text(classes[i].subject),
            onTap: () => Navigator.pop(ctx, classes[i]),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ],
    ),
  );
  if (target == null || !context.mounted) return;

  final service = ClassroomService();
  try {
    for (final doc in docs) {
      await service.uploadResource(SharedResource(
        id: '',
        academyId: user.academyId ?? user.uid,
        classId: target.id,
        teacherId: user.uid,
        teacherName: user.fullName,
        title: doc.title,
        description: '',
        contentText: doc.extractedText,
        createdAt: DateTime.now(),
      ));
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Published to ${target.className} (${target.section})')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to publish: $e'),
          backgroundColor: AppColors.danger));
    }
  }
}
