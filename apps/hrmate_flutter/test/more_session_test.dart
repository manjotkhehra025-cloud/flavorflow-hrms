import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hrmate/core/app_lock.dart';
import 'package:hrmate/core/session.dart';
import 'package:hrmate/core/theme.dart';
import 'package:hrmate/features/more/more_tab.dart';

class NoBiometrics extends AppLock {
  @override
  Future<bool> available() async => false;
}

HmUser user(String role) => HmUser(
  id: 'staff-fixture', name: '$role user', email: 'fixture@example.invalid',
  role: role, employeeId: null, mustChangePassword: false,
  // A route-head employee must still NOT see staff-only entries.
  canApprove: true, perms: const {},
);

Future<SessionStore> openMore(WidgetTester tester, {HmUser? initialUser}) async {
  tester.view.physicalSize = const Size(390, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = SessionStore()..setUser(initialUser);
  // Deliberately no session refreshListenable here: this tests More's own
  // subscription, not an incidental rebuild caused by router navigation.
  final router = GoRouter(initialLocation: '/more', routes: [
    GoRoute(path: '/more', builder: (_, __) => const MoreTab()),
    GoRoute(path: '/team', builder: (_, __) => const Scaffold(body: Text('Live Team route'))),
  ]);
  addTearDown(router.dispose);
  addTearDown(session.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sessionStoreProvider.overrideWithValue(session),
      appLockProvider.overrideWith((ref) => NoBiometrics()),
    ],
    child: MaterialApp.router(theme: buildHmTheme(), routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return session;
}

void main() {
  final oldHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = oldHitTestPolicy);

  for (final role in ['ADMIN', 'HR']) {
    testWidgets('$role gets a working Live Team entry when user flags arrive late', (tester) async {
      final session = await openMore(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('?'), findsOneWidget);
      expect(find.text('Live Team'), findsNothing);

      // Same order as a cold start: the token boots the shell before /auth/me.
      session.setUser(user(role));
      await tester.pumpAndSettle();
      expect(find.text('$role user'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Live Team'), 180,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Live Team'));
      await tester.pumpAndSettle();
      expect(find.text('Live Team route'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('staff entries disappear when the current user becomes an employee', (tester) async {
    final session = await openMore(tester, initialUser: user('ADMIN'));
    await tester.scrollUntilVisible(find.text('Live Team'), 180,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Live Team'), findsOneWidget);
    session.setUser(user('EMPLOYEE'));
    await tester.pumpAndSettle();
    expect(find.text('Live Team'), findsNothing);
    expect(find.text('Employees'), findsNothing);
    expect(find.text('Employee permissions'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
