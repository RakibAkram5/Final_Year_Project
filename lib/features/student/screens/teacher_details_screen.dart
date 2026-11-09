import '../../shared/course_materials_view.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../data/models/class_entity.dart';
import '../../../data/models/student_query.dart';
import '../../../data/models/attendance_record.dart';
import '../../../data/remote/classroom_service.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/attendance_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';

class TeacherDetailsScreen extends StatefulWidget {
  final ClassEntity classEntity;
  const TeacherDetailsScreen({super.key, required this.classEntity});

  @override
  State<TeacherDetailsScreen> createState() => _TeacherDetailsScreenState();
}

class _TeacherDetailsScreenState extends State<TeacherDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _classroomService = ClassroomService();
  final _queryCtrl = TextEditingController();
  bool _sendingQuery = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _queryCtrl.dispose();
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
        title: Text(widget.classEntity.primaryTeacherName,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          // Fixed equal-width tabs cut "ATTENDANCE" mid-word on small phones.
          isScrollable: MediaQuery.sizeOf(context).width < 400,
          tabAlignment: MediaQuery.sizeOf(context).width < 400
              ? TabAlignment.start
              : null,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: context.appColors.textSecondary,
          tabs: const [
            Tab(text: 'RESOURCES'),
            Tab(text: 'ATTENDANCE'),
            Tab(text: 'DISCUSS'),
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
    final navSections = buildStudentNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: widget.classEntity.primaryTeacherName,
      titleIcon: Icons.person_rounded,
      navSections: navSections,
      activeNavId: 'classroom_hub',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      contentPadding: EdgeInsets.zero,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.classEntity.primaryTeacherName,
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
                  Tab(text: 'RESOURCES'),
                  Tab(text: 'ATTENDANCE'),
                  Tab(text: 'DISCUSS'),
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
        _buildResourcesTab(),
        _buildAttendanceTab(),
        _buildDiscussTab(),
      ],
    );
  }

  Widget _buildResourcesTab() =>
      CourseMaterialsView(classEntity: widget.classEntity);

  Widget _buildAttendanceTab() {
    final user = context.watch<AuthProvider>().currentUser;
    return StreamBuilder<List<AttendanceRecord>>(
      stream: context
          .read<AttendanceProvider>()
          .watchStudentAttendance(user?.uid ?? '', user?.academyId ?? ''),
      builder: (context, snap) {
        final allRecords = snap.data ?? [];
        // Filter specifically for this teacher's class
        final classRecords = allRecords
            .where((r) => r.classId == widget.classEntity.id)
            .toList();

        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
              child: Text('Error loading attendance: ${snap.error}',
                  style: const TextStyle(color: AppColors.danger)));
        }
        if (classRecords.isEmpty) {
          return _emptyState(
              Icons.fact_check_outlined, "No attendance records found.");
        }

        final total = classRecords.length;
        final present = classRecords
            .where((r) => r.status == 'present' || r.status == 'late')
            .length;
        final percentage = (present / total) * 100;

        return Column(
          children: [
            _attendanceSummaryHeader(percentage, present, total),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: classRecords.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _attendanceTile(classRecords[i]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _attendanceSummaryHeader(double pct, int p, int t) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.accent.withValues(alpha: 0.15),
          context.appColors.surface
        ]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem("Subject Presence", "${pct.toStringAsFixed(1)}%",
              AppColors.accent),
          _statItem("Present", "$p", AppColors.success),
          _statItem("Total Classes", "$t", context.appColors.textPrimary),
        ],
      ),
    );
  }

  Widget _statItem(String label, String val, Color color) {
    return Column(
      children: [
        Text(val,
            style: TextStyle(
                color: color, fontSize: 24, fontWeight: FontWeight.w900)),
        Text(label,
            style: TextStyle(
                color: context.appColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _attendanceTile(AttendanceRecord r) {
    final isPresent = r.status == 'present' || r.status == 'late';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: context.appColors.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(DateFormat('EEEE, MMM dd').format(r.logDate),
              style: TextStyle(
                  color: context.appColors.textPrimary,
                  fontWeight: FontWeight.w600)),
          Text(r.status.toUpperCase(),
              style: TextStyle(
                  color: isPresent ? AppColors.success : AppColors.danger,
                  fontWeight: FontWeight.w900,
                  fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildDiscussTab() {
    final user = context.watch<AuthProvider>().currentUser;
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<StudentQuery>>(
            stream: _classroomService.watchQueriesForClass(
                widget.classEntity.id, widget.classEntity.academyId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                    child: Text('Error loading queries: ${snap.error}',
                        style: const TextStyle(color: AppColors.danger)));
              }
              final queries = (snap.data ?? [])
                  .where((q) => q.studentId == user?.uid)
                  .toList();
              if (queries.isEmpty) {
                return _emptyState(Icons.question_answer_outlined,
                    "Ask your teacher a question!");
              }

              return ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: queries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, i) => _queryCard(queries[i]),
              );
            },
          ),
        ),
        _queryInputArea(user),
      ],
    );
  }

  Widget _queryCard(StudentQuery q) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16))),
          child: Text(q.question,
              style: TextStyle(
                  color: context.appColors.textPrimary,
                  fontWeight: FontWeight.w500)),
        ),
        if (q.answer != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 32),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: context.appColors.surface,
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16)),
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Teacher's Response",
                      style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(q.answer!,
                      style: TextStyle(color: context.appColors.textPrimary)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _queryInputArea(dynamic user) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: context.appColors.surface,
          border: Border(top: BorderSide(color: context.appColors.border))),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _queryCtrl,
              decoration: const InputDecoration(
                  hintText: "Type your query...",
                  border: InputBorder.none,
                  filled: false),
              style: TextStyle(color: context.appColors.textPrimary),
            ),
          ),
          IconButton(
            onPressed: _sendingQuery ? null : () => _submitQuery(user),
            icon: _sendingQuery
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accent))
                : Icon(Icons.send_rounded, color: context.appColors.accentText),
          ),
        ],
      ),
    );
  }

  Future<void> _submitQuery(dynamic user) async {
    if (_queryCtrl.text.trim().isEmpty || _sendingQuery) return;
    final q = StudentQuery(
      id: '', // Firestore auto-gen
      academyId: user.academyId,
      classId: widget.classEntity.id,
      studentId: user.uid,
      studentName: user.fullName,
      teacherId: widget.classEntity.primaryTeacherId,
      question: _queryCtrl.text.trim(),
      createdAt: DateTime.now(),
    );
    setState(() => _sendingQuery = true);
    try {
      await _classroomService.postQuery(q);
      _queryCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to send question: $e'),
            backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _sendingQuery = false);
    }
  }

  Widget _emptyState(IconData icon, String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 48,
              color: context.appColors.textMuted.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(msg, style: TextStyle(color: context.appColors.textSecondary)),
        ],
      ),
    );
  }
}
