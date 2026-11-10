import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/fee_challan_model.dart';
import '../models/app_user.dart';
import 'payment_service.dart';

class ChallanPdfService {
  static Future<pw.Document> _buildDocument(
      FeeChallanModel challan, AppUser? academy) async {
    final doc = pw.Document();
    Map<String, dynamic> paymentSettings = const {};
    try {
      paymentSettings = await PaymentService().getSettings();
    } catch (_) {
      // The challan remains printable when payment settings are unavailable.
    }
    pw.ImageProvider? paymentQr;
    if (paymentSettings['enabled'] == true &&
        paymentSettings['qrImageBase64'] is String) {
      try {
        paymentQr = pw.MemoryImage(
            base64Decode(paymentSettings['qrImageBase64'] as String));
      } catch (_) {
        paymentQr = null;
      }
    }

    // Load network image if logo exists
    pw.ImageProvider? logoImage;
    if (academy?.academyLogo != null && academy!.academyLogo!.isNotEmpty) {
      try {
        logoImage = await networkImage(academy.academyLogo!);
      } catch (e) {
        debugPrint("Could not load academy logo for PDF: $e");
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 34, 34, 42),
        build: (pw.Context context) {
          return [
            _buildHeader(challan, academy, logoImage),
            pw.SizedBox(height: 16),
            _buildStudentInfo(challan),
            pw.SizedBox(height: 16),
            _buildFeeTable(challan),
            pw.SizedBox(height: 22),
            _buildFooter(challan, academy, paymentSettings, paymentQr),
            pw.SizedBox(height: 28),
            _signatureBlock(),
          ];
        },
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ),
      ),
    );

    return doc;
  }

  static Future<void> generateAndPrint(FeeChallanModel challan,
      {AppUser? academy}) async {
    try {
      final doc = await _buildDocument(challan, academy);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Challan_${challan.challanNumber}',
      );
    } catch (e) {
      debugPrint("PDF Error: $e");
      rethrow;
    }
  }

  static Future<void> generateAndShare(FeeChallanModel challan,
      {AppUser? academy}) async {
    try {
      final doc = await _buildDocument(challan, academy);
      final bytes = await doc.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Challan_${challan.challanNumber}.pdf',
      );
    } catch (e) {
      debugPrint("PDF Share Error: $e");
      rethrow;
    }
  }

  static pw.Widget _buildHeader(
      FeeChallanModel challan, AppUser? academy, pw.ImageProvider? logo) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            if (logo != null)
              pw.Container(
                width: 60,
                height: 60,
                margin: const pw.EdgeInsets.only(right: 12),
                child: pw.Image(logo),
              ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                    academy?.academyName?.toUpperCase() ?? "TALEEMPLUS ACADEMY",
                    style: const pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Text(academy?.academyAddress ?? "Academy Address Not Set",
                    style: const pw.TextStyle(fontSize: 9)),
                pw.Text("Contact: ${academy?.academyPhone ?? 'N/A'}",
                    style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text("FEE CHALLAN",
                style: const pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.cyan900)),
            pw.Text("No: ${challan.challanNumber}",
                style: const pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text(
                "Date: ${DateFormat('dd-MMM-yyyy').format(challan.issueDate)}",
                style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildStudentInfo(FeeChallanModel challan) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _infoRow("Student Name", challan.studentName),
                _infoRow("Father Name", challan.fatherName),
                _infoRow(
                    "Student ID",
                    challan.studentCode.isEmpty
                        ? challan.studentId
                        : challan.studentCode),
                _infoRow("Fee Month",
                    DateFormat('MMMM yyyy').format(challan.billingMonth)),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _infoRow("Class", challan.classLabel),
                _infoRow("Roll No", challan.rollNumber),
                _infoRow("Due Date",
                    DateFormat('dd-MMM-yyyy').format(challan.dueDate)),
                _infoRow("Payment Status",
                    challan.effectiveStatus.toUpperCase()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _infoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
                text: "$label: ",
                style: const pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildFeeTable(FeeChallanModel challan) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text("Description",
                    style: const pw.TextStyle(fontWeight: pw.FontWeight.bold))),
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text("Amount (PKR)",
                    textAlign: pw.TextAlign.right,
                    style: const pw.TextStyle(fontWeight: pw.FontWeight.bold))),
          ],
        ),
        _tableRow("Monthly Tuition Fee", challan.monthlyFee),
        _tableRow("Admission Fee", challan.admissionFee),
        _tableRow("Examination Fee", challan.examFee),
        _tableRow("Transport Charges", challan.transportFee),
        _tableRow("Fine / Arrears", challan.fine),
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey50),
          children: [
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text("Total Payable",
                    style: const pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 14))),
            pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text("Rs. ${challan.totalAmount.toStringAsFixed(0)}",
                    textAlign: pw.TextAlign.right,
                    style: const pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 14))),
          ],
        ),
      ],
    );
  }

  static pw.TableRow _tableRow(String desc, double amount) {
    return pw.TableRow(
      children: [
        pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Text(desc, style: const pw.TextStyle(fontSize: 10))),
        pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Text(amount.toStringAsFixed(0),
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 10))),
      ],
    );
  }

  static pw.Widget _buildFooter(FeeChallanModel challan, AppUser? academy,
      Map<String, dynamic> paymentSettings, pw.ImageProvider? paymentQr) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("PAYMENT INSTRUCTIONS:",
                  style: const pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 10)),
              if (paymentSettings['enabled'] == true) ...[
                if ((paymentSettings['provider'] ?? '').toString().isNotEmpty)
                  pw.Text('Provider: ${paymentSettings['provider']}',
                      style: const pw.TextStyle(fontSize: 9)),
                if ((paymentSettings['accountTitle'] ?? '')
                    .toString()
                    .isNotEmpty)
                  pw.Text('Account title: ${paymentSettings['accountTitle']}',
                      style: const pw.TextStyle(fontSize: 9)),
                if ((paymentSettings['accountDetails'] ?? '')
                    .toString()
                    .isNotEmpty)
                  pw.Text(
                      'Account details: ${paymentSettings['accountDetails']}',
                      style: const pw.TextStyle(fontSize: 9)),
                pw.Text(
                    'Include challan ${challan.challanNumber} in payment reference.',
                    style: const pw.TextStyle(fontSize: 9)),
              ] else ...[
                pw.Text(
                    'Payment details: Contact ${academy?.academyName ?? 'your academy'}.',
                    style: const pw.TextStyle(fontSize: 9)),
                if ((academy?.academyPhone ?? '').isNotEmpty)
                  pw.Text('Academy contact: ${academy!.academyPhone}',
                      style: const pw.TextStyle(fontSize: 9)),
              ],
              pw.Text("Challan reference: ${challan.challanNumber}",
                  style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
        if (paymentQr != null)
          pw.Container(
              width: 76,
              height: 76,
              margin: const pw.EdgeInsets.only(left: 12),
              child: pw.Image(paymentQr)),
      ],
    );
  }

  static pw.Widget _signatureBlock() => pw.Row(children: [
        pw.Expanded(child: _signatureLine('Fee clerk')),
        pw.SizedBox(width: 28),
        pw.Expanded(child: _signatureLine('Authorized signature / stamp')),
      ]);

  static pw.Widget _signatureLine(String label) => pw.Column(children: [
        pw.SizedBox(height: 22),
        pw.Container(height: .7, color: PdfColors.grey700),
        pw.SizedBox(height: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
      ]);
}
