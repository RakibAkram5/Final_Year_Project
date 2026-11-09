import '../../shared/course_materials_view.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../data/models/class_entity.dart';
import '../../../data/models/student_query.dart';
import '../../../data/remote/classroom_service.dart';
import '../../../logic/auth_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/app_widgets.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';

class ClassroomManagementScreen extends StatefulWidget {
  final ClassEntity classEntity;

  /// 0 = Student Queries, 1 = Share Content (Resources). Lets dashboard
  /// shortcuts (see teacher_dashboard.dart's "Resources"/"Queries" tiles)
  /// land directly on the right tab instead of always opening on Queries.
  final int initialTabIndex;
  const ClassroomManagementScreen({
    super.key,
    required this.classEntity,
    this.initialTabIndex = 0,
  });

  @override
  State<ClassroomManagementScreen> createState() =>
      _ClassroomManagementScreenState();
}

class _ClassroomManagementScreenState extends State<ClassroomManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _classroomService = ClassroomService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      return _buildWebLayout(context);
    }
    return _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.classEntity.displayLabel,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: context.appColors.textSecondary,
          tabs: const [
            Tab(text: 'STUDENT QUERIES'),
            Tab(text: 'SHARE CONTENT'),
          ],
        ),
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _tabBarView(),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final navSections = buildTeacherNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: widget.classEntity.displayLabel,
      titleIcon: Icons.door_sliding_rounded,
      navSections: navSections,
      activeNavId: widget.initialTabIndex == 1 ? 'resources' : 'queries',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      contentPadding: EdgeInsets.zero,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.classEntity.displayLabel,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w800)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: AppColors.accent,
                labelColor: AppColors.accent,
                unselectedLabelColor: context.appColors.textSecondary,
                tabs: const [
                  Tab(text: 'STUDENT QUERIES'),
                  Tab(text: 'SHARE CONTENT'),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _tabBarView()),
        ],
      ),
    );
  }

  Widget _tabBarView() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildQueriesTab(),
        _buildShareTab(),
      ],
    );
  }

  Widget _buildQueriesTab() {
    return StreamBuilder<List<StudentQuery>>(
      stream: _classroomService.watchQueriesForClass(
          widget.classEntity.id, widget.classEntity.academyId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.accent));
        }
        if (snap.hasError) {
          return Center(
              child: Text('Error loading queries: ${snap.error}',
                  style: const TextStyle(color: AppColors.danger)));
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return _emptyState(
              Icons.question_answer_outlined, "No pending student queries.");
        }

        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _queryTile(list[i]),
        );
      },
    );
  }

  Widget _queryTile(StudentQuery q) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: q.isResolved
                ? AppColors.success.withValues(alpha: 0.3)
                : AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                  radius: 12,
                  child: Text(q.studentName[0],
                      style: const TextStyle(fontSize: 10))),
              const SizedBox(width: 8),
              Text(q.studentName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              if (q.isResolved)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 16),
            ],
          ),
          const SizedBox(height: 12),
          Text(q.question,
              style: TextStyle(
                  color: context.appColors.textPrimary, fontSize: 14)),
          if (q.answer != null) ...[
            const Divider(height: 24),
            Text("My Response: ${q.answer}",
                style: const TextStyle(
                    color: AppColors.success,
                    fontSize: 13,
                    fontStyle: FontStyle.italic)),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: PrimaryButton(
                label: "REPLY",
                onPressed: () => _showReplyDialog(q),
                icon: Icons.reply_rounded,
              ),
            ),
        ],
      ),
    );
  }

  void _showReplyDialog(StudentQuery q) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reply to Student"),
        content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration:
                const InputDecoration(hintText: "Enter your answer...")),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          TextButton(
              onPressed: () async {
                if (ctrl.text.isEmpty) return;
                try {
                  await _classroomService.answerQuery(q.id, ctrl.text);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text("Failed to send reply: $e"),
                        backgroundColor: AppColors.danger));
                  }
                }
              },
              child: const Text("SEND")),
        ],
      ),
    );
  }

  Widget _buildShareTab() =>
      CourseMaterialsView(classEntity: widget.classEntity, canManage: true);

  Widget _emptyState(IconData icon, String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 48,
              color: context.appColors.textMuted.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(msg, style: TextStyle(color: context.appColors.textSecondary)),
        ],
      ),
    );
  }
}
