import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ihrms/app.dart';
import 'package:ihrms/app_providers.dart';
import 'package:ihrms/repositories/repository_factory.dart';

/// Opens every screen on a phone-sized display and fails on any
/// layout overflow or exception.
void main() {
  Future<void> settle(WidgetTester tester, [int steps = 10]) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> login(WidgetTester tester, String id, String pw) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppProviders(repositories: buildRepositories(), child: const IhrmsApp()));
    await settle(tester, 12); // splash
    expect(find.text('Welcome to iHRMS'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), id);
    await tester.enterText(find.byType(TextFormField).at(1), pw);
    await tester.tap(find.text('Login'));
    await settle(tester, 12);
  }

  Future<void> openAndBack(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle(tester);
    await tester.pageBack();
    await settle(tester, 4);
  }

  Future<void> tab(WidgetTester tester, IconData icon) async {
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.byIcon(icon)));
    await settle(tester);
  }

  testWidgets('employee flow', (tester) async {
    await login(tester, 'EMP001', 'emp123');
    expect(find.text('Manjot'), findsOneWidget);

    // Punch in from the dashboard.
    final punch = find.text('Punch In');
    if (punch.evaluate().isNotEmpty) {
      await tester.tap(punch.first);
      await settle(tester);
    }

    await tab(tester, Icons.access_time);
    final attList = find.descendant(of: find.byType(AppBar), matching: find.text('Attendance'));
    expect(attList, findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_left).hitTestable().first);
    await settle(tester);
    await tester.scrollUntilVisible(find.text('History'), 300, scrollable: find.byType(Scrollable).hitTestable().first);
    await settle(tester, 3);
    expect(find.text('History'), findsOneWidget);

    await tab(tester, Icons.event_note_outlined);
    await openAndBack(tester, find.text('Apply Leave'));

    await tab(tester, Icons.receipt_long_outlined);
    await openAndBack(tester, find.text('Net pay').first);

    await tab(tester, Icons.grid_view_outlined);
    await openAndBack(tester, find.text('Holiday calendar'));
    await openAndBack(tester, find.text('Announcements'));
    await openAndBack(tester, find.text('My profile'));
    expect(find.text('Admin / HR'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('admin flow', (tester) async {
    await login(tester, 'ADM001', 'admin123');
    expect(find.text('Harpreet'), findsOneWidget);

    await tab(tester, Icons.grid_view_outlined);
    await openAndBack(tester, find.text('Leave approvals'));
    await openAndBack(tester, find.text('Attendance report'));

    await tester.tap(find.text('Employees'));
    await settle(tester);
    await openAndBack(tester, find.text('Manjot Singh'));
    await openAndBack(tester, find.text('Add'));
    await tester.pageBack();
    await settle(tester, 4);

    await tab(tester, Icons.event_note_outlined);
    await openAndBack(tester, find.text('Approvals'));

    await tester.pumpWidget(const SizedBox());
  });
}
