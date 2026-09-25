import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';

/// App-wide snackbar host (push banners arrive while any screen is open).
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Selected bottom-nav tab of the signed-in shell:
/// 0 Home · 1 Leaves · 2 Approvals · 3 More.
final homeTabProvider = StateProvider<int>((ref) => 0);

/// Where an `appPath` (from a push payload or an alert row) should land.
class AppTarget {
  /// Shell tab to select, or null to leave the tab alone.
  final int? tab;

  /// Route to push on top of the shell, or null.
  final String? route;
  const AppTarget({this.tab, this.route});
}

/// Pure mapping — unit tested in test/widget_test.dart.
AppTarget resolveAppPath(String? appPath, {required bool canApprove}) {
  final p = (appPath ?? '').trim();
  switch (p) {
    case 'tab:approvals':
      return AppTarget(tab: canApprove ? 2 : 0);
    case 'tab:leaves':
      return const AppTarget(tab: 1);
    case 'tab:more':
      return const AppTarget(tab: 3);
    case '':
    case '/home':
      return const AppTarget(tab: 0);
  }
  const allowed = {'/attendance', '/idcard', '/roster', '/social', '/payslips', '/holidays', '/helpdesk'};
  if (allowed.contains(p) || p.startsWith('/helpdesk/')) return AppTarget(route: p);
  return const AppTarget(tab: 0);
}

/// Open an `appPath` from anywhere (push tap, alert tap).
void openAppPath(WidgetRef ref, String? appPath, {required bool canApprove}) {
  final target = resolveAppPath(appPath, canApprove: canApprove);
  _open(ref.read(routerProvider), (t) => ref.read(homeTabProvider.notifier).state = t, target);
}

/// Same as [openAppPath] for code that only holds a provider `Ref`.
void openAppPathFromRef(Ref ref, String? appPath, {required bool canApprove}) {
  final target = resolveAppPath(appPath, canApprove: canApprove);
  _open(ref.read(routerProvider), (t) => ref.read(homeTabProvider.notifier).state = t, target);
}

void _open(GoRouter router, void Function(int) setTab, AppTarget target) {
  if (target.tab != null) {
    setTab(target.tab!);
    router.go('/home');
  }
  if (target.route != null) {
    router.go('/home');
    router.push(target.route!);
  }
}
