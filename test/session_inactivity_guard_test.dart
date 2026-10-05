import 'package:flavorflow_hrms/core/api_client.dart';
import 'package:flavorflow_hrms/core/app_controller.dart';
import 'package:flavorflow_hrms/core/app_scope.dart';
import 'package:flavorflow_hrms/core/session_inactivity_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _IdleGuardController extends AppController {
  _IdleGuardController()
      : super(apiClient: ApiClient(baseUrl: 'https://example.test/api/v1/'));

  bool _signedIn = true;
  int inactivitySignOuts = 0;

  @override
  bool get isAuthenticated => _signedIn;

  @override
  Future<void> recordUserActivity() async {
    lastActivityAt = DateTime.now().toUtc();
  }

  @override
  Future<void> persistLastActivityAt() async {}

  @override
  Future<void> signOutForInactivity({
    bool promptBiometricsOnNextLogin = false,
  }) async {
    inactivitySignOuts++;
    _signedIn = false;
    notifyListeners();
  }
}

Widget _guardedApp(_IdleGuardController controller) => AppScope(
      controller: controller,
      child: SessionInactivityGuard(
        controller: controller,
        timeout: const Duration(minutes: 15),
        child: const MaterialApp(
          home: Scaffold(body: Center(child: Text('Session active'))),
        ),
      ),
    );

void main() {
  testWidgets('session is signed out after 15 minutes without activity', (
    tester,
  ) async {
    final controller = _IdleGuardController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_guardedApp(controller));
    await tester.pump(const Duration(minutes: 15));
    await tester.pump();

    expect(controller.inactivitySignOuts, 1);
  });

  testWidgets('interaction resets the 15-minute inactivity timer', (
    tester,
  ) async {
    final controller = _IdleGuardController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_guardedApp(controller));
    await tester.pump(const Duration(minutes: 14));
    await tester.tap(find.text('Session active'));
    await tester.pump();
    await tester.pump(const Duration(minutes: 14, seconds: 59));
    await tester.pump();

    expect(controller.inactivitySignOuts, 0);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(controller.inactivitySignOuts, 1);
  });
}
