import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../data/models/class_section.dart';
import '../../../logic/auth_provider.dart';
import '../../../logic/class_section_provider.dart';
import '../../../data/repositories/fee_challan_repository.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/app_widgets.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';

class ChallanGenerationScreen extends StatefulWidget {
  const ChallanGenerationScreen({super.key});

  @override
  State<ChallanGenerationScreen> createState() =>
      _ChallanGenerationScreenState();
}

class _ChallanGenerationScreenState extends State<ChallanGenerationScreen> {
  final _repo = FeeChallanRepository();
  ClassSectionEntity? _selectedSection;
  String _selectedMonth = DateFormat('MMMM').format(DateTime.now());
  final _monthlyFeeCtrl = TextEditingController(text: "3000");
  final _admissionFeeCtrl = TextEditingController(text: "0");
  final _examFeeCtrl = TextEditingController(text: "0");
  final _fineCtrl = TextEditingController(text: "0");

  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user =
          Provider.of<AuthProvider>(context, listen: false).currentUser;
      if (user != null) {
        context.read<ClassSectionProvider>().listenAll(user.uid);
      }
    });
  }

  @override
  void dispose() {
    _monthlyFeeCtrl.dispose();
    _admissionFeeCtrl.dispose();
    _examFeeCtrl.dispose();
    _fineCtrl.dispose();
    super.dispose();
  }

  /// Due date for a challan billed for [monthName]: the 10th of that month.
  /// Since there is no year selector, a month earlier than the current one
  /// is assumed to refer to that month next year (e.g. generating a
  /// "January" challan in November means January next year).
  DateTime _dueDateForMonth(String monthName) {
    final now = DateTime.now();
    final monthIndex = _months.indexOf(monthName) + 1;
    var year = now.year;
    if (monthIndex < now.month) {
      year += 1;
    }
    return DateTime(year, monthIndex, 10);
  }

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
  Widget build(BuildContext context) {
    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      return _buildWebLayout(context);
    }
    return _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) {
    final sections = context.watch<ClassSectionProvider>().sections;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate Challans',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(sections),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final sections = context.watch<ClassSectionProvider>().sections;
    final navSections = buildAdminNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: 'Generate Challans',
      titleIcon: Icons.request_quote_rounded,
      navSections: navSections,
      activeNavId: 'bulk_challans',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: _body(sections),
        ),
      ),
    );
  }

  Widget _body(List<ClassSectionEntity> sections) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildClassSelector(sections),
        const SizedBox(height: 16),
        _buildMonthSelector(),
        const SizedBox(height: 24),
        Text("FEE STRUCTURE",
            style: TextStyle(
                color: context.appColors.accentText,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2)),
        const SizedBox(height: 16),
        LabeledField(
            label: "Monthly Tuition Fee",
            hint: "3000",
            controller: _monthlyFeeCtrl,
            keyboardType: TextInputType.number),
        LabeledField(
            label: "Admission Fee (One-time)",
            hint: "0",
            controller: _admissionFeeCtrl,
            keyboardType: TextInputType.number),
        LabeledField(
            label: "Exam Fee",
            hint: "0",
            controller: _examFeeCtrl,
            keyboardType: TextInputType.number),
        LabeledField(
            label: "Fine / Arrears",
            hint: "0",
            controller: _fineCtrl,
            keyboardType: TextInputType.number),
        const SizedBox(height: 24),
        PrimaryButton(
          label: "GENERATE FOR SECTION",
          icon: Icons.auto_awesome_motion_rounded,
          loading: _isGenerating,
          onPressed: (_selectedSection == null || _isGenerating)
              ? null
              : _confirmAndGenerate,
        ),
        const SizedBox(height: 12),
        Text(
            "Note: This will create pending challans for all students enrolled in the selected class+section.",
            textAlign: TextAlign.center,
            style: TextStyle(color: context.appColors.textMuted, fontSize: 11)),
      ],
    );
  }

  Widget _buildClassSelector(List<ClassSectionEntity> sections) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("SELECT CLASS & SECTION",
            style: TextStyle(
                color: context.appColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
              color: context.appColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.appColors.border)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ClassSectionEntity>(
              value: _selectedSection,
              isExpanded: true,
              dropdownColor: context.appColors.surface,
              hint: const Text("Pick a class & section"),
              items: sections
                  .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s.displayLabel,
                          style:
                              TextStyle(color: context.appColors.textPrimary))))
                  .toList(),
              onChanged: (v) => setState(() => _selectedSection = v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMonthSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("BILLING MONTH",
            style: TextStyle(
                color: context.appColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
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
                          style:
                              TextStyle(color: context.appColors.textPrimary))))
                  .toList(),
              onChanged: (v) => setState(() => _selectedMonth = v!),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmAndGenerate() async {
    final section = _selectedSection;
    if (section == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appColors.surface,
        title: const Text('Generate challans?'),
        content: Text(
            'This will create pending challans for every student enrolled in '
            '${section.displayLabel} for $_selectedMonth. Students who already '
            'have a challan for this month will be skipped. This cannot be '
            'undone automatically.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Generate')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _generateChallans();
    }
  }

  Future<void> _generateChallans() async {
    final section = _selectedSection;
    if (section == null) return;

    setState(() => _isGenerating = true);

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final admin = auth.currentUser;
      if (admin == null) return;

      if (section.studentIds.isEmpty) {
        throw Exception("No students are enrolled in this section.");
      }

      // One atomic, duplicate-safe server call: the backend creates a
      // pending challan for every active student in the section and skips
      // students who already have one for this billing month.
      final billingPeriod =
          DateFormat('yyyy-MM').format(_dueDateForMonth(_selectedMonth));
      final created = await _repo.generateForSection(
        sectionId: section.id,
        billingPeriod: billingPeriod,
        dueDate: _dueDateForMonth(_selectedMonth),
        monthlyFee: double.tryParse(_monthlyFeeCtrl.text) ?? 0,
        admissionFee: double.tryParse(_admissionFeeCtrl.text) ?? 0,
        examFee: double.tryParse(_examFeeCtrl.text) ?? 0,
        fine: double.tryParse(_fineCtrl.text) ?? 0,
      );
      final count = created.length;
      final skipped = section.studentIds.length - count;

      if (mounted) {
        final skippedNote = skipped > 0
            ? " ($skipped already had one or are inactive, skipped)"
            : "";
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "Generated $count challans for $_selectedMonth!$skippedNote"),
            backgroundColor: AppColors.success));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Generation failed: $e"),
            backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }
}
