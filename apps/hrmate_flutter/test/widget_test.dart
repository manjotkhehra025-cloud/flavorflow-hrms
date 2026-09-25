import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrmate/core/app_nav.dart';

/// CI guard — see .circleci/config.yml (build-flutter).
///
/// The build generates the Android wrapper with `flutter create .`. When a
/// `test/widget_test.dart` is absent from the repo, `flutter create` drops its
/// stock counter-app test, which references a MyApp class that does not exist
/// here (our root widget is HrmateApp) — so `flutter analyze` failed every
/// pipeline with `creation_with_non_type`. Committing our own test keeps
/// `flutter create` from inventing one (it only creates missing files).
void main() {
  testWidgets('HRMate smoke — boots a MaterialApp', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('HRMate'))),
    );
    expect(find.text('HRMate'), findsOneWidget);
  });

  group('P6 push / alert tap routing', () {
    test('approvals tab only for approvers', () {
      expect(resolveAppPath('tab:approvals', canApprove: true).tab, 2);
      expect(resolveAppPath('tab:approvals', canApprove: false).tab, 0);
    });

    test('leaves tab and screens', () {
      expect(resolveAppPath('tab:leaves', canApprove: false).tab, 1);
      expect(resolveAppPath('/attendance', canApprove: false).route, '/attendance');
      expect(resolveAppPath('/idcard', canApprove: false).route, '/idcard');
      expect(resolveAppPath('/helpdesk/abc123', canApprove: false).route, '/helpdesk/abc123');
    });

    test('unknown or empty paths fall back to Home', () {
      for (final p in [null, '', '/home', '/permissions', 'https://evil.example']) {
        final t = resolveAppPath(p, canApprove: true);
        expect(t.tab, 0, reason: 'path=$p');
        expect(t.route, isNull, reason: 'path=$p');
      }
    });
  });
}
