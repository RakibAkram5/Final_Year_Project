// Responsive layout regression tests.
//
// Every major screen of the four portals is rendered with REAL recorded API
// responses (test/fixtures/ui_api_fixtures.json, which include deliberately
// long [TEST] class and student names) at each viewport in the test plan.
// A screen fails when it:
//   * reports a layout error (RenderFlex overflow, unbounded constraints...),
//   * throws during build, or
//   * squeezes a text into a column so narrow that words break mid-word
//     (the Class Management bug: a 12+ character label laid out in < 72 px
//     across several lines).
//
// Run: flutter test test/responsive_layout_test.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:taleemplus_app/core/constants/app_constants.dart';
import 'package:taleemplus_app/data/models/app_user.dart';
import 'package:taleemplus_app/data/models/class_entity.dart';
import 'package:taleemplus_app/data/remote/assignment_service.dart';
import 'package:taleemplus_app/data/remote/file_service.dart';
import 'package:taleemplus_app/features/shared/assignments_screen.dart';
import 'package:taleemplus_app/features/shared/documents_screen.dart';
import 'package:taleemplus_app/features/shared/reports_screen.dart';
import 'package:taleemplus_app/features/shared/academy_location.dart';
import 'package:taleemplus_app/features/admin/admin_ai_prediction_screen.dart';
import 'package:taleemplus_app/features/admin/admin_dashboard.dart';
import 'package:taleemplus_app/features/admin/admin_quiz_list_screen.dart';
import 'package:taleemplus_app/features/admin/announcements_screen.dart';
import 'package:taleemplus_app/features/admin/approval_requests_screen.dart';
import 'package:taleemplus_app/features/admin/class_management_screen.dart';
import 'package:taleemplus_app/features/admin/class_sections_screen.dart';
import 'package:taleemplus_app/features/admin/fee_ledger_screen.dart';
import 'package:taleemplus_app/features/admin/screens/academic_structure_screen.dart';
import 'package:taleemplus_app/features/admin/screens/academy_payment_settings_screen.dart';
import 'package:taleemplus_app/features/admin/screens/challan_generation_screen.dart';
import 'package:taleemplus_app/features/admin/screens/class_fee_status_screen.dart';
import 'package:taleemplus_app/features/admin/screens/class_reports_screen.dart';
import 'package:taleemplus_app/features/admin/screens/timetable_management_screen.dart';
import 'package:taleemplus_app/features/admin/screens/unpaid_students_screen.dart';
import 'package:taleemplus_app/features/admin/user_management_screen.dart';
import 'package:taleemplus_app/features/auth/login_screen.dart';
import 'package:taleemplus_app/features/auth/signup_screen.dart';
import 'package:taleemplus_app/features/parent/parent_dashboard.dart';
import 'package:taleemplus_app/features/parent/screens/academy_contact_screen.dart';
import 'package:taleemplus_app/features/parent/screens/all_challans_screen.dart';
import 'package:taleemplus_app/features/parent/screens/child_alerts_screen.dart';
import 'package:taleemplus_app/features/parent/screens/child_overview_screen.dart';
import 'package:taleemplus_app/features/parent/screens/child_timetable_screen.dart';
import 'package:taleemplus_app/features/parent/screens/student_challan_screen.dart';
import 'package:taleemplus_app/features/quiz/screens/monthly_report_screen.dart';
import 'package:taleemplus_app/features/quiz/screens/student_test_report_screen.dart';
import 'package:taleemplus_app/features/quiz/screens/teacher_quiz_list_screen.dart';
import 'package:taleemplus_app/features/shared/notifications_screen.dart';
import 'package:taleemplus_app/features/shared/view_announcements_screen.dart';
import 'package:taleemplus_app/features/student/screens/ai_summarizer_screen.dart';
import 'package:taleemplus_app/features/student/screens/my_classroom_hub.dart';
import 'package:taleemplus_app/features/student/screens/my_timetable_screen.dart'
    as student_tt;
import 'package:taleemplus_app/features/student/screens/student_attendance_screen.dart';
import 'package:taleemplus_app/features/student/screens/student_fee_screen.dart';
import 'package:taleemplus_app/features/student/screens/student_progress_chart_screen.dart';
import 'package:taleemplus_app/features/student/screens/teacher_details_screen.dart';
import 'package:taleemplus_app/features/student/student_dashboard.dart';
import 'package:taleemplus_app/features/teacher/attendance_marking_screen.dart';
import 'package:taleemplus_app/features/teacher/screens/classroom_management_screen.dart';
import 'package:taleemplus_app/features/teacher/screens/my_timetable_screen.dart'
    as teacher_tt;
import 'package:taleemplus_app/features/teacher/teacher_announcements_screen.dart';
import 'package:taleemplus_app/features/teacher/teacher_classes_screen.dart';
import 'package:taleemplus_app/features/teacher/teacher_dashboard.dart';

import 'support/fake_api.dart';

class _Ctx {
  final Map<String, dynamic> fx;
  _Ctx(this.fx);

  /// The longest-named class the role can see, so wrapping is exercised.
  ClassEntity get longestClass {
    final list = (fx['GET /classes'] as List?) ?? const [];
    final classes = list
        .map((m) => ClassEntity.fromMap(
            m['id'] as String, Map<String, dynamic>.from(m as Map)))
        .toList()
      ..sort((a, b) => b.displayLabel.length.compareTo(a.displayLabel.length));
    return classes.first;
  }

  AppUser get child {
    final me = fx['GET /auth/me'] as Map;
    final c = (me['linkedChildren'] as List).first as Map;
    return AppUser(
      uid: c['id'] as String,
      fullName: c['fullName'] as String,
      email: c['email'] as String,
      phoneNumber: '',
      role: UserRole.student,
      academyId: me['academyId'] as String,
    );
  }

  Assignment get firstAssignment => Assignment.fromJson(
      Map<String, dynamic>.from((fx['GET /assignments'] as List).first as Map));

  String get meId => (fx['GET /auth/me'] as Map)['id'] as String;
  String get academyId => (fx['GET /auth/me'] as Map)['academyId'] as String;
}

class _Config {
  final String key;
  final Size size;
  final double textScale;
  final ThemeMode theme;
  const _Config(this.key, this.size,
      {this.textScale = 1.0, this.theme = ThemeMode.dark});
}

/// Every viewport of the test plan (dark theme, default text size), plus
/// phone landscape and accessibility runs: light theme with the system font
/// enlarged to 130 %.
final List<_Config> _configs = [
  for (final vp in testViewports.entries) _Config(vp.key, vp.value),
  const _Config('phone-landscape-800x360', Size(800, 360)),
  const _Config('a11y-light-text130-360x800', Size(360, 800),
      textScale: 1.3, theme: ThemeMode.light),
  const _Config('a11y-light-text130-412x915', Size(412, 915),
      textScale: 1.3, theme: ThemeMode.light),
];

typedef _Builder = Widget Function(_Ctx c);

final Map<String, Map<String, _Builder>> _screens = {
  'admin': {
    'AdminDashboard': (_) => const AdminDashboard(),
    'ClassManagement': (_) => const ClassManagementScreen(),
    'ClassSections': (_) => const ClassSectionsScreen(),
    'UserManagement': (_) => const UserManagementScreen(),
    'Announcements': (_) => const AnnouncementsScreen(),
    'ApprovalRequests': (_) => const ApprovalRequestsScreen(),
    'FeeLedger': (_) => const FeeLedgerScreen(),
    'AcademicStructure': (_) => const AcademicStructureScreen(),
    'PaymentSettings': (_) => const AcademyPaymentSettingsScreen(),
    'ChallanGeneration': (_) => const ChallanGenerationScreen(),
    'ClassFeeStatus': (c) => ClassFeeStatusScreen(classEntity: c.longestClass),
    'ClassReports': (_) => const ClassReportsScreen(),
    'TimetableManagement': (_) => const TimetableManagementScreen(),
    'UnpaidStudents': (_) => const UnpaidStudentsScreen(),
    'AiPrediction': (_) => const AdminAiPredictionScreen(),
    'AdminQuizList': (_) => const AdminQuizListScreen(),
    'Notifications': (_) => const NotificationsScreen(),
    'Assignments': (_) => const AssignmentsScreen(),
    'AssignmentDetail': (c) => AssignmentDetailScreen(
        assignment: c.firstAssignment, staff: true, studentId: ''),
    'StudentDocs': (c) => DocumentsScreen(
        title: '[TEST] Muhammad Abdul Rehman Siddiqui Chaudhry · Documents',
        category: FileCategory.studentDocument,
        ownerId: c.meId,
        canEdit: true),
    'Reports': (_) => const ReportsScreen(),
    'LocationEditor': (_) => const AcademyLocationEditorScreen(),
    'Login': (_) => const LoginScreen(),
    'Signup': (_) => const SignupScreen(),
  },
  'teacher': {
    'TeacherDashboard': (_) => const TeacherDashboard(),
    'TeacherClasses': (_) => const TeacherClassesScreen(),
    'AttendanceMarking': (c) =>
        AttendanceMarkingScreen(classEntity: c.longestClass),
    'Classroom': (c) => ClassroomManagementScreen(classEntity: c.longestClass),
    'TeacherAnnouncements': (_) => const TeacherAnnouncementsScreen(),
    'TeacherQuizList': (_) => const TeacherQuizListScreen(),
    'MonthlyReport': (_) => const MonthlyReportScreen(),
    'TeacherTimetable': (_) => const teacher_tt.MyTimetableScreen(),
    'TeacherAssignments': (_) => const AssignmentsScreen(),
    'TeacherReports': (_) => const ReportsScreen(),
    'TeacherLocation': (_) => const AcademyLocationScreen(),
    'TeacherAssignmentDetail': (c) => AssignmentDetailScreen(
        assignment: c.firstAssignment, staff: true, studentId: ''),
  },
  'student': {
    'StudentDashboard': (_) => const StudentDashboard(),
    'ClassroomHub': (_) => const MyClassroomHub(),
    'StudentTimetable': (_) => const student_tt.MyTimetableScreen(),
    'StudentAttendance': (c) => StudentAttendanceScreen(studentUid: c.meId),
    'StudentFees': (c) => StudentFeeScreen(studentUid: c.meId),
    'ProgressChart': (c) => StudentProgressChartScreen(studentUid: c.meId),
    'TestReport': (c) =>
        StudentTestReportScreen(studentUid: c.meId, studentName: 'Me'),
    'TeacherDetails': (c) => TeacherDetailsScreen(classEntity: c.longestClass),
    'AiSummarizer': (_) => const AiSummarizerScreen(),
    'ViewAnnouncements': (_) => const ViewAnnouncementsScreen(),
    'StudentAssignments': (_) => const AssignmentsScreen(),
    'StudentLocation': (_) => const AcademyLocationScreen(),
    'StudentAssignmentDetail': (c) => AssignmentDetailScreen(
        assignment: c.firstAssignment, staff: false, studentId: c.meId),
    'MyDocuments': (c) => DocumentsScreen(
        title: 'My Documents',
        category: FileCategory.studentDocument,
        ownerId: c.meId),
  },
  'parent': {
    'ParentDashboard': (_) => const ParentDashboard(),
    'ChildOverview': (c) => ChildOverviewScreen(child: c.child),
    'ChildTimetable': (c) => ChildTimetableScreen(child: c.child),
    'AllChallans': (_) => const AllChallansScreen(),
    'StudentChallan': (c) => StudentChallanScreen(studentUid: c.child.uid),
    'AcademyContact': (c) => AcademyContactScreen(academyId: c.academyId),
    'ChildAssignments': (c) =>
        AssignmentsScreen(childId: c.child.uid, childName: c.child.fullName),
    'ChildAssignmentDetail': (c) => AssignmentDetailScreen(
        assignment: c.firstAssignment, staff: false, studentId: c.child.uid),
    'ChildDocuments': (c) => DocumentsScreen(
        title: 'Documents',
        category: FileCategory.studentDocument,
        ownerId: c.child.uid),
    'ChildAlerts': (c) =>
        ChildAlertsScreen(childName: c.child.fullName, childUid: c.child.uid),
  },
};

const _emails = {
  'admin': 'admin@demo.taleemplus',
  'teacher': 'teacher@demo.taleemplus',
  'student': 'student@demo.taleemplus',
  'parent': 'parent@demo.taleemplus',
};

/// Contrast threshold. 1.5:1 (default) catches effectively invisible text;
/// set CONTRAST_MIN=4.5 to audit against WCAG AA.
final double _minContrast =
    double.tryParse(Platform.environment['CONTRAST_MIN'] ?? '') ?? 1.5;

/// Light theme only: near-white text that is not on a dark-painted
/// background (it would be invisible on the white light-theme surfaces).
List<String> _lowContrastTexts(WidgetTester tester) {
  final found = <String>[];
  Color? backgroundOf(RenderObject node) {
    RenderObject? p = node.parent;
    while (p != null) {
      // ColoredBox paints through a private render object; read its widget.
      final creator = p.debugCreator;
      if (creator is DebugCreator && creator.element.widget is ColoredBox) {
        final c = (creator.element.widget as ColoredBox).color;
        if (c.a > 0.5) return c;
      }
      if (p is RenderDecoratedBox) {
        final d = p.decoration;
        if (d is BoxDecoration && d.color != null && d.color!.a > 0.5) {
          return d.color;
        }
        if (d is BoxDecoration &&
            d.gradient != null &&
            d.gradient!.colors.first.a > 0.5) {
          return d.gradient!.colors.first;
        }
      }
      if (p is RenderPhysicalShape && p.color.a > 0.5) return p.color;
      if (p is RenderPhysicalModel && p.color.a > 0.5) return p.color;
      p = p.parent;
    }
    return null;
  }

  void visit(RenderObject node) {
    if (node is RenderParagraph && node.hasSize && node.size.width > 0) {
      final text = node.text.toPlainText().trim();
      final color = node.text.style?.color;
      if (text.isNotEmpty && color != null && color.a > 0.5) {
        final bg = backgroundOf(node) ?? Colors.white;
        final ratio =
            (math.max(color.computeLuminance(), bg.computeLuminance()) + 0.05) /
                (math.min(color.computeLuminance(), bg.computeLuminance()) +
                    0.05);
        // 1.5:1 flags only effectively invisible text (WCAG AA is 4.5:1).
        if (ratio < _minContrast) {
          found.add(
              'Low contrast (${ratio.toStringAsFixed(2)}:1, text ${color.toARGB32().toRadixString(16)} on ${bg.toARGB32().toRadixString(16)}) "${text.length > 40 ? text.substring(0, 40) : text}"');
        }
      }
    }
    node.visitChildren(visit);
  }

  final root = tester.binding.rootElement?.renderObject;
  if (root != null) visit(root);
  return found;
}

/// Finds text laid out in a column too narrow for its words.
List<String> _squeezedTexts(WidgetTester tester) {
  final found = <String>[];
  void visit(RenderObject node) {
    if (node is RenderParagraph && node.hasSize) {
      final text = node.text.toPlainText().trim();
      final fontSize = node.text.style?.fontSize ?? 14;
      final longestWord = text
          .split(RegExp(r'\s+'))
          .fold<int>(0, (m, w) => w.length > m ? w.length : m);
      // Hyphens and slashes are legitimate soft line-break points.
      final words = text.split(RegExp(r'[\s\-/]+')).where((w) => w.isNotEmpty);
      // Count the lines the paragraph actually laid out (distinct box rows).
      final boxes = node.getBoxesForSelection(TextSelection(
          baseOffset: 0, extentOffset: node.text.toPlainText().length));
      final lines = boxes.map((b) => b.top.round()).toSet().length;
      // App-bar titles squeezed by too many action icons (e.g. "A…").
      final creatorObj = node.debugCreator;
      if (creatorObj is DebugCreator &&
          creatorObj.element
              .debugGetCreatorChain(8)
              .contains('_AppBarTitleBox') &&
          text.length > 6 &&
          node.size.width < 110 &&
          node.didExceedMaxLines) {
        found.add('App bar title "$text" truncated to '
            '${node.size.width.toStringAsFixed(0)}px');
      }
      // More lines than words means at least one word was split mid-word:
      // the exact Class Management bug. Only meaningful for text that is not
      // intentionally clipped to a line limit.
      if (fontSize > 0 && longestWord >= 4 && lines > words.length) {
        final creator = node.debugCreator;
        final chain = creator is DebugCreator
            ? creator.element.debugGetCreatorChain(10)
            : '';
        found.add('"$text" broken mid-word into $lines lines at '
            '${node.size.width.toStringAsFixed(0)}px  <<$chain>>');
      }
    }
    node.visitChildren(visit);
  }

  final root = tester.binding.rootElement?.renderObject;
  if (root != null) visit(root);
  return found;
}

void main() {
  final fixtures = loadFixtures();

  setUpAll(() async {
    final loaded = await loadRealFonts();
    if (!loaded) {
      // ignore: avoid_print
      print('WARNING: Flutter SDK fonts not found; text widths are inflated.');
    }
  });

  for (final role in _screens.keys) {
    group('$role portal', () {
      for (final entry in _screens[role]!.entries) {
        testWidgets('${entry.key} lays out at every viewport', (tester) async {
          final fx = Map<String, dynamic>.from(fixtures[role] as Map);
          final ctx = _Ctx(fx);
          final problems = <String, List<String>>{};

          await http.runWithClient(() async {
            final auth = await signedInAuth(_emails[role]!);
            for (final vp in _configs) {
              tester.view.physicalSize = vp.size;
              tester.view.devicePixelRatio = 1;
              tester.platformDispatcher.textScaleFactorTestValue = vp.textScale;
              final errors = <String>[];
              final previous = FlutterError.onError;
              FlutterError.onError = (d) {
                if (Platform.environment['LAYOUT_DEBUG'] != null) {
                  debugPrint('FULLERR [${vp.key}] ${d.toString()}');
                }
                final msg = d.exceptionAsString().split('\n').take(2).join(' ');
                // Report which widget the error came from, if known.
                final where = RegExp(r'lib/[\w/]+\.dart:\d+')
                    .allMatches(d.toString())
                    .map((m) => m.group(0))
                    .toSet()
                    .take(2)
                    .join(', ');
                errors.add(where.isEmpty ? msg : '$msg @ $where');
              };
              try {
                final app = await buildApp(tester,
                    home: entry.value(ctx), auth: auth, themeMode: vp.theme);
                await tester.pumpWidget(app);
                for (var i = 0; i < 12; i++) {
                  await tester.pump(const Duration(milliseconds: 100));
                }
                errors.addAll(_squeezedTexts(tester));
                if (vp.theme == ThemeMode.light) {
                  errors.addAll(_lowContrastTexts(tester));
                }
              } catch (e) {
                errors.add('threw: $e');
              } finally {
                FlutterError.onError = previous;
              }
              await tester.pumpWidget(const SizedBox());
              await tester.pump(const Duration(seconds: 1));
              // Follow-on assertions ("was not laid out", null checks inside
              // the framework) repeat the first, real error.
              final primary = errors
                  .where((e) =>
                      !e.startsWith('RenderBox was not laid out') &&
                      !e.startsWith('Null check operator') &&
                      !e.contains('object.dart\': Failed assertion') &&
                      !e.contains('sliver_multi_box_adaptor.dart'))
                  .toSet();
              for (final e in (primary.isEmpty ? errors.toSet() : primary)) {
                problems.putIfAbsent(e, () => []).add(vp.key);
              }
            }
          }, () => fakeBackend(fx));

          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          final report = problems.entries
              .map((e) => '- ${e.key}\n    at: ${e.value.join(', ')}')
              .join('\n');
          expect(problems, isEmpty, reason: '\n$report');
          // Measurements need the real fonts; the default test font is ~2x
          // wider and would report false overflows.
        }, skip: !realFontsAvailable);
      }
    });
  }
}
