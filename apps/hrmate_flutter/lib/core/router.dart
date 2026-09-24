import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'session.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/set_password_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/home/home_screen.dart';

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
      if (!mustChange && (loc == '/splash' || loc.startsWith('/login') || loc == '/set-password')) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(
        path: '/login',
        builder: (_, state) => LoginScreen(changed: state.uri.queryParameters['changed'] == '1'),
      ),
      GoRoute(path: '/set-password', builder: (_, __) => const SetPasswordScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    ],
  );
});
