import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/quiz_model.dart';
import '../models/app_user.dart';
import 'auth_service.dart';

class PdfGeneratorService {
  /// Print preview kholta hai
  static Future<void> printTestPaper(QuizModel quiz) async {
    final pdf = await _buildDocument(quiz);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '${quiz.title}_Paper',
    );
  }

  /// Share sheet kholta hai
  static Future<void> shareTestPaper(QuizModel quiz) async {
    final pdf = await _buildDocument(quiz);
    final bytes = await pdf.save();
    final safeName =
        quiz.title.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
    await Printing.sharePdf(bytes: bytes, filename: '$safeName.pdf');
  }

  /// PDF document banata hai
  static Future<pw.Document> _buildDocument(QuizModel quiz) async {
    // 1. Academy details come from the signed-in staff member's profile
    // (`/auth/me` includes the academy name, address, phone and logo).
    // Fails loudly rather than printing a paper without the academy header.
    final AppUser? academy = await AuthService().getCurrentUserProfile();
    if (academy == null) {
      throw StateError('Sign in again to load your academy details.');
    }

    // Load network image if logo exists
    pw.ImageProvider? logoImage;
    if (academy.academyLogo != null && academy.academyLogo!.isNotEmpty) {
      try {
        logoImage = await networkImage(academy.academyLogo!);
      } catch (e) {
        debugPrint("Could not load academy logo for Test PDF: $e");
      }
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Academy Header Section
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (logoImage != null)
                  pw.Container(
                    width: 50,
                    height: 50,
                    child: pw.Image(logoImage),
                  ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                          academy.academyName?.toUpperCase() ??
                              "TALEEMPLUS ACADEMY",
                          style: const pw.TextStyle(
                              fontSize: 18, fontWeight: pw.FontWeight.bold)),
                      pw.Text(academy.academyAddress ?? "",
                          style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
                pw.SizedBox(width: 50), // Balance the logo
              ],
            ),
            pw.Divider(thickness: 1, color: PdfColors.grey300),
            pw.SizedBox(height: 10),

            // Test Title Section
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(quiz.classLabel.toUpperCase(),
                      style: const pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.Text(quiz.title,
                      style: const pw.TextStyle(
                          fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Subject: ${quiz.subject}",
                      style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 2),
            pw.SizedBox(height: 10),

            // Student Info Section (Blank for physical test)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Month: ${quiz.month}"),
                pw.Text("Session: ${quiz.session}"),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Chapter: ${quiz.chapter}"),
                pw.Text("Difficulty: ${quiz.difficulty}"),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Student Name: __________________________"),
                pw.Text("Roll No: __________"),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Date: ________________"),
                pw.Text("Total Marks: ${quiz.totalMarks}",
                    style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.SizedBox(height: 20),

            // Instructions
            if (quiz.instructions.isNotEmpty) ...[
              pw.Text("Instructions:",
                  style: const pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text(quiz.instructions,
                  style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 20),
            ],

            // Questions Section — grouped into MCQ/Short/Long blocks, each
            // with its own "Section X (N Marks)" heading showing
            // count x per-question-mark, instead of one continuous list
            // with marks printed beside every individual question.
            ..._buildQuestionSections(quiz.questions),

            pw.Footer(
              margin: const pw.EdgeInsets.only(top: 20),
              trailing: pw.Text("Generated by TaleemPlus AI",
                  style:
                      const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
            ),
          ];
        },
      ),
    );

    return pdf;
  }

  /// Groups questions into MCQ -> Short -> Long blocks (skipping empty
  /// groups) and assigns section letters dynamically to whichever groups
  /// are actually present. Question numbering continues across sections
  /// (Q1..Qn MCQs, then Qn+1.. Short, etc.) rather than restarting per
  /// section.
  static List<pw.Widget> _buildQuestionSections(List<QuizQuestion> all) {
    final groups = [
      ('MCQs', all.where((q) => q.type == QuestionType.mcq).toList()),
      (
        'Short Questions',
        all.where((q) => q.type == QuestionType.short).toList()
      ),
      (
        'Long Questions',
        all.where((q) => q.type == QuestionType.long).toList()
      ),
    ];

    const letters = ['A', 'B', 'C'];
    final widgets = <pw.Widget>[];
    var questionNumber = 1;
    var letterIndex = 0;

    for (final (typeName, questions) in groups) {
      if (questions.isEmpty) continue;
      widgets.addAll(_buildSection(
        sectionLabel: 'Section ${letters[letterIndex]}',
        typeName: typeName,
        questions: questions,
        startNumber: questionNumber,
      ));
      questionNumber += questions.length;
      letterIndex++;
    }
    return widgets;
  }

  static List<pw.Widget> _buildSection({
    required String sectionLabel,
    required String typeName,
    required List<QuizQuestion> questions,
    required int startNumber,
  }) {
    final perQuestionMarks = questions.first.marks;
    final sectionTotal =
        questions.fold<double>(0, (total, q) => total + q.marks);

    String fmt(double v) =>
        v == v.roundToDouble() ? v.toInt().toString() : v.toString();

    return [
      pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('$sectionLabel (${fmt(sectionTotal)} Marks)',
                style: const pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.Text(
                '${questions.length} $typeName × ${fmt(perQuestionMarks)} '
                'Mark${perQuestionMarks == 1 ? '' : 's'}',
                style: const pw.TextStyle(
                    fontSize: 10, fontStyle: pw.FontStyle.italic)),
            pw.SizedBox(height: 4),
            pw.Text('Attempt all questions in this section.',
                style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      ),
      pw.SizedBox(height: 8),
      ...questions.asMap().entries.map((entry) {
        final i = entry.key;
        final q = entry.value;
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 16),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("Q${startNumber + i}. ",
                      style:
                          const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Expanded(
                    child: pw.Text(q.text,
                        style:
                            const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              if (q.type == QuestionType.mcq && q.options != null)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 20),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: q.options!.asMap().entries.map((optEntry) {
                      final optLetter = String.fromCharCode(65 + optEntry.key);
                      return pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 4),
                        child: pw.Text("$optLetter) ${optEntry.value}"),
                      );
                    }).toList(),
                  ),
                ),
              // Short/long questions print with no answer-writing space:
              // answer sheets are provided separately, so a blank box here
              // would just waste page space.
            ],
          ),
        );
      }),
      pw.SizedBox(height: 12),
    ];
  }
}
