import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/branding/branding_utils.dart';
import '../../core/branding/pdf_branding.dart';
import '../models/app_user.dart';
import '../models/fee_challan_model.dart';
import 'payment_service.dart';

/// Professional A4 fee challan carrying the academy's own identity
/// (logo, name, address, phone, email) and its configured payment details.
///
/// One page: letterhead → challan summary strip → student block → fee
/// breakdown → total + amount in words → payment instructions / bank
/// details / QR → signatures, then a tear-off academy copy stub.
class ChallanPdfService {
  static final _date = DateFormat('dd MMM yyyy');
  static final _money = NumberFormat('#,##0', 'en_US');

  /// Builds the PDF bytes. [paymentSettings] may be supplied to avoid a
  /// network call (tests, offline); otherwise they are fetched and any
  /// failure simply omits the payment block details.
  static Future<Uint8List> build(FeeChallanModel challan,
      {AppUser? academy, Map<String, dynamic>? paymentSettings}) async {
    final doc = await _buildDocument(challan, academy, paymentSettings);
    return doc.save();
  }

  static Future<pw.Document> _buildDocument(FeeChallanModel challan,
      AppUser? academy, Map<String, dynamic>? providedSettings) async {
    Map<String, dynamic> payment = providedSettings ?? const {};
    if (providedSettings == null) {
      try {
        payment = await PaymentService().getSettings();
      } catch (_) {
        // The challan stays printable without payment settings.
      }
    }
    pw.ImageProvider? qr;
    if (payment['enabled'] == true && payment['qrImageBase64'] is String) {
      final bytes =
          BrandingUtils.decodeLogo(payment['qrImageBase64'] as String);
      if (bytes != null) qr = pw.MemoryImage(bytes);
    }
    final logo = await PdfBranding.loadLogo(academy?.academyLogo);
    final theme = await PdfBranding.theme();
    final academyName = PdfBranding.academyName(academy);

    final doc = pw.Document(
      title: 'Fee Challan ${challan.challanNumber}',
      author: academyName,
      creator: academyName,
      subject: 'Fee challan for ${challan.studentName}',
    );

    doc.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 30),
          theme: theme,
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            PdfBranding.letterhead(academy, logo,
                title: 'FEE CHALLAN', meta: ['No. ${challan.challanNumber}']),
            pw.SizedBox(height: 12),
            _summaryStrip(challan),
            pw.SizedBox(height: 12),
            _studentBlock(challan),
            pw.SizedBox(height: 12),
            _feeTable(challan),
            pw.SizedBox(height: 8),
            _amountInWords(challan),
            pw.SizedBox(height: 14),
            _paymentBlock(challan, academy, payment, qr),
            pw.Spacer(),
            _signatures(),
            pw.SizedBox(height: 10),
            _tearOff(challan, academyName),
            pw.SizedBox(height: 6),
            PdfBranding.footer(context, academy,
                note:
                    '$academyName · Computer-generated challan · Generated with TaleemPlus'),
          ],
        ),
      ),
    );
    return doc;
  }

  // ------------------------------------------------------------ actions --

  /// Opens the platform print dialog (web: browser print; Android: system
  /// print service, which can also save to PDF).
  static Future<void> print(FeeChallanModel challan, {AppUser? academy}) async {
    final bytes = await build(challan, academy: academy);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: _fileName(challan),
    );
  }

  /// Saves the file: on web this triggers a browser download; on Android
  /// the system share sheet offers "Save to Files / Drive".
  static Future<void> download(FeeChallanModel challan,
      {AppUser? academy}) async {
    final bytes = await build(challan, academy: academy);
    await Printing.sharePdf(bytes: bytes, filename: _fileName(challan));
  }

  /// Shares the PDF through the platform share sheet.
  static Future<void> share(FeeChallanModel challan, {AppUser? academy}) async {
    final bytes = await build(challan, academy: academy);
    await Printing.sharePdf(bytes: bytes, filename: _fileName(challan));
  }

  // Backward-compatible names used by existing screens.
  static Future<void> generateAndPrint(FeeChallanModel challan,
          {AppUser? academy}) =>
      print(challan, academy: academy);
  static Future<void> generateAndShare(FeeChallanModel challan,
          {AppUser? academy}) =>
      share(challan, academy: academy);

  static String _fileName(FeeChallanModel c) {
    final safe = c.challanNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'Challan_$safe.pdf';
  }

  // ------------------------------------------------------------ sections --

  static pw.Widget _summaryStrip(FeeChallanModel c) {
    final status = c.effectiveStatus;
    final statusColor = status == 'paid'
        ? const PdfColor.fromInt(0xFF15803D)
        : status == 'overdue'
            ? const PdfColor.fromInt(0xFFB91C1C)
            : const PdfColor.fromInt(0xFFB45309);
    pw.Widget cell(String label, String value, {PdfColor? color}) =>
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label.toUpperCase(),
                  style: const pw.TextStyle(
                      fontSize: 7, color: PdfBranding.muted)),
              pw.SizedBox(height: 2),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: color ?? PdfBranding.ink)),
            ],
          ),
        );
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const pw.BoxDecoration(
          color: PdfBranding.brandLight,
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(6))),
      child: pw.Row(children: [
        cell('Fee month', DateFormat('MMMM yyyy').format(c.billingMonth)),
        cell('Issue date', _date.format(c.issueDate)),
        cell('Due date', _date.format(c.dueDate)),
        cell('Status', status.toUpperCase(), color: statusColor),
        cell('Amount payable', 'Rs. ${_money.format(c.totalAmount)}'),
      ]),
    );
  }

  static pw.Widget _studentBlock(FeeChallanModel c) {
    pw.Widget row(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2.2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 78,
                child: pw.Text(label,
                    style: const pw.TextStyle(
                        fontSize: 8.5, color: PdfBranding.muted)),
              ),
              pw.Expanded(
                child: pw.Text(value.isEmpty ? '—' : value,
                    style: pw.TextStyle(
                        fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
        );
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfBranding.line, width: 0.6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('STUDENT DETAILS',
              style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfBranding.brand,
                  letterSpacing: 0.8)),
          pw.SizedBox(height: 4),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(children: [
                  row('Student name', c.studentName),
                  row('Father name', c.fatherName),
                  row('Student ID',
                      c.studentCode.isEmpty ? c.studentId : c.studentCode),
                ]),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: pw.Column(children: [
                  row('Class', c.classLabel),
                  row('Roll number', c.rollNumber),
                  row('Challan ID', c.challanNumber),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _feeTable(FeeChallanModel c) {
    final items = <MapEntry<String, double>>[
      MapEntry('Monthly tuition fee', c.monthlyFee),
      if (c.admissionFee > 0) MapEntry('Admission fee', c.admissionFee),
      if (c.examFee > 0) MapEntry('Examination fee', c.examFee),
      if (c.transportFee > 0) MapEntry('Transport charges', c.transportFee),
      if (c.fine > 0) MapEntry('Fine / arrears', c.fine),
    ];
    const headStyle = pw.TextStyle(
        fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
    pw.Widget cell(String text,
            {pw.TextAlign align = pw.TextAlign.left,
            pw.TextStyle? style,
            PdfColor? background}) =>
        pw.Container(
          color: background,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: pw.Text(text,
              textAlign: align,
              style: style ?? const pw.TextStyle(fontSize: 9.5)),
        );
    var index = 0;
    return pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfBranding.line, width: 0.4),
        bottom: pw.BorderSide(color: PdfBranding.line, width: 0.6),
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(5),
        2: const pw.FlexColumnWidth(2.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfBranding.brand),
          children: [
            cell('#', style: headStyle),
            cell('Description', style: headStyle),
            cell('Amount (PKR)', align: pw.TextAlign.right, style: headStyle),
          ],
        ),
        for (final item in items)
          pw.TableRow(
            decoration: pw.BoxDecoration(
                color: (index++).isOdd
                    ? const PdfColor.fromInt(0xFFF8FAFA)
                    : PdfColors.white),
            children: [
              cell('$index',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfBranding.muted)),
              cell(item.key),
              cell(_money.format(item.value), align: pw.TextAlign.right),
            ],
          ),
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfBranding.brandLight),
          children: [
            cell(''),
            cell('TOTAL PAYABLE',
                style: pw.TextStyle(
                    fontSize: 10.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfBranding.brand)),
            cell('Rs. ${_money.format(c.totalAmount)}',
                align: pw.TextAlign.right,
                style: pw.TextStyle(
                    fontSize: 11.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfBranding.brand)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _amountInWords(FeeChallanModel c) => pw.Text(
        'Amount in words: ${amountInWords(c.totalAmount)} rupees only',
        style: const pw.TextStyle(fontSize: 8.5, color: PdfBranding.muted),
      );

  static pw.Widget _paymentBlock(FeeChallanModel c, AppUser? academy,
      Map<String, dynamic> payment, pw.ImageProvider? qr) {
    final enabled = payment['enabled'] == true;
    String text(String key) => (payment[key] ?? '').toString().trim();
    final rows = <List<String>>[
      if (enabled) ...[
        if (text('provider').isNotEmpty) ['Pay via', text('provider')],
        if (text('bankName').isNotEmpty) ['Bank', text('bankName')],
        if (text('accountTitle').isNotEmpty)
          ['Account title', text('accountTitle')],
        if (text('bankAccountNumber').isNotEmpty)
          ['Account number', text('bankAccountNumber')],
        if (text('bankIban').isNotEmpty) ['IBAN', text('bankIban')],
        if (text('accountDetails').isNotEmpty)
          ['Account / wallet', text('accountDetails')],
      ],
    ];
    final instructions = <String>[
      if (enabled && text('paymentInstructions').isNotEmpty)
        text('paymentInstructions'),
      'Quote challan ${c.challanNumber} as the payment reference.',
      'Pay on or before ${_date.format(c.dueDate)} to avoid a late fee.',
      if (!enabled)
        'For payment options contact ${PdfBranding.academyName(academy)}'
            '${(academy?.academyPhone ?? '').trim().isNotEmpty ? ' at ${academy!.academyPhone!.trim()}' : ''}.',
    ];
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfBranding.line, width: 0.6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('PAYMENT INSTRUCTIONS',
                    style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfBranding.brand,
                        letterSpacing: 0.8)),
                pw.SizedBox(height: 4),
                for (final row in rows)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.Row(children: [
                      pw.SizedBox(
                          width: 86,
                          child: pw.Text(row[0],
                              style: const pw.TextStyle(
                                  fontSize: 8.5, color: PdfBranding.muted))),
                      pw.Expanded(
                          child: pw.Text(row[1],
                              style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold))),
                    ]),
                  ),
                if (rows.isNotEmpty) pw.SizedBox(height: 3),
                for (final line in instructions)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 1.5),
                    child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('•  ',
                              style: const pw.TextStyle(fontSize: 8.5)),
                          pw.Expanded(
                              child: pw.Text(line,
                                  style: const pw.TextStyle(fontSize: 8.5))),
                        ]),
                  ),
              ],
            ),
          ),
          if (qr != null) ...[
            pw.SizedBox(width: 12),
            pw.Column(children: [
              pw.Container(
                  width: 74,
                  height: 74,
                  padding: const pw.EdgeInsets.all(3),
                  decoration: pw.BoxDecoration(
                      border:
                          pw.Border.all(color: PdfBranding.line, width: 0.6)),
                  child: pw.Image(qr, fit: pw.BoxFit.contain)),
              pw.SizedBox(height: 2),
              pw.Text('Scan to pay',
                  style: const pw.TextStyle(
                      fontSize: 7, color: PdfBranding.muted)),
            ]),
          ],
        ],
      ),
    );
  }

  static pw.Widget _signatures() => pw.Row(children: [
        pw.Expanded(child: _signatureLine('Fee clerk')),
        pw.SizedBox(width: 30),
        pw.Expanded(child: _signatureLine('Parent / guardian')),
        pw.SizedBox(width: 30),
        pw.Expanded(child: _signatureLine('Authorised signature & stamp')),
      ]);

  static pw.Widget _signatureLine(String label) => pw.Column(children: [
        pw.SizedBox(height: 20),
        pw.Container(height: 0.7, color: PdfBranding.ink),
        pw.SizedBox(height: 3),
        pw.Text(label,
            style: const pw.TextStyle(fontSize: 7.5, color: PdfBranding.muted)),
      ]);

  /// Tear-off stub the academy keeps when the fee is paid at the counter.
  static pw.Widget _tearOff(FeeChallanModel c, String academyName) {
    pw.Widget item(String label, String value) => pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label.toUpperCase(),
                  style: const pw.TextStyle(
                      fontSize: 6.5, color: PdfBranding.muted)),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        );
    return pw.Column(children: [
      pw.Row(children: [
        pw.Expanded(
            child: pw.Container(
                height: 0.6,
                decoration: const pw.BoxDecoration(
                    border: pw.Border(
                        top: pw.BorderSide(
                            color: PdfBranding.muted,
                            width: 0.6,
                            style: pw.BorderStyle.dashed))))),
        pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6),
            child: pw.Text('ACADEMY COPY',
                style: const pw.TextStyle(
                    fontSize: 6.5, color: PdfBranding.muted))),
        pw.Expanded(
            child: pw.Container(
                height: 0.6,
                decoration: const pw.BoxDecoration(
                    border: pw.Border(
                        top: pw.BorderSide(
                            color: PdfBranding.muted,
                            width: 0.6,
                            style: pw.BorderStyle.dashed))))),
      ]),
      pw.SizedBox(height: 6),
      pw.Row(children: [
        item('Academy', academyName),
        item('Challan', c.challanNumber),
        item('Student', c.studentName),
        item('Class', c.classLabel),
        item('Month', DateFormat('MMM yyyy').format(c.billingMonth)),
        item('Amount', 'Rs. ${_money.format(c.totalAmount)}'),
        item('Received by', '______________'),
      ]),
    ]);
  }

  // ------------------------------------------------------------ helpers --

  /// English words for a non-negative integer amount (Pakistani grouping:
  /// thousand, lakh, crore).
  @visibleForTesting
  static String amountInWords(double amount) {
    var n = amount.round();
    if (n <= 0) return 'Zero';
    const ones = [
      '',
      'One',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine',
      'Ten',
      'Eleven',
      'Twelve',
      'Thirteen',
      'Fourteen',
      'Fifteen',
      'Sixteen',
      'Seventeen',
      'Eighteen',
      'Nineteen'
    ];
    const tens = [
      '',
      '',
      'Twenty',
      'Thirty',
      'Forty',
      'Fifty',
      'Sixty',
      'Seventy',
      'Eighty',
      'Ninety'
    ];
    String below100(int v) => v < 20
        ? ones[v]
        : '${tens[v ~/ 10]}${v % 10 == 0 ? '' : ' ${ones[v % 10]}'}';
    String below1000(int v) {
      final h = v ~/ 100;
      final r = v % 100;
      return [
        if (h > 0) '${ones[h]} Hundred',
        if (r > 0) below100(r),
      ].join(' ');
    }

    final parts = <String>[];
    final crore = n ~/ 10000000;
    n %= 10000000;
    final lakh = n ~/ 100000;
    n %= 100000;
    final thousand = n ~/ 1000;
    n %= 1000;
    if (crore > 0) parts.add('${below100(crore)} Crore');
    if (lakh > 0) parts.add('${below100(lakh)} Lakh');
    if (thousand > 0) parts.add('${below100(thousand)} Thousand');
    if (n > 0) parts.add(below1000(n));
    return parts.join(' ');
  }
}
