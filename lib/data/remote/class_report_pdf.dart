import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/attendance_record.dart';
import '../models/class_entity.dart';
import '../models/test_mark_model.dart';

/// Class-level PDF reports built from API data (no network access here, so
/// they are unit-testable). Attendance % = (present + late) / days marked,
/// identical to the Excel export and the server's student reports.
class ClassReportPdf {
  static final _date = DateFormat('d MMM yyyy');

  static pw.Widget _header(String title, String academy, String subtitle) =>
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(academy,
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
        pw.Text(title,
            style: const pw.TextStyle(
                fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 12),
      ]);

  static pw.Widget _footer(pw.Context ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
            'Generated ${_date.format(DateTime.now())} · TaleemPlus · '
            'page ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      );

  /// One row per student with present/late/leave/absent and percentage, for
  /// a day (from == to) or any range such as a month.
  static Future<Uint8List> attendance({
    required String academyName,
    required ClassEntity cls,
    required List<AttendanceRecord> records,
    required DateTime from,
    required DateTime to,
  }) async {
    final ids = {...cls.studentIds, ...records.map((r) => r.studentId)};
    final names = {
      ...cls.studentNames,
      for (final r in records) r.studentId: r.studentName,
    };
    final rows = ids.map((id) {
      final own = records.where((r) => r.studentId == id).toList();
      int count(String s) => own.where((r) => r.status == s).length;
      final pct = own.isEmpty
          ? '—'
          : '${((count('present') + count('late')) * 100 / own.length).toStringAsFixed(1)}%';
      return [
        names[id] ?? id,
        '${count('present')}',
        '${count('late')}',
        '${count('leave')}',
        '${count('absent')}',
        '${own.length}',
        pct,
      ];
    }).toList()
      ..sort((a, b) => a[0].compareTo(b[0]));

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      footer: _footer,
      build: (_) => [
        _header(
            from == to ? 'Daily attendance' : 'Attendance report',
            academyName,
            '${cls.displayLabel}\n${from == to ? _date.format(from) : '${_date.format(from)} – ${_date.format(to)}'}'),
        if (rows.isEmpty)
          pw.Text('No attendance has been recorded for this period.')
        else
          pw.TableHelper.fromTextArray(
            headers: [
              'Student',
              'Present',
              'Late',
              'Leave',
              'Absent',
              'Days',
              '%'
            ],
            data: rows,
            headerStyle:
                const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.cyan100),
            cellAlignments: {
              for (var i = 1; i < 7; i++) i: pw.Alignment.center
            },
          ),
      ],
    ));
    return doc.save();
  }

  /// All test results of a class, plus each student's overall percentage.
  static Future<Uint8List> results({
    required String academyName,
    required ClassEntity cls,
    required List<TestMarkModel> marks,
    Map<String, String> quizTitles = const {},
  }) async {
    final sorted = [...marks]
      ..sort((a, b) => a.studentName.compareTo(b.studentName));
    final perStudent = <String, (String, double, double)>{};
    for (final m in sorted) {
      final p = perStudent[m.studentId];
      perStudent[m.studentId] = (
        m.studentName,
        (p?.$2 ?? 0) + m.marksObtained,
        (p?.$3 ?? 0) + m.totalMarks,
      );
    }
    String n(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      footer: _footer,
      build: (_) => [
        _header('Class results', academyName, cls.displayLabel),
        if (sorted.isEmpty)
          pw.Text('No marks have been entered for this class yet.')
        else ...[
          pw.TableHelper.fromTextArray(
            headers: ['Student', 'Test', 'Marks', '%', 'Grade'],
            data: [
              for (final m in sorted)
                [
                  m.studentName,
                  quizTitles[m.quizId] ?? m.subject,
                  '${n(m.marksObtained)} / ${n(m.totalMarks)}',
                  m.percentage.toStringAsFixed(1),
                  m.gradeLetter,
                ]
            ],
            headerStyle:
                const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.cyan100),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Overall',
              style: const pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Student', 'Obtained', 'Total', 'Overall %'],
            data: [
              for (final s in perStudent.values)
                [
                  s.$1,
                  n(s.$2),
                  n(s.$3),
                  s.$3 == 0 ? '—' : (s.$2 * 100 / s.$3).toStringAsFixed(1),
                ]
            ],
            headerStyle:
                const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.cyan100),
          ),
        ],
      ],
    ));
    return doc.save();
  }
}
