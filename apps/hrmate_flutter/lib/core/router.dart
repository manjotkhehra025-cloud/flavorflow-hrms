import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'session.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/set_password_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/home/home_shell.dart';
import '../features/home/punch_flow.dart';
import '../features/attendance/attendance_screen.dart';
import '../features/more/idcard_screen.dart';
import '../features/more/gatekeeper_screen.dart';
import '../features/more/roster_screen.dart';
import '../features/social/social_screen.dart';
import '../features/payslip/payslips_screen.dart';
import '../features/holidays/holidays_screen.dart';
import '../features/helpdesk/helpdesk_screen.dart';
import '../features/helpdesk/helpdesk_thread_screen.dart';
import '../features/people/permissions_screen.dart';

/// Route guard — mirrors the web app exactly:
///  booting          → /splash
///  no token         → /login
///  mustChangePassword → /set-password
///  everything else  → /home
final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(sessionStoreProvider);
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: session,
    redirect: (context, state) {
      if (!session.booted) {
        return state.matchedLocation == '/splash' ? null : '/splash';
      }
      final hasToken = session.cachedToken != null;
      final loc = state.matchedLocation;

      if (!hasToken) {
        return loc.startsWith('/login') ? null : '/login';
      }
      final mustChange = session.user?.mustChangePassword ?? false;
      if (mustChange && loc != '/set-password') return '/set-password';
      // After sign-in everything under the app is fine (change-password is
      // reachable from More even when not forced); only launch screens bounce.
      if (!mustChange && (loc == '/splash' || loc.startsWith('/login'))) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(
        path: '/login',
        builder: (_, state) => LoginScreen(changed: state.uri.queryParameters['changed'] == '1'),
      ),
      GoRoute(path: '/set-password', builder: (_, __) => const SetPasswordScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeShell()),
      GoRoute(
        path: '/punch',
        builder: (_, state) => PunchFlowScreen(action: state.extra as String? ?? 'checkin'),
      ),
      GoRoute(path: '/attendance', builder: (_, __) => const AttendanceScreen()),
      GoRoute(path: '/idcard', builder: (_, __) => IdCardScreen()),
      GoRoute(path: '/gatekeeper', builder: (_, __) => const GatekeeperScreen()),
      GoRoute(path: '/roster', builder: (_, __) => const RosterScreen()),
      // ── P5 ──
      GoRoute(path: '/social', builder: (_, __) => const SocialScreen()),
      GoRoute(path: '/payslips', builder: (_, __) => const PayslipsScreen()),
      GoRoute(path: '/holidays', builder: (_, __) => const HolidaysScreen()),
      GoRoute(path: '/helpdesk', builder: (_, __) => const HelpdeskScreen()),
      GoRoute(
        path: '/helpdesk/:id',
        builder: (_, state) => HelpdeskThreadScreen(id: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(path: '/permissions', builder: (_, __) => const PermissionsPickerScreen()),
      GoRoute(
        path: '/permissions/:employeeId',
        builder: (_, state) => PermissionsScreen(employeeId: state.pathParameters['employeeId'] ?? ''),
      ),
    ],
  );
});
