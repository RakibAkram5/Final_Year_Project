import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';
import '../../../data/models/fee_challan_model.dart';
import '../../../data/repositories/fee_challan_repository.dart';
import '../../../data/remote/challan_pdf_service.dart';
import '../../../logic/auth_provider.dart';
import '../../../data/remote/payment_service.dart';

class StudentChallanScreen extends StatefulWidget {
  final String studentUid;
  const StudentChallanScreen({super.key, required this.studentUid});

  @override
  State<StudentChallanScreen> createState() => _StudentChallanScreenState();
}

class _StudentChallanScreenState extends State<StudentChallanScreen> {
  final _repo = FeeChallanRepository();
  bool _loading = true;
  String? _errorMessage;
  FeeChallanModel? _latestChallan;
  Map<String, dynamic>? _paymentSettings;
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
    _loadChallan();
  }

  Future<void> _loadChallan() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final academyId = Provider.of<AuthProvider>(context, listen: false)
              .currentUser
              ?.academyId ??
          '';

      // Passing the month and academyId to filter specifically
      final c = await _repo.getLatestForStudent(widget.studentUid, academyId,
          month: _selectedBillingPeriod);
      Map<String, dynamic>? settings;
      try {
        settings = await PaymentService().getSettings();
      } catch (_) {
        // Keep the challan available if payment settings cannot be fetched.
      }

      if (mounted) {
        setState(() {
          _latestChallan = c;
          _paymentSettings = settings;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _loading = false;
        });
      }
    }
  }

  String get _selectedBillingPeriod {
    final month = _months.indexOf(_selectedMonth) + 1;
    var year = DateTime.now().year;
    if (month < DateTime.now().month) year++;
    return '$year-${month.toString().padLeft(2, '0')}';
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
        title: const Text('Fee Challan',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _body(),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    final navSections = buildParentNavSections(context,
        onDashboard: () => Navigator.of(context).popUntil((r) => r.isFirst));
    return WebAppShell(
      title: 'Fee Challan',
      titleIcon: Icons.receipt_long_rounded,
      navSections: navSections,
      activeNavId: 'dashboard',
      user: context.watch<AuthProvider>().currentUser,
      onLogout: () => performWebLogout(context),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    return Column(
      children: [
        _buildMonthFilter(),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.accent))
              : _errorMessage != null
                  ? _buildErrorState()
                  : _latestChallan == null
                      ? _buildEmptyState()
                      : _buildChallanDetails(),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.danger, size: 48),
            const SizedBox(height: 16),
            Text(
              "Error loading challan: $_errorMessage",
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.danger),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadChallan,
              child: const Text("RETRY"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: context.appColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: context.appColors.border.withValues(alpha: 0.5)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedMonth,
            isExpanded: true,
            dropdownColor: context.appColors.surfaceAlt,
            items: _months
                .map((m) => DropdownMenuItem(
                    value: m,
                    child: Text(m,
                        style:
                            TextStyle(color: context.appColors.textPrimary))))
                .toList(),
            onChanged: (v) {
              setState(() => _selectedMonth = v!);
              _loadChallan();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildChallanDetails() {
    if (_latestChallan == null) return _buildEmptyState();
    final c = _latestChallan!;
    final bool isOverdue = c.isOverdue;
    final statusColor = c.isPaid
        ? AppColors.success
        : (isOverdue ? AppColors.danger : AppColors.warning);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildStatusCard(c, statusColor),
        const SizedBox(height: 20),
        _buildDigitalPreview(c),
        const SizedBox(height: 24),
        _buildActionButtons(c),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildStatusCard(FeeChallanModel c, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(
                c.isPaid
                    ? Icons.check_circle_rounded
                    : Icons.pending_actions_rounded,
                color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.status.toUpperCase(),
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontSize: 16)),
                Text(
                    c.isPaid
                        ? "Payment received"
                        : "Due Date: ${DateFormat('dd MMM yyyy').format(c.dueDate)}",
                    style: TextStyle(
                        color: context.appColors.textMuted, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDigitalPreview(FeeChallanModel c) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: context.appColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("TOTAL PAYABLE",
              style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
          const SizedBox(height: 4),
          Text("Rs. ${c.totalAmount.toStringAsFixed(0)}",
              style: TextStyle(
                  color: context.appColors.accentText,
                  fontSize: 32,
                  fontWeight: FontWeight.w900)),
          Divider(height: 32, color: context.appColors.border),
          _previewRow("Student", c.studentName),
          _previewRow("Challan #", c.challanNumber),
          _previewRow("Monthly Fee", "Rs. ${c.monthlyFee}"),
          if (c.fine > 0) _previewRow("Fine", "Rs. ${c.fine}", isDanger: true),
          const SizedBox(height: 24),
          Center(
            child: Text(
                'Use challan reference ${c.challanNumber} when contacting the academy.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: context.appColors.textMuted, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _previewRow(String label, String val, {bool isDanger = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: context.appColors.textSecondary, fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(val,
                textAlign: TextAlign.end,
                style: TextStyle(
                    color: isDanger
                        ? AppColors.danger
                        : context.appColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePrint(FeeChallanModel c) async {
    try {
      await ChallanPdfService.generateAndPrint(
        c,
        academy: context.read<AuthProvider>().currentUser,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Print Error: $e"),
              backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _handleShare(FeeChallanModel c) async {
    try {
      await ChallanPdfService.generateAndShare(
        c,
        academy: context.read<AuthProvider>().currentUser,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Share Error: $e"),
              backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Widget _buildActionButtons(FeeChallanModel c) {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: () => _showPaymentInstructions(c),
          icon: const Icon(Icons.payment_rounded),
          label: const Text("PAY NOW"),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.textOnAccent,
            minimumSize: const Size(double.infinity, 44),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _handlePrint(c),
                icon: const Icon(Icons.print_rounded),
                label: const Text("PRINT"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _handleShare(c),
                icon: const Icon(Icons.share_rounded),
                label: const Text("SHARE"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showPaymentInstructions(FeeChallanModel c) {
    final academy = context.read<AuthProvider>().currentUser;
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("Payment Instructions",
                  style: TextStyle(
                      color: context.appColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              _instructionRow(
                  Icons.school_rounded,
                  "Academy",
                  (_paymentSettings?['academyName'] ??
                          academy?.academyName ??
                          'TaleemPlus Academy')
                      .toString()),
              if (_paymentSettings?['enabled'] == true) ...[
                if ((_paymentSettings?['provider'] ?? '').toString().isNotEmpty)
                  _instructionRow(Icons.account_balance_wallet_rounded,
                      'Provider', _paymentSettings!['provider'].toString()),
                if ((_paymentSettings?['accountTitle'] ?? '')
                    .toString()
                    .isNotEmpty)
                  _instructionRow(Icons.person_outline_rounded, 'Account title',
                      _paymentSettings!['accountTitle'].toString()),
                if ((_paymentSettings?['accountDetails'] ?? '')
                    .toString()
                    .isNotEmpty)
                  _instructionRow(Icons.numbers_rounded, 'Account details',
                      _paymentSettings!['accountDetails'].toString()),
                for (final (key, icon, label) in const [
                  ('bankName', Icons.account_balance_rounded, 'Bank'),
                  ('bankAccountNumber', Icons.pin_rounded, 'Account number'),
                  ('bankIban', Icons.credit_card_rounded, 'IBAN'),
                  (
                    'paymentInstructions',
                    Icons.info_outline_rounded,
                    'Instructions'
                  ),
                ])
                  if ((_paymentSettings?[key] ?? '').toString().isNotEmpty)
                    _instructionRow(
                        icon, label, _paymentSettings![key].toString()),
                if ((_paymentSettings?['qrImageBase64'] ?? '')
                    .toString()
                    .isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Image.memory(
                      base64Decode(
                          _paymentSettings!['qrImageBase64'] as String),
                      height: 190,
                      fit: BoxFit.contain,
                    ),
                  ),
                Text(
                    'Include the challan reference in your transfer details. Payment is recorded only after academy verification.',
                    style: TextStyle(
                        color: context.appColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: c.isPaid
                      ? null
                      : () async {
                          final image = await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 80,
                              maxWidth: 1400,
                              maxHeight: 1400);
                          if (image == null) return;
                          try {
                            await PaymentService().submitProof(c.id, image);
                            if (!ctx.mounted || !mounted) return;
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Payment proof submitted for academy review.')));
                          } catch (error) {
                            if (!ctx.mounted || !mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content:
                                    Text('Could not submit proof: $error')));
                          }
                        },
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Submit payment proof'),
                ),
              ] else
                const Text(
                    'Payment instructions are not configured for this academy. Contact the academy administrator before sending money.',
                    style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              if ((academy?.academyPhone ?? '').isNotEmpty)
                _instructionRow(
                    Icons.phone_rounded, "Contact", academy!.academyPhone!),
              _instructionRow(Icons.receipt_long_rounded, "Challan reference",
                  c.challanNumber),
              _instructionRow(Icons.payments_rounded, "Amount due",
                  "Rs. ${c.totalAmount.toStringAsFixed(2)}"),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _instructionRow(IconData icon, String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: context.appColors.accentText, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: context.appColors.textMuted, fontSize: 11)),
                // Selectable so parents can copy the IBAN / account number.
                SelectableText(val,
                    style: TextStyle(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_rounded,
              size: 64, color: context.appColors.textMuted),
          const SizedBox(height: 16),
          Text("No challans available for this month.",
              style: TextStyle(color: context.appColors.textSecondary)),
        ],
      ),
    );
  }
}
