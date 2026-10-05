import 'package:flavorflow_hrms/core/api_client.dart';
import 'package:flavorflow_hrms/core/app_controller.dart';
import 'package:flavorflow_hrms/core/app_scope.dart';
import 'package:flavorflow_hrms/core/theme.dart';
import 'package:flavorflow_hrms/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _LoginTestController extends AppController {
  _LoginTestController()
      : super(apiClient: ApiClient(baseUrl: 'https://example.test/api/v1/'));

  @override
  Future<bool> canUseBiometricsOnDevice() async => false;
}

class _AutoBiometricController extends _LoginTestController {
  int biometricAttempts = 0;

  @override
  Future<bool> canUseBiometricsOnDevice() async => true;

  @override
  Future<bool> signInWithBiometrics() async {
    biometricAttempts++;
    return true;
  }
}

void main() {
  testWidgets('login screen shows the FlavorFlow sign-in options', (tester) async {
    final controller = _LoginTestController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Login with Biometrics / Fingerprint'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Sign In with Password'), findsOneWidget);
    expect(find.text('WORKFORCE PORTAL'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText() == 'FlavorFlow',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('GD FOODS'),
      ),
      findsNothing,
    );

    await tester.tap(find.text('Login with Biometrics / Fingerprint'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Fingerprint or face unlock is not available.'),
      findsOneWidget,
    );
  });

  testWidgets('saved biometric sign-in prompts automatically on app open', (
    tester,
  ) async {
    final controller = _AutoBiometricController()
      ..hasBiometricLoginSession = true
      ..autoBiometricPromptPending = true;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.biometricAttempts, 1);
  });
}
