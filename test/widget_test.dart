import 'package:flavorflow_hrms/core/models.dart';
import 'package:flavorflow_hrms/core/theme.dart';
import 'package:flavorflow_hrms/core/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('session capabilities come from the API payload', () {
    final user = SessionUser.fromJson({
      'id': 7,
      'email': 'admin@example.com',
      'full_name': 'Sam Admin',
      'is_active': true,
      'roles': ['super_admin'],
      'role_names': ['Super Admin'],
      'permissions': ['employees.read', 'employees.create'],
    });

    expect(user.can('employees.read'), isTrue);
    expect(user.can('audit.read'), isFalse);
    expect(user.isSuperAdmin, isTrue);
  });

  testWidgets('status badges present a readable state label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: Center(child: StatusBadge(status: 'on_leave'))),
      ),
    );

    expect(find.text('On Leave'), findsOneWidget);
  });
}
