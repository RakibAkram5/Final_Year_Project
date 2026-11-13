import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../logic/auth_provider.dart';
import '../../logic/parent_provider.dart';

import '../../features/admin/user_management_screen.dart';
import '../../features/admin/approval_requests_screen.dart';
import '../../features/admin/class_sections_screen.dart';
import '../../features/admin/class_management_screen.dart';
import '../../features/admin/screens/timetable_management_screen.dart';
import '../../features/admin/admin_quiz_list_screen.dart';
import '../../features/admin/fee_ledger_screen.dart';
import '../../features/admin/screens/challan_generation_screen.dart';
import '../../features/admin/screens/unpaid_students_screen.dart';
import '../../features/admin/admin_ai_prediction_screen.dart';
import '../../features/admin/announcements_screen.dart';
import '../../features/admin/screens/academic_structure_screen.dart';
import '../../features/admin/screens/class_reports_screen.dart';
import '../../features/admin/screens/academy_branding_screen.dart';
import '../../features/admin/screens/academy_payment_settings_screen.dart';

import '../../features/teacher/teacher_classes_screen.dart';
import '../../features/teacher/teacher_announcements_screen.dart';
import '../../features/teacher/screens/my_timetable_screen.dart' as teacher_tt;
import '../../features/quiz/screens/teacher_quiz_list_screen.dart';
import '../../features/quiz/screens/monthly_report_screen.dart';
import '../../features/shared/view_announcements_screen.dart';
import '../../features/ocr/screens/ocr_capture_screen.dart';
import '../../features/ocr/screens/ocr_history_screen.dart';

import '../../features/student/screens/my_classroom_hub.dart';
import '../../features/student/screens/ai_summarizer_screen.dart';
import '../../features/student/screens/my_timetable_screen.dart' as student_tt;
import '../../features/student/screens/student_attendance_screen.dart';
import '../../features/student/screens/student_fee_screen.dart';
import '../../features/student/screens/student_progress_chart_screen.dart';
import '../../features/quiz/screens/student_test_report_screen.dart';

import '../../features/parent/screens/all_challans_screen.dart';
import '../../features/parent/screens/academy_contact_screen.dart';

/// A single sidebar destination. [id] is matched against a screen's
/// `activeNavId` to render the active-item indicator.
class WebNavItem {
  final String id;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const WebNavItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

class WebNavSection {
  final String? title;
  final List<WebNavItem> items;

  const WebNavSection({this.title, required this.items});
}

/// Every destination here mirrors an existing tile/list-item already present
/// verbatim in that role's mobile dashboard (same icon, same label, same
/// `Navigator.push(MaterialPageRoute(...))` target) — the sidebar only
/// relocates existing navigation into a persistent rail, it does not add new
/// destinations or change the push-based navigation model.
List<WebNavSection> buildAdminNavSections(
  BuildContext context, {
  required VoidCallback onDashboard,
}) {
  void push(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  return [
    WebNavSection(items: [
      WebNavItem(
          id: 'dashboard',
          label: 'Dashboard',
          icon: Icons.dashboard_rounded,
          onTap: onDashboard),
    ]),
    WebNavSection(title: 'PEOPLE', items: [
      WebNavItem(
          id: 'user_management',
          label: 'User Management',
          icon: Icons.group_rounded,
          onTap: () => push(const UserManagementScreen())),
      WebNavItem(
          id: 'approvals',
          label: 'Approval Requests',
          icon: Icons.how_to_reg_rounded,
          onTap: () => push(const ApprovalRequestsScreen())),
    ]),
    WebNavSection(title: 'ACADEMICS', items: [
      WebNavItem(
          id: 'academic_structure',
          label: 'Academic Structure',
          icon: Icons.school_rounded,
          onTap: () => push(const AcademicStructureScreen())),
      WebNavItem(
          id: 'class_sections',
          label: 'Classes & Sections',
          icon: Icons.groups_2_rounded,
          onTap: () => push(const ClassSectionsScreen())),
      WebNavItem(
          id: 'class_management',
          label: 'Class Management',
          icon: Icons.class_rounded,
          onTap: () => push(const ClassManagementScreen())),
      WebNavItem(
          id: 'timetable',
          label: 'Timetable',
          icon: Icons.schedule_rounded,
          onTap: () => push(const TimetableManagementScreen())),
      WebNavItem(
          id: 'quiz_reports',
          label: 'Test Reports & Grading',
          icon: Icons.analytics_rounded,
          onTap: () => push(const AdminQuizListScreen())),
    ]),
    WebNavSection(title: 'FEES', items: [
      WebNavItem(
          id: 'fee_ledger',
          label: 'Fee Ledger',
          icon: Icons.receipt_long_rounded,
          onTap: () => push(const FeeLedgerScreen())),
      WebNavItem(
          id: 'bulk_challans',
          label: 'Bulk Fee Challans',
          icon: Icons.request_quote_rounded,
          onTap: () => push(const ChallanGenerationScreen())),
      WebNavItem(
          id: 'unpaid_students',
          label: 'Unpaid Students',
          icon: Icons.money_off_rounded,
          onTap: () => push(const UnpaidStudentsScreen())),
    ]),
    WebNavSection(title: 'INSIGHTS & COMMUNICATION', items: [
      WebNavItem(
          id: 'ai_prediction',
          label: 'AI Prediction & Insights',
          icon: Icons.auto_awesome_rounded,
          onTap: () => push(const AdminAiPredictionScreen())),
      WebNavItem(
          id: 'announcements',
          label: 'Announcements',
          icon: Icons.campaign_rounded,
          onTap: () => push(const AnnouncementsScreen())),
      WebNavItem(
          id: 'class_reports',
          label: 'Class Reports',
          icon: Icons.summarize_rounded,
          onTap: () => push(const ClassReportsScreen())),
    ]),
    WebNavSection(title: 'SETTINGS', items: [
      WebNavItem(
          id: 'branding',
          label: 'Academy Branding',
          icon: Icons.palette_rounded,
          onTap: () => push(const AcademyBrandingScreen())),
      WebNavItem(
          id: 'payment_settings',
          label: 'Payment Settings',
          icon: Icons.qr_code_2_rounded,
          onTap: () => push(const AcademyPaymentSettingsScreen())),
    ]),
  ];
}

List<WebNavSection> buildTeacherNavSections(
  BuildContext context, {
  required VoidCallback onDashboard,
}) {
  void push(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  return [
    WebNavSection(items: [
      WebNavItem(
          id: 'dashboard',
          label: 'Dashboard',
          icon: Icons.dashboard_rounded,
          onTap: onDashboard),
    ]),
    WebNavSection(title: 'CLASSROOM', items: [
      WebNavItem(
          id: 'attendance',
          label: 'Attendance',
          icon: Icons.fact_check_rounded,
          onTap: () => push(const TeacherClassesScreen())),
      WebNavItem(
          id: 'my_timetable',
          label: 'My Timetable',
          icon: Icons.schedule_rounded,
          onTap: () => push(const teacher_tt.MyTimetableScreen())),
      WebNavItem(
          id: 'resources',
          label: 'Resources',
          icon: Icons.folder_shared_rounded,
          onTap: () => push(
              const TeacherClassesScreen(jumpTo: ClassJumpTarget.resources))),
      WebNavItem(
          id: 'queries',
          label: 'Queries',
          icon: Icons.forum_rounded,
          onTap: () => push(
              const TeacherClassesScreen(jumpTo: ClassJumpTarget.queries))),
    ]),
    WebNavSection(title: 'GRADING & TESTS', items: [
      WebNavItem(
          id: 'grading',
          label: 'Grading & AI Grader',
          icon: Icons.add_chart_rounded,
          onTap: () => push(const TeacherQuizListScreen(isAiGen: false))),
      WebNavItem(
          id: 'ai_test_gen',
          label: 'AI Test Generator',
          icon: Icons.auto_awesome_motion_rounded,
          onTap: () => push(const TeacherQuizListScreen(isAiGen: true))),
      WebNavItem(
          id: 'monthly_report',
          label: 'Monthly Performance',
          icon: Icons.insights_rounded,
          onTap: () => push(const MonthlyReportScreen())),
    ]),
    WebNavSection(title: 'ANNOUNCEMENTS & TOOLS', items: [
      WebNavItem(
          id: 'view_announcements',
          label: 'View Announcements',
          icon: Icons.campaign_rounded,
          onTap: () => push(const ViewAnnouncementsScreen())),
      WebNavItem(
          id: 'manage_announcements',
          label: 'Manage Announcements',
          icon: Icons.add_comment_rounded,
          onTap: () => push(const TeacherAnnouncementsScreen())),
      WebNavItem(
          id: 'ocr_scanner',
          label: 'OCR Scanner',
          icon: Icons.document_scanner_rounded,
          onTap: () => push(const OcrCaptureScreen())),
      WebNavItem(
          id: 'ocr_history',
          label: 'OCR History',
          icon: Icons.history_rounded,
          onTap: () => push(const OcrHistoryScreen())),
    ]),
  ];
}

List<WebNavSection> buildStudentNavSections(
  BuildContext context, {
  required VoidCallback onDashboard,
}) {
  void push(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  final user = context.read<AuthProvider>().currentUser;
  final uid = user?.uid ?? '';
  final studentName = user?.fullName ?? 'Student';

  return [
    WebNavSection(items: [
      WebNavItem(
          id: 'dashboard',
          label: 'Dashboard',
          icon: Icons.dashboard_rounded,
          onTap: onDashboard),
    ]),
    WebNavSection(title: 'LEARNING', items: [
      WebNavItem(
          id: 'classroom_hub',
          label: 'My Classroom Hub',
          icon: Icons.school_rounded,
          onTap: () => push(const MyClassroomHub())),
      WebNavItem(
          id: 'ai_summarizer',
          label: 'AI Notes Summarizer',
          icon: Icons.auto_awesome_rounded,
          onTap: () => push(const AiSummarizerScreen())),
    ]),
    WebNavSection(title: 'DAILY', items: [
      WebNavItem(
          id: 'my_timetable',
          label: 'My Timetable',
          icon: Icons.schedule_rounded,
          onTap: () => push(const student_tt.MyTimetableScreen())),
      WebNavItem(
          id: 'my_attendance',
          label: 'My Attendance',
          icon: Icons.fact_check_rounded,
          onTap: () => push(StudentAttendanceScreen(studentUid: uid))),
    ]),
    WebNavSection(title: 'PERFORMANCE', items: [
      WebNavItem(
          id: 'test_reports',
          label: 'Test Reports',
          icon: Icons.analytics_rounded,
          onTap: () => push(StudentTestReportScreen(
              studentUid: uid, studentName: studentName))),
      WebNavItem(
          id: 'progress_charts',
          label: 'Performance Analytics',
          icon: Icons.show_chart_rounded,
          onTap: () => push(StudentProgressChartScreen(studentUid: uid))),
    ]),
    WebNavSection(title: 'ACADEMY', items: [
      WebNavItem(
          id: 'view_announcements',
          label: 'Announcements',
          icon: Icons.campaign_rounded,
          onTap: () => push(const ViewAnnouncementsScreen())),
      WebNavItem(
          id: 'fee_status',
          label: 'Fee Status',
          icon: Icons.receipt_long_rounded,
          onTap: () => push(StudentFeeScreen(studentUid: uid))),
    ]),
  ];
}

List<WebNavSection> buildParentNavSections(
  BuildContext context, {
  required VoidCallback onDashboard,
}) {
  void push(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  return [
    WebNavSection(items: [
      WebNavItem(
          id: 'dashboard',
          label: 'Dashboard',
          icon: Icons.dashboard_rounded,
          onTap: onDashboard),
    ]),
    WebNavSection(title: 'SERVICES', items: [
      WebNavItem(
          id: 'fee_challans',
          label: 'Fee Challans',
          icon: Icons.receipt_long_rounded,
          onTap: () => push(const AllChallansScreen())),
      WebNavItem(
          id: 'view_announcements',
          label: 'Announcements',
          icon: Icons.campaign_rounded,
          onTap: () => push(const ViewAnnouncementsScreen())),
      WebNavItem(
          id: 'academy_support',
          label: 'Academy Support',
          icon: Icons.support_agent_rounded,
          onTap: () {
            final children = context.read<ParentProvider>().children;
            if (children.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please link a child first.')));
              return;
            }
            push(AcademyContactScreen(
                academyId: children.first.academyId ?? ''));
          }),
    ]),
  ];
}
