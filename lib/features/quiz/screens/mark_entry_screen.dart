import 'package:flutter/material.dart';
import '../../../core/theme/theme_extensions.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../logic/quiz_provider.dart';
import '../../../logic/class_provider.dart';
import '../../../widgets/app_widgets.dart';
import '../../../widgets/gradient_background.dart';
import '../../../data/models/class_entity.dart';
import '../../../data/models/quiz_model.dart';
import '../../../data/models/test_mark_model.dart';

class MarkEntryScreen extends StatefulWidget {
  final QuizModel quiz;
  const MarkEntryScreen({super.key, required this.quiz});

  @override
  State<MarkEntryScreen> createState() => _MarkEntryScreenState();
}

class _MarkEntryScreenState extends State<MarkEntryScreen> {
  final Map<String, TextEditingController> _markControllers = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final classes = context.read<ClassProvider>().classes;
    final clsList = classes.where((c) => c.id == widget.quiz.classId).toList();

    if (clsList.isNotEmpty) {
      final cls = clsList.first;
      for (var studentId in cls.studentIds) {
        _markControllers[studentId] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (var ctrl in _markControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _saveMarks() async {
    final clsList = context
        .read<ClassProvider>()
        .classes
        .where((c) => c.id == widget.quiz.classId)
        .toList();
    if (clsList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This class no longer exists.'),
          backgroundColor: AppColors.danger));
      return;
    }
    final cls = clsList.first;

    for (var entry in _markControllers.entries) {
      final text = entry.value.text.trim();
      if (text.isEmpty) continue;
      final val = double.tryParse(text);
      if (val == null || val < 0 || val > widget.quiz.totalMarks) {
        final name = cls.studentNames[entry.key] ?? "a student";
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "Invalid mark for $name: must be between 0 and ${widget.quiz.totalMarks}."),
            backgroundColor: AppColors.danger));
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final List<TestMarkModel> marksList = [];

      _markControllers.forEach((uid, ctrl) {
        if (ctrl.text.trim().isNotEmpty) {
          final obtained = double.tryParse(ctrl.text.trim()) ?? 0;
          final percentage = (obtained / widget.quiz.totalMarks) * 100;

          marksList.add(TestMarkModel(
            id: "${widget.quiz.id}_$uid",
            academyId: widget.quiz.academyId,
            quizId: widget.quiz.id,
            studentId: uid,
            studentName: cls.studentNames[uid] ?? "Unknown",
            classId: widget.quiz.classId,
            subject: widget.quiz.subject,
            month: widget.quiz.month,
            marksObtained: obtained,
            totalMarks: widget.quiz.totalMarks,
            percentage: percentage,
            gradeLetter: TestMarkModel.calculateGrade(percentage),
            updatedAt: DateTime.now(),
          ));
        }
      });

      if (marksList.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("No marks entered!")));
        return;
      }

      await context.read<QuizProvider>().uploadBulkMarks(marksList);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Marks saved successfully!")));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error saving marks: $e")));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final classes = context.watch<ClassProvider>().classes;
    final clsList = classes.where((c) => c.id == widget.quiz.classId).toList();

    if (clsList.isEmpty) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text("Class data not found.")));
    }
    final cls = clsList.first;
    final ordered = _byRollNumber(cls);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter Test Marks',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
      ),
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              _quizInfoCard(),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: ordered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final uid = ordered[i];
                    final name = cls.studentNames[uid] ?? "Student";
                    final roll = cls.studentRollNumbers[uid] ?? '';
                    return _studentMarkTile(
                        roll.isEmpty ? name : '$roll  ·  $name', uid);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: PrimaryButton(
                  label: "UPLOAD MARKS",
                  icon: Icons.cloud_upload_rounded,
                  loading: _isSaving,
                  onPressed: _saveMarks,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Students in roll-number order (natural sort: 9B-2 before 9B-10);
  /// students without a roll number follow, alphabetically.
  static List<String> _byRollNumber(ClassEntity cls) {
    final ids = List<String>.of(cls.studentIds);
    int numberOf(String roll) =>
        int.tryParse(RegExp(r'(\d+)\D*$').firstMatch(roll)?.group(1) ?? '') ??
        0;
    ids.sort((a, b) {
      final ra = cls.studentRollNumbers[a] ?? '';
      final rb = cls.studentRollNumbers[b] ?? '';
      if (ra.isEmpty != rb.isEmpty) return ra.isEmpty ? 1 : -1;
      if (ra.isNotEmpty) {
        final prefixA = ra.replaceAll(RegExp(r'\d+\D*$'), '');
        final prefixB = rb.replaceAll(RegExp(r'\d+\D*$'), '');
        final byPrefix = prefixA.compareTo(prefixB);
        if (byPrefix != 0) return byPrefix;
        final byNumber = numberOf(ra).compareTo(numberOf(rb));
        if (byNumber != 0) return byNumber;
      }
      return (cls.studentNames[a] ?? '').compareTo(cls.studentNames[b] ?? '');
    });
    return ids;
  }

  Widget _quizInfoCard() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.quiz.title,
              style: TextStyle(
                  color: context.appColors.accentText,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          Text("${widget.quiz.subject} • Total: ${widget.quiz.totalMarks}",
              style: TextStyle(
                  color: context.appColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _studentMarkTile(String name, String uid) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
              child: Text(name,
                  style: TextStyle(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.w600))),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _markControllers[uid],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: context.appColors.accentText,
                  fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: "0.0",
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
