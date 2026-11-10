import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/quiz_provider.dart';
import '../../../logic/class_provider.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';
import '../../../data/models/class_entity.dart';

class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  String? _selectedClassId;
  String _selectedMonth = DateFormat('MMMM').format(DateTime.now());

  final List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().currentUser;
      if (user != null) {
        context.read<ClassProvider>().listenAll(user.academyId ?? '');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      return _buildWebLayout(context);
    }
    return _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final classes = context
        .watch<ClassProvider>()
        .classes
        .where((c) => c.primaryTeacherId == user?.uid)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Reports',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(classes),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final classes = context
        .watch<ClassProvider>()
        .classes
        .where((c) => c.primaryTeacherId == user?.uid)
        .toList();
    final navSections = buildTeacherNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: 'Monthly Reports',
      titleIcon: Icons.insights_rounded,
      navSections: navSections,
      activeNavId: 'monthly_report',
      user: user,
      onLogout: () => performWebLogout(context),
      body: _body(classes),
    );
  }

  Widget _body(List<ClassEntity> classes) {
    return Column(
      children: [
        _buildFilters(classes),
        Expanded(
          child: _selectedClassId == null
              ? _buildNoClassState()
              : _buildReportList(),
        ),
      ],
    );
  }

  Widget _buildFilters(List<ClassEntity> classes) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
                color: context.appColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.appColors.border)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedClassId,
                hint: const Text('Select Class'),
                isExpanded: true,
                dropdownColor: context.appColors.surface,
                items: classes
                    .map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(c.displayLabel,
                            style: TextStyle(
                                color: context.appColors.textPrimary))))
                    .toList(),
                onChanged: (v) => setState(() => _selectedClassId = v),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
                color: context.appColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.appColors.border)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedMonth,
                isExpanded: true,
                dropdownColor: context.appColors.surface,
                items: _months
                    .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(m,
                            style: TextStyle(
                                color: context.appColors.textPrimary))))
                    .toList(),
                onChanged: (v) => setState(() => _selectedMonth = v!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportList() {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    final academyId = user?.academyId ?? '';

    return StreamBuilder<Map<String, dynamic>>(
      stream: context.read<QuizProvider>().watchMonthlyClassReport(
          _selectedClassId!, _selectedMonth, academyId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.accent));
        }
        if (snap.hasError) {
          return Center(
              child: Text('Error loading report: ${snap.error}',
                  style: const TextStyle(color: AppColors.danger)));
        }

        final data = snap.data;
        if (data == null || data['quizCount'] == 0) {
          return Center(
              child: Text('No data found for this month',
                  style: TextStyle(color: context.appColors.textSecondary)));
        }

        final Map<String, Map<String, dynamic>> studentStats =
            data['studentStats'];
        final List<String> subjects = List<String>.from(data['subjects']);

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          itemCount: studentStats.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final studentId = studentStats.keys.elementAt(i);
            final stats = studentStats[studentId]!;
            return _reportTile(stats, subjects);
          },
        );
      },
    );
  }

  Widget _reportTile(Map<String, dynamic> stats, List<String> subjects) {
    final double percentage = (stats['obtained'] / stats['total']) * 100;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(stats['name'],
                  style: TextStyle(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              Text("${percentage.toStringAsFixed(1)}%",
                  style: TextStyle(
                      color: percentage >= 50
                          ? AppColors.success
                          : AppColors.danger,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          Divider(height: 24, color: context.appColors.border),
          ...subjects.map((sub) {
            final subStats =
                stats['subjects'][sub] ?? {'obtained': 0.0, 'total': 0.0};
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(sub,
                      style: TextStyle(
                          color: context.appColors.textSecondary,
                          fontSize: 12)),
                  Text("${subStats['obtained']} / ${subStats['total']}",
                      style: TextStyle(
                          color: context.appColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildNoClassState() {
    return Center(
        child: Text('Select a class to view reports',
            style: TextStyle(color: context.appColors.textSecondary)));
  }
}
