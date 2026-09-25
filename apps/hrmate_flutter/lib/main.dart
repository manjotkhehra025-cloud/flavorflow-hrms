import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_lock.dart';
import 'core/app_nav.dart';
import 'core/firebase_boot.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'core/i18n.dart';
import 'core/session.dart';
import 'features/auth/unlock_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootFirebase(); // no-op unless built with FIREBASE_ON=true
  runApp(const ProviderScope(child: HrmateApp()));
}

class HrmateApp extends ConsumerStatefulWidget {
  const HrmateApp({super.key});

  @override
  ConsumerState<HrmateApp> createState() => _HrmateAppState();
}

class _HrmateAppState extends ConsumerState<HrmateApp> with WidgetsBindingObserver {
  late final SessionStore _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = ref.read(sessionStoreProvider);
    _session.addListener(_onSession);
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Signed out (logout, expired token) → drop the biometric gate and the
  /// crash-report user tag.
  void _onSession() {
    final hasToken = _session.cachedToken != null;
    if (!hasToken) ref.read(appLockProvider).release();
    crashSetUser(hasToken ? _session.user?.id : null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(appLockProvider);
    if (state == AppLifecycleState.paused) {
      lock.onBackground();
    } else if (state == AppLifecycleState.resumed) {
      lock.onResume(hasSession: _session.cachedToken != null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final lock = ref.watch(appLockProvider);
    // Load the saved language once on startup.
    ref.watch(_langBootProvider);
    return MaterialApp.router(
      title: 'HRMate',
      debugShowCheckedModeBanner: false,
      theme: buildHmTheme(),
      routerConfig: router,
      scaffoldMessengerKey: scaffoldMessengerKey,
      builder: (context, child) {
        final locked = lock.locked && _session.cachedToken != null;
        return Stack(children: [
          if (child != null) child,
          // Barrier swallows every touch meant for the screen underneath.
          if (locked) const Positioned.fill(child: ModalBarrier(dismissible: false, color: HMC.ink)),
          if (locked) const Positioned.fill(child: UnlockScreen()),
        ]);
      },
    );
  }
}

final _langBootProvider = FutureProvider<void>((ref) async {
  await loadLang(ref);
});
