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
  bool failBiometricSignIn = false;

  @override
  Future<bool> canUseBiometricsOnDevice() async => true;

  @override
  Future<bool> signInWithBiometrics() async {
    biometricAttempts++;
    if (failBiometricSignIn) {
      throw const ApiException('Automatic biometric check failed.');
    }
    return true;
  }
}

class _CaptureLoginController extends _LoginTestController {
  String? submittedEmail;
  String? submittedPassword;

  @override
  Future<void> signIn(
    String email,
    String password, {
    required bool rememberMe,
    required bool enableBiometricLogin,
  }) async {
    submittedEmail = email;
    submittedPassword = password;
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

  testWidgets('password sign-in submits the exact entered field contents', (
    tester,
  ) async {
    final controller = _CaptureLoginController();
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

    const email = 'admin@flavorflow.co.in';
    const password = '  Exact!Pass  ';
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), email);
    await tester.enterText(fields.at(1), password);
    await tester.tap(find.text('Sign In with Password'));
    await tester.pumpAndSettle();

    expect(controller.submittedEmail, email);
    expect(controller.submittedPassword, password);
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

  testWidgets('failed automatic biometric check falls back without an error', (
    tester,
  ) async {
    final controller = _AutoBiometricController()
      ..hasBiometricLoginSession = true
      ..autoBiometricPromptPending = true
      ..failBiometricSignIn = true;
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
    expect(find.text('Automatic biometric check failed.'), findsNothing);
  });
}
