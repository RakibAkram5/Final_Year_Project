// Taleem Plus - Academy Management System
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent;
import 'package:provider/provider.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/web/web_theme.dart';
import 'logic/auth_provider.dart';
import 'logic/member_provider.dart';
import 'logic/class_provider.dart';
import 'logic/class_section_provider.dart';
import 'logic/attendance_provider.dart';
import 'logic/quiz_provider.dart';
import 'logic/timetable_provider.dart';
import 'logic/academic_structure_provider.dart';
import 'logic/theme_provider.dart';
import 'logic/admin_ai_provider.dart';
import 'logic/parent_provider.dart';
import 'logic/session_provider.dart';
import 'features/auth/splash_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/admin/admin_dashboard.dart';
import 'features/teacher/teacher_dashboard.dart';
import 'features/student/student_dashboard.dart';
import 'features/parent/parent_dashboard.dart';
import 'widgets/connection_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => MemberProvider()),
        ChangeNotifierProvider(create: (_) => ClassProvider()),
        ChangeNotifierProvider(create: (_) => ClassSectionProvider()),
        ChangeNotifierProvider(create: (_) => AttendanceProvider()),
        ChangeNotifierProvider(create: (_) => QuizProvider()),
        ChangeNotifierProvider(create: (_) => TimetableProvider()),
        ChangeNotifierProvider(create: (_) => AdminAiProvider()),
        ChangeNotifierProvider(create: (_) => AcademicStructureProvider()),
        ChangeNotifierProxyProvider<AuthProvider, ParentProvider>(
          create: (_) => ParentProvider(),
          update: (_, auth, parent) => parent!..syncWithUser(auth.currentUser),
        ),
        ChangeNotifierProxyProvider<AuthProvider, SessionProvider>(
          create: (_) => SessionProvider(),
          update: (_, auth, session) => session!..updateAuth(auth),
        ),
      ],
      child: const TaleemPlusApp(),
    ),
  );
}

/// Resets the inactivity timer on every route change (push/pop/replace),
/// so in-app navigation counts as activity even when it isn't triggered by
/// a raw pointer event the root [Listener] would otherwise see (e.g.
/// programmatic navigation following a button tap already handled by the
/// same gesture).
class _ActivityNavigatorObserver extends NavigatorObserver {
  void _resetSessionTimer() {
    final ctx = navigator?.context;
    if (ctx == null) return;
    final auth = Provider.of<AuthProvider>(ctx, listen: false);
    Provider.of<SessionProvider>(ctx, listen: false).resetTimer(ctx, auth);
  }

  @override
  void didPush(Route route, Route? previousRoute) => _resetSessionTimer();

  @override
  void didPop(Route route, Route? previousRoute) => _resetSessionTimer();

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) => _resetSessionTimer();
}

final _activityNavigatorObserver = _ActivityNavigatorObserver();

class _ActivityListener extends StatefulWidget {
  const _ActivityListener({required this.onActivity, required this.child});

  final VoidCallback onActivity;
  final Widget child;

  @override
  State<_ActivityListener> createState() => _ActivityListenerState();
}

class _ActivityListenerState extends State<_ActivityListener> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    widget.onActivity();
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class TaleemPlusApp extends StatelessWidget {
  const TaleemPlusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, theme, _) {
        void resetTimer([_]) => context
            .read<SessionProvider>()
            .resetTimer(context, context.read<AuthProvider>());
        return _ActivityListener(
          onActivity: resetTimer,
          child: Listener(
            onPointerDown: resetTimer,
            onPointerMove: resetTimer,
            onPointerSignal: resetTimer,
            child: MaterialApp(
              navigatorKey: rootNavigatorKey,
              navigatorObservers: [_activityNavigatorObserver],
              title: 'Taleem Plus',
              debugShowCheckedModeBanner: false,
              // One offline banner for the whole app (see ConnectionStatus).
              builder: (context, child) =>
                  ConnectionBanner(child: child ?? const SizedBox.shrink()),
              // Web gets the SaaS-redesign theme (Inter font, softer surfaces,
              // smoother transitions); mobile keeps the original theme
              // untouched — `kIsWeb` is a compile-time constant, so mobile
              // builds never even include the `AppWebTheme` branch.
              theme: kIsWeb ? AppWebTheme.light : AppTheme.light,
              darkTheme: kIsWeb ? AppWebTheme.dark : AppTheme.dark,
              themeMode: theme.themeMode,
              initialRoute: AppRoutes.splash,
              routes: {
                AppRoutes.splash: (_) => const SplashScreen(),
                AppRoutes.login: (_) => const LoginScreen(),
                AppRoutes.signup: (_) => const SignupScreen(),
                AppRoutes.adminDashboard: (_) => const AdminDashboard(),
                AppRoutes.teacherDashboard: (_) => const TeacherDashboard(),
                AppRoutes.studentDashboard: (_) => const StudentDashboard(),
                AppRoutes.parentDashboard: (_) => const ParentDashboard(),
              },
            ),
          ),
        );
      },
    );
  }
}
