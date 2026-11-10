import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/quiz_model.dart';
import '../models/app_user.dart';
import 'auth_service.dart';

/// Builds professional Pakistani-academy examination papers (and a separate
/// teacher answer key) as A4 PDFs, matching the layout of a standard board /
/// academy paper: a full header block, a Section A multiple-choice table,
/// roman-numbered short-question groups with "attempt any N" instructions, and
/// a Part II of long questions.
///
/// The same document is used for on-screen preview, printing and download, so
/// what the teacher previews is byte-for-byte what prints.
class PdfGeneratorService {
  // ------------------------- Public entry points -------------------------

  /// Opens the OS print / print-preview dialog for the student paper.
  static Future<void> printTestPaper(QuizModel quiz) async {
    final academy = await _academy();
    final pdf = await _buildStudentPaper(quiz, academy);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '${_safe(quiz.title)}_Paper',
    );
  }

  /// Shares / downloads the student paper.
  static Future<void> shareTestPaper(QuizModel quiz) async {
    final academy = await _academy();
    final pdf = await _buildStudentPaper(quiz, academy);
    await Printing.sharePdf(
        bytes: await pdf.save(), filename: '${_safe(quiz.title)}_Paper.pdf');
  }

  /// Shares / downloads the teacher-only answer key.
  static Future<void> shareAnswerKey(QuizModel quiz) async {
    final academy = await _academy();
    final pdf = await _buildAnswerKey(quiz, academy);
    await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: '${_safe(quiz.title)}_Answer_Key.pdf');
  }

  /// Prints the teacher-only answer key.
  static Future<void> printAnswerKey(QuizModel quiz) async {
    final academy = await _academy();
    final pdf = await _buildAnswerKey(quiz, academy);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '${_safe(quiz.title)}_Answer_Key',
    );
  }

  /// Raw bytes of the student paper, for an in-app PDF preview widget.
  static Future<Uint8List> studentPaperBytes(QuizModel quiz) async =>
      (await _buildStudentPaper(quiz, await _academy())).save();

  /// Raw bytes of the answer key, for an in-app PDF preview widget.
  static Future<Uint8List> answerKeyBytes(QuizModel quiz) async =>
      (await _buildAnswerKey(quiz, await _academy())).save();

  /// Builds the student paper for a known academy (no network lookup). Used by
  /// tests and callers that already hold the academy profile.
  static Future<Uint8List> renderStudentPaper(
          QuizModel quiz, AppUser academy) async =>
      (await _buildStudentPaper(quiz, academy)).save();

  /// Builds the teacher answer key for a known academy (no network lookup).
  static Future<Uint8List> renderAnswerKey(
          QuizModel quiz, AppUser academy) async =>
      (await _buildAnswerKey(quiz, academy)).save();

  // ------------------------------ Styling --------------------------------

  static const _accent = PdfColor.fromInt(0xFF0B3D2E); // deep academic green
  static const double _pageMargin = 36;

  static pw.TextStyle _h(double size, {PdfColor? color}) => pw.TextStyle(
      fontSize: size, fontWeight: pw.FontWeight.bold, color: color);

  static pw.TextStyle _body(double size) => pw.TextStyle(fontSize: size);

  static String _safe(String s) =>
      s.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  static const _romans = [
    'i',
    'ii',
    'iii',
    'iv',
    'v',
    'vi',
    'vii',
    'viii',
    'ix',
    'x',
    'xi',
    'xii',
    'xiii',
    'xiv',
    'xv',
    'xvi',
    'xvii',
    'xviii',
    'xix',
    'xx',
  ];

  static String _roman(int i) => i < _romans.length ? _romans[i] : '${i + 1}';

  // Bundled Unicode font so the paper renders every glyph English papers need
  // (em dashes, ×, ÷, degrees, superscripts, bullets) instead of the built-in
  // Helvetica dropping any character outside Latin-1. Loaded once and cached.
  // Urdu glyphs need an additional Nastaliq font pack (planned) that would be
  // added to `fontFallback` here.
  static pw.ThemeData? _theme;

  static Future<pw.ThemeData> _loadTheme() async {
    if (_theme != null) return _theme!;
    try {
      final base = pw.Font.ttf(
          await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      final bold =
          pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
      final italic = pw.Font.ttf(
          await rootBundle.load('assets/fonts/NotoSans-Italic.ttf'));
      _theme = pw.ThemeData.withFont(
        base: base,
        bold: bold,
        italic: italic,
        fontFallback: [base],
      );
    } catch (e) {
      // Falls back to built-in fonts rather than failing to produce a paper.
      debugPrint('Could not load bundled PDF font, using default: $e');
      _theme = pw.ThemeData.base();
    }
    return _theme!;
  }

  static Future<AppUser> _academy() async {
    final AppUser? academy = await AuthService().getCurrentUserProfile();
    if (academy == null) {
      throw StateError('Sign in again to load your academy details.');
    }
    return academy;
  }

  static Future<pw.ImageProvider?> _logo(AppUser academy) async {
    if (academy.academyLogo == null || academy.academyLogo!.isEmpty) {
      return null;
    }
    try {
      return await networkImage(academy.academyLogo!);
    } catch (e) {
      debugPrint('Could not load academy logo for paper: $e');
      return null;
    }
  }

  /// Rebuilds the printed sections from the quiz. New papers carry explicit
  /// [QuizModel.sections]; legacy quizzes fall back to grouping the flat
  /// question list by type so they still render as a proper paper.
  static List<PaperSection> _sectionsOf(QuizModel quiz) {
    if (quiz.sections.isNotEmpty) return quiz.sections;
    final mcq =
        quiz.questions.where((q) => q.type == QuestionType.mcq).toList();
    final short =
        quiz.questions.where((q) => q.type == QuestionType.short).toList();
    final long =
        quiz.questions.where((q) => q.type == QuestionType.long).toList();
    final out = <PaperSection>[];
    if (mcq.isNotEmpty) {
      out.add(PaperSection(
        id: 'mcq',
        kind: SectionKind.mcq,
        heading: 'Section A',
        instruction: 'Attempt all of the following multiple choice questions.',
        marksPerQuestion: mcq.first.marks,
        attemptCount: null,
        questionIds: mcq.map((q) => q.id).toList(),
      ));
    }
    if (short.isNotEmpty) {
      out.add(PaperSection(
        id: 'short',
        kind: SectionKind.short,
        heading: '',
        instruction: 'Write short answers to the following parts.',
        marksPerQuestion: short.first.marks,
        attemptCount: short.length,
        questionIds: short.map((q) => q.id).toList(),
      ));
    }
    if (long.isNotEmpty) {
      out.add(PaperSection(
        id: 'long',
        kind: SectionKind.long,
        heading: 'Part II',
        instruction: 'Attempt the following questions.',
        marksPerQuestion: long.first.marks,
        attemptCount: long.length,
        questionIds: long.map((q) => q.id).toList(),
      ));
    }
    return out;
  }

  // --------------------------- Student paper -----------------------------

  static Future<pw.Document> _buildStudentPaper(
      QuizModel quiz, AppUser academy) async {
    final logo = await _logo(academy);
    final theme = await _loadTheme();
    final sections = _sectionsOf(quiz);
    final pdf = pw.Document(
      title: quiz.title,
      author: academy.academyName ?? 'TaleemPlus',
    );

    // Running question counter: the short/long block numbers continue after
    // the MCQ block (MCQ block is "Q1"; first short group becomes "2", etc.).
    var blockNumber = 1;

    pdf.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(theme),
        header: (ctx) =>
            ctx.pageNumber == 1 ? pw.SizedBox() : _runningHeader(quiz),
        footer: (ctx) => _footer(ctx),
        build: (ctx) {
          final widgets = <pw.Widget>[
            _paperHeader(quiz, academy, logo, answerKey: false),
            pw.SizedBox(height: 10),
          ];

          for (final section in sections) {
            switch (section.kind) {
              case SectionKind.mcq:
                widgets.addAll(_mcqSection(quiz, section, blockNumber));
                blockNumber++;
                break;
              case SectionKind.short:
                widgets.addAll(_shortSection(quiz, section, blockNumber));
                blockNumber++;
                break;
              case SectionKind.long:
                widgets.addAll(
                    _longSection(quiz, section, blockNumber, answerKey: false));
                blockNumber += section.questionIds.length;
                break;
            }
          }
          widgets.add(pw.SizedBox(height: 16));
          widgets.add(_endOfPaper());
          return widgets;
        },
      ),
    );
    return pdf;
  }

  // ----------------------------- Answer key ------------------------------

  static Future<pw.Document> _buildAnswerKey(
      QuizModel quiz, AppUser academy) async {
    final logo = await _logo(academy);
    final theme = await _loadTheme();
    final sections = _sectionsOf(quiz);
    final pdf = pw.Document(
      title: '${quiz.title} - Answer Key',
      author: academy.academyName ?? 'TaleemPlus',
    );
    var blockNumber = 1;

    pdf.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(theme),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : _runningHeader(quiz, suffix: 'Answer Key'),
        footer: (ctx) => _footer(ctx),
        build: (ctx) {
          final widgets = <pw.Widget>[
            _paperHeader(quiz, academy, logo, answerKey: true),
            pw.SizedBox(height: 6),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFFFF3CD),
                border: pw.Border.all(color: PdfColors.orange),
              ),
              child: pw.Text(
                'TEACHER COPY — CONFIDENTIAL. Do not distribute to students.',
                style: _h(10, color: const PdfColor.fromInt(0xFF8A6D00)),
              ),
            ),
            pw.SizedBox(height: 10),
          ];

          for (final section in sections) {
            switch (section.kind) {
              case SectionKind.mcq:
                widgets.addAll(_mcqAnswerKey(quiz, section, blockNumber));
                blockNumber++;
                break;
              case SectionKind.short:
                widgets.addAll(_shortAnswerKey(quiz, section, blockNumber));
                blockNumber++;
                break;
              case SectionKind.long:
                widgets.addAll(
                    _longSection(quiz, section, blockNumber, answerKey: true));
                blockNumber += section.questionIds.length;
                break;
            }
          }
          return widgets;
        },
      ),
    );
    return pdf;
  }

  // ------------------------------ Shared UI ------------------------------

  static pw.PageTheme _pageTheme(pw.ThemeData theme) => pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        margin: const pw.EdgeInsets.fromLTRB(
            _pageMargin, _pageMargin, _pageMargin, _pageMargin + 10),
      );

  static pw.Widget _runningHeader(QuizModel quiz, {String? suffix}) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('${quiz.subject} — ${quiz.effectiveExamType}',
              style: _body(9)),
          pw.Text(suffix ?? quiz.classLabel, style: _body(9)),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context ctx) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Generated with TaleemPlus',
              style: _body(8).copyWith(color: PdfColors.grey600)),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: _body(8).copyWith(color: PdfColors.grey600)),
        ],
      ),
    );
  }

  static pw.Widget _paperHeader(
    QuizModel quiz,
    AppUser academy,
    pw.ImageProvider? logo, {
    required bool answerKey,
  }) {
    final chapters = quiz.effectiveChapters;
    final totalMarks = quiz.computedTotalMarks;

    pw.Widget labelValue(String label, String value, {bool line = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.RichText(
          text: pw.TextSpan(children: [
            pw.TextSpan(text: '$label: ', style: _h(10)),
            pw.TextSpan(
                text: line && value.isEmpty ? '______________________' : value,
                style: _body(10)),
          ]),
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Academy banner
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null)
              pw.Container(width: 52, height: 52, child: pw.Image(logo))
            else
              pw.SizedBox(width: 52),
            pw.Expanded(
              child: pw.Column(children: [
                pw.Text(
                  (academy.academyName ?? 'TaleemPlus Academy').toUpperCase(),
                  textAlign: pw.TextAlign.center,
                  style: _h(18, color: _accent),
                ),
                if ((academy.academyAddress ?? '').isNotEmpty)
                  pw.Text(academy.academyAddress!,
                      textAlign: pw.TextAlign.center, style: _body(9)),
                if ((academy.academyPhone ?? '').isNotEmpty)
                  pw.Text('Phone: ${academy.academyPhone}',
                      textAlign: pw.TextAlign.center, style: _body(9)),
              ]),
            ),
            pw.SizedBox(width: 52),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Container(height: 2, color: _accent),
        pw.SizedBox(height: 6),
        // Exam title row
        pw.Center(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
            child: pw.Text(
              answerKey
                  ? '${quiz.effectiveExamType} — ANSWER KEY'
                  : quiz.effectiveExamType.toUpperCase(),
              style: _h(13),
            ),
          ),
        ),
        pw.SizedBox(height: 8),
        // Subject / class / time / marks grid
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  labelValue('Subject', quiz.subject),
                  labelValue('Class', quiz.classLabel),
                  if (chapters.isNotEmpty)
                    labelValue('Chapters', chapters.join(', ')),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                labelValue(
                    'Time Allowed',
                    quiz.timeAllowed.isNotEmpty
                        ? quiz.timeAllowed
                        : '____________'),
                labelValue('Total Marks', _fmt(totalMarks)),
                labelValue('Date', '', line: true),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 2),
        // Student identification (blank lines on the student paper)
        if (!answerKey) ...[
          pw.Container(height: 0.5, color: PdfColors.grey500),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              pw.Expanded(
                  flex: 3, child: labelValue('Student Name', '', line: true)),
              pw.SizedBox(width: 10),
              pw.Expanded(
                  flex: 2, child: labelValue('Roll No', '', line: true)),
              pw.SizedBox(width: 10),
              pw.Expanded(
                  flex: 2, child: labelValue('Section', '', line: true)),
            ],
          ),
        ],
        pw.Container(height: 0.5, color: PdfColors.grey500),
        pw.SizedBox(height: 6),
        if (quiz.instructions.trim().isNotEmpty)
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF3F6F4),
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.RichText(
              text: pw.TextSpan(children: [
                pw.TextSpan(text: 'Instructions: ', style: _h(9)),
                pw.TextSpan(text: quiz.instructions, style: _body(9)),
              ]),
            ),
          ),
      ],
    );
  }

  static pw.Widget _sectionHeading(String left, String marks) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12, bottom: 6),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8EFEA)),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(left, style: _h(12, color: _accent)),
          pw.Text(marks, style: _h(11, color: _accent)),
        ],
      ),
    );
  }

  // -- Section A: MCQ table (No. | Question | A | B | C | D) --

  static List<pw.Widget> _mcqSection(
      QuizModel quiz, PaperSection section, int blockNo) {
    final mcqs = section.questionIds
        .map(quiz.questionById)
        .whereType<QuizQuestion>()
        .toList();
    if (mcqs.isEmpty) return [];
    final total = mcqs.length * section.marksPerQuestion;

    return [
      _sectionHeading(
        'SECTION A — Multiple Choice Questions',
        '(${_fmt(total)} Marks)',
      ),
      pw.Text(
        'Q$blockNo. ${section.instruction} '
        'Each question carries ${_fmt(section.marksPerQuestion)} mark'
        '${section.marksPerQuestion == 1 ? '' : 's'}.',
        style: _body(9).copyWith(fontStyle: pw.FontStyle.italic),
      ),
      pw.SizedBox(height: 6),
      _mcqTable(mcqs, answerKey: false),
    ];
  }

  static List<pw.Widget> _mcqAnswerKey(
      QuizModel quiz, PaperSection section, int blockNo) {
    final mcqs = section.questionIds
        .map(quiz.questionById)
        .whereType<QuizQuestion>()
        .toList();
    if (mcqs.isEmpty) return [];
    return [
      _sectionHeading('SECTION A — MCQ Answers', ''),
      _mcqTable(mcqs, answerKey: true),
    ];
  }

  static pw.Widget _mcqTable(List<QuizQuestion> mcqs,
      {required bool answerKey}) {
    const headerStyleSize = 9.0;
    final headers = answerKey
        ? ['No.', 'Question', 'A', 'B', 'C', 'D', 'Ans']
        : ['No.', 'Question', 'A', 'B', 'C', 'D'];

    pw.Widget cell(String text,
        {pw.TextAlign align = pw.TextAlign.left,
        bool bold = false,
        PdfColor? bg}) {
      return pw.Container(
        color: bg,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(text,
            textAlign: align,
            style: bold ? _h(headerStyleSize) : _body(headerStyleSize)),
      );
    }

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFDDE7E1)),
        children: [
          cell(headers[0], align: pw.TextAlign.center, bold: true),
          cell(headers[1], bold: true),
          for (var i = 2; i < headers.length; i++)
            cell(headers[i], align: pw.TextAlign.center, bold: true),
        ],
      ),
    ];

    for (var i = 0; i < mcqs.length; i++) {
      final q = mcqs[i];
      final opts = q.options ?? const [];
      String opt(int idx) => idx < opts.length ? opts[idx] : '';
      final correct = q.correctIndex;
      PdfColor? mark(int idx) => answerKey && correct == idx
          ? const PdfColor.fromInt(0xFFCDE9D5)
          : null;

      rows.add(pw.TableRow(children: [
        cell('${i + 1}', align: pw.TextAlign.center),
        cell(q.text),
        cell(opt(0), bg: mark(0)),
        cell(opt(1), bg: mark(1)),
        cell(opt(2), bg: mark(2)),
        cell(opt(3), bg: mark(3)),
        if (answerKey)
          cell(
            correct != null && correct >= 0 && correct < 4
                ? String.fromCharCode(65 + correct)
                : '-',
            align: pw.TextAlign.center,
            bold: true,
          ),
      ]));
    }

    final widths = answerKey
        ? <int, pw.TableColumnWidth>{
            0: const pw.FixedColumnWidth(26),
            1: const pw.FlexColumnWidth(5),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(2),
            4: const pw.FlexColumnWidth(2),
            5: const pw.FlexColumnWidth(2),
            6: const pw.FixedColumnWidth(28),
          }
        : <int, pw.TableColumnWidth>{
            0: const pw.FixedColumnWidth(26),
            1: const pw.FlexColumnWidth(5),
            2: const pw.FlexColumnWidth(2.2),
            3: const pw.FlexColumnWidth(2.2),
            4: const pw.FlexColumnWidth(2.2),
            5: const pw.FlexColumnWidth(2.2),
          };

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
      columnWidths: widths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  // -- Short-question group: "N. Write short answers to any X parts" --

  static List<pw.Widget> _shortSection(
      QuizModel quiz, PaperSection section, int blockNo) {
    final parts = section.questionIds
        .map(quiz.questionById)
        .whereType<QuizQuestion>()
        .toList();
    if (parts.isEmpty) return [];
    final attempt =
        (section.attemptCount ?? parts.length).clamp(1, parts.length);
    final equation = '(${_fmt(section.marksPerQuestion)}×$attempt='
        '${_fmt(section.marksPerQuestion * attempt)} Marks)';

    return [
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 2),
        child: pw.RichText(
          text: pw.TextSpan(children: [
            pw.TextSpan(text: '$blockNo. ', style: _h(11)),
            pw.TextSpan(text: section.instruction, style: _h(11)),
            pw.TextSpan(text: '   $equation', style: _h(10, color: _accent)),
          ]),
        ),
      ),
      // Keep each part with its number; wrap neatly in two readable columns
      // when short — but default to single-column for reliable wrapping.
      ...parts.asMap().entries.map((e) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(left: 12, top: 4, bottom: 2),
          child: pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(text: '(${_roman(e.key)}) ', style: _h(10)),
              pw.TextSpan(text: e.value.text, style: _body(10)),
            ]),
          ),
        );
      }),
    ];
  }

  static List<pw.Widget> _shortAnswerKey(
      QuizModel quiz, PaperSection section, int blockNo) {
    final parts = section.questionIds
        .map(quiz.questionById)
        .whereType<QuizQuestion>()
        .toList();
    if (parts.isEmpty) return [];
    return [
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 2),
        child: pw.Text('$blockNo. Short Questions — Model Answers',
            style: _h(11, color: _accent)),
      ),
      ...parts.asMap().entries.map((e) {
        final q = e.value;
        return pw.Container(
          margin: const pw.EdgeInsets.only(left: 12, top: 4, bottom: 4),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.RichText(
                text: pw.TextSpan(children: [
                  pw.TextSpan(text: '(${_roman(e.key)}) ', style: _h(10)),
                  pw.TextSpan(text: q.text, style: _h(10)),
                ]),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 14, top: 2),
                child: pw.Text(
                  q.answerText?.trim().isNotEmpty == true
                      ? q.answerText!
                      : '(No model answer recorded.)',
                  style: _body(9).copyWith(color: PdfColors.grey800),
                ),
              ),
            ],
          ),
        );
      }),
    ];
  }

  // -- Part II: long questions (continuous numbering) --

  static List<pw.Widget> _longSection(
      QuizModel quiz, PaperSection section, int startNo,
      {required bool answerKey}) {
    final longs = section.questionIds
        .map(quiz.questionById)
        .whereType<QuizQuestion>()
        .toList();
    if (longs.isEmpty) return [];
    final attempt =
        (section.attemptCount ?? longs.length).clamp(1, longs.length);
    final equation = '(${_fmt(section.marksPerQuestion)}×$attempt='
        '${_fmt(section.marksPerQuestion * attempt)} Marks)';

    final widgets = <pw.Widget>[
      _sectionHeading(
        'PART II — Long Questions',
        answerKey ? '' : equation,
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Text(section.instruction,
            style: _body(9).copyWith(fontStyle: pw.FontStyle.italic)),
      ),
    ];

    for (var i = 0; i < longs.length; i++) {
      final q = longs[i];
      widgets.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.RichText(
              text: pw.TextSpan(children: [
                pw.TextSpan(text: '${startNo + i}. ', style: _h(11)),
                pw.TextSpan(text: q.text, style: _h(11)),
                pw.TextSpan(
                    text: '   (${_fmt(q.marks)})',
                    style: _body(9).copyWith(color: PdfColors.grey700)),
              ]),
            ),
            if (answerKey)
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 14, top: 3),
                child: pw.Text(
                  q.answerText?.trim().isNotEmpty == true
                      ? q.answerText!
                      : '(No marking guideline recorded.)',
                  style: _body(9).copyWith(color: PdfColors.grey800),
                ),
              )
            else
              // Light writing space hint for long answers on the student copy.
              pw.Container(),
          ],
        ),
      ));
    }
    return widgets;
  }

  static pw.Widget _endOfPaper() {
    return pw.Center(
      child: pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Text('— END OF PAPER —',
            style: _h(10, color: PdfColors.grey700)),
      ),
    );
  }
}
