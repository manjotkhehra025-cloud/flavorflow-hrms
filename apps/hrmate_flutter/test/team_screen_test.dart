import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hrmate/core/api.dart';
import 'package:hrmate/core/i18n.dart';
import 'package:hrmate/core/session.dart';
import 'package:hrmate/core/theme.dart';
import 'package:hrmate/core/widgets.dart';
import 'package:hrmate/features/team/team_models.dart';
import 'package:hrmate/features/team/team_screen.dart';

ResponseBody reply(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body), status, headers: {Headers.contentTypeHeader: ['application/json']},
);

Map<String, dynamic> snapshot({String dept = '', bool empty = false, String? longName}) {
  final rows = <Map<String, dynamic>>[
    {'id': 'one', 'name': longName ?? 'Gurpreet Singh', 'dept': 'Production', 'shift': 'General 08:00', 'status': 'IN', 'inAt': '08:02 AM', 'outAt': null, 'photo': null, 'completed': false, 'weeklyOff': 0},
    {'id': 'two', 'name': 'Ravi Kumar', 'dept': 'Production', 'shift': 'General 07:00', 'status': 'OUT', 'inAt': '07:00 AM', 'outAt': '04:00 PM', 'photo': null, 'completed': true, 'weeklyOff': 1},
    {'id': 'three', 'name': 'Simran Kaur', 'dept': 'Quality', 'shift': 'General 08:00', 'status': 'ABSENT', 'inAt': null, 'outAt': null, 'photo': null, 'completed': false, 'weeklyOff': 2},
  ].where((r) => !empty && (dept.isEmpty || r['dept'].toString().toLowerCase() == dept)).toList();
  return {
    'activeDept': dept,
    'rows': rows,
    'counts': {
      'in': rows.where((r) => r['status'] == 'IN').length,
      'out': rows.where((r) => r['status'] == 'OUT').length,
      'absent': rows.where((r) => r['status'] == 'ABSENT').length,
      'done': rows.where((r) => r['completed'] == true).length,
    },
    'departments': [{'id': 'production', 'name': 'Production'}, {'id': 'quality', 'name': 'Quality'}],
    'leaves': empty ? [] : [
      {'id': 'leave-1', 'name': 'Simran Kaur', 'dept': 'Quality', 'fromDate': '2026-09-28', 'toDate': '2026-09-29', 'days': 2, 'type': 'Earned Leave'},
    ],
  };
}

class TeamAdapter implements HttpClientAdapter {
  FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  TeamAdapter(this.respond);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return await respond(options);
  }

  @override
  void close({bool force = false}) {}
}

class TestSession extends SessionStore {
  @override
  String? get cachedToken => 'test-token';
}

Future<void> openTeam(
  WidgetTester tester,
  TeamAdapter adapter, {
  String role = 'HR',
  String lang = 'en',
  double width = 390,
  double scale = 1,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = TestSession()..setUser(HmUser(
    id: 'user', name: 'Test user', email: 'test@example.invalid', role: role,
    employeeId: null, mustChangePassword: false, canApprove: true, perms: const {},
  ));
  final dio = Dio(BaseOptions(baseUrl: 'https://hr.example'))..httpClientAdapter = adapter;
  final router = GoRouter(initialLocation: '/team', routes: [
    GoRoute(path: '/team', builder: (_, __) => const TeamScreen()),
    GoRoute(path: '/employees/:id', builder: (_, state) => Scaffold(
      appBar: AppBar(title: const Text('Employee profile')),
      body: Text('Profile ${state.pathParameters['id']}'),
    )),
  ]);
  addTearDown(router.dispose);
  addTearDown(session.dispose);
  addTearDown(() => dio.close(force: true));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sessionStoreProvider.overrideWithValue(session),
      apiProvider.overrideWithValue(dio),
      langProvider.overrideWith((ref) => lang),
    ],
    child: MaterialApp.router(
      theme: buildHmTheme(), routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!,
      ),
    ),
  ));
  if (settle) await tester.pumpAndSettle();
  else await tester.pump();
}

void main() {
  for (final role in ['ADMIN', 'HR']) {
    testWidgets('$role sees counters, punch times, status and department filters', (tester) async {
      final adapter = TeamAdapter((req) => reply(snapshot(dept: '${req.queryParameters['dept'] ?? ''}')));
      await openTeam(tester, adapter, role: role);
      expect(find.text('Live Team'), findsOneWidget);
      expect(find.text('Gurpreet Singh'), findsOneWidget);
      expect(find.text('Punched In'), findsOneWidget);
      expect(find.text('IN 08:02 AM'), findsOneWidget);
      expect(find.text('✓ Done'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('team-dept-quality')));
      await tester.pumpAndSettle();
      expect(adapter.requests.last.queryParameters['dept'], 'quality');
      expect(find.text('Gurpreet Singh'), findsNothing);
      expect(find.text('Simran Kaur'), findsOneWidget);
      expect(find.text('No punch yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('employee approvers cannot load the board', (tester) async {
    final adapter = TeamAdapter((_) => reply(snapshot()));
    await openTeam(tester, adapter, role: 'EMPLOYEE');
    expect(find.text('Only HR / admin can view Live Team.'), findsOneWidget);
    expect(adapter.requests, isEmpty);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('team-refresh'))).onPressed, isNull);
  });

  testWidgets('Upcoming Leaves stays company-wide after a board filter', (tester) async {
    final adapter = TeamAdapter((req) => reply(snapshot(dept: '${req.queryParameters['dept'] ?? ''}')));
    await openTeam(tester, adapter);
    await tester.tap(find.byKey(const ValueKey('team-dept-production')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upcoming Leaves'));
    await tester.pumpAndSettle();
    expect(find.text('Simran Kaur'), findsOneWidget);
    expect(find.text('Earned Leave'), findsOneWidget);
    expect(find.text('2d'), findsOneWidget);
    expect(find.text('Punched In'), findsNothing);
    expect(find.byKey(const ValueKey('team-dept-production')), findsNothing);
    await tester.tap(find.text('Board'));
    await tester.pumpAndSettle();
    expect(find.text('Gurpreet Singh'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('team-dept-production'))).selected, isTrue);
  });

  testWidgets('all seven weekly-off choices persist through PATCH', (tester) async {
    final adapter = TeamAdapter((req) => req.method == 'PATCH'
      ? reply({'employeeId': req.data['employeeId'], 'weeklyOff': req.data['weeklyOff']}) : reply(snapshot()));
    await openTeam(tester, adapter);
    for (final day in [1, 2, 3, 4, 5, 6, 0]) {
      await tester.tap(find.byKey(const ValueKey('weekly-off-one')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(teamDayNames[day]));
      await tester.pumpAndSettle();
      expect(adapter.requests.last.method, 'PATCH');
      expect(adapter.requests.last.path, '/api/team/weekly-off');
      expect(adapter.requests.last.data, {'employeeId': 'one', 'weeklyOff': day});
      expect(find.descendant(of: find.byKey(const ValueKey('weekly-off-one')), matching: find.text(teamDayLabels[day])), findsOneWidget);
    }
  });

  testWidgets('pending save is disabled; a failed save keeps the saved value', (tester) async {
    final saving = Completer<ResponseBody>();
    final adapter = TeamAdapter((req) => req.method == 'PATCH' ? saving.future : reply(snapshot()));
    await openTeam(tester, adapter);
    await tester.tap(find.byKey(const ValueKey('weekly-off-one')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monday'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<PopupMenuButton<int>>(find.byKey(const ValueKey('weekly-off-one'))).enabled, isFalse);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('team-refresh'))).onPressed, isNull);
    saving.complete(reply({'error': 'Could not save weekly off. Try again.'}, 500));
    await tester.pumpAndSettle();
    expect(find.text('Could not save weekly off. Try again.'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('weekly-off-one')), matching: find.text('Sun off')), findsOneWidget);
    expect(adapter.requests.where((r) => r.method == 'PATCH').length, 1);
  });

  testWidgets('opening a profile and returning refreshes the board', (tester) async {
    final adapter = TeamAdapter((_) => reply(snapshot()));
    await openTeam(tester, adapter);
    await tester.tap(find.text('Gurpreet Singh'));
    await tester.pumpAndSettle();
    expect(find.text('Profile one'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Live Team'), findsOneWidget);
    expect(adapter.requests.where((r) => r.path == '/api/team').length, 2);
  });

  testWidgets('initial error, retry, refresh error and pull refresh work', (tester) async {
    var fail = true;
    final adapter = TeamAdapter((_) => fail
      ? reply({'error': 'Could not load Live Team. Try again.'}, 500) : reply(snapshot()));
    await openTeam(tester, adapter);
    expect(find.text('Could not load Live Team. Try again.'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Gurpreet Singh'), findsOneWidget);
    fail = true;
    await tester.tap(find.byKey(const ValueKey('team-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('Gurpreet Singh'), findsNothing);
    expect(find.text('Could not load Live Team. Try again.'), findsOneWidget);
    fail = false;
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(find.text('Gurpreet Singh'), findsOneWidget);
  });

  testWidgets('loading and empty board/leave states are explicit', (tester) async {
    final loading = Completer<ResponseBody>();
    final adapter = TeamAdapter((_) => loading.future);
    await openTeam(tester, adapter, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    loading.complete(reply(snapshot(empty: true)));
    await tester.pumpAndSettle();
    expect(find.text('No employees in this filter.'), findsOneWidget);
    await tester.tap(find.text('Upcoming Leaves'));
    await tester.pumpAndSettle();
    expect(find.text('No approved leaves in the next 14 days'), findsOneWidget);
  });

  testWidgets('an older department response cannot replace a newer selection', (tester) async {
    final slow = Completer<ResponseBody>();
    final adapter = TeamAdapter((req) => req.queryParameters['dept'] == 'quality'
      ? slow.future : reply(snapshot(dept: '${req.queryParameters['dept'] ?? ''}')));
    await openTeam(tester, adapter);
    await tester.tap(find.byKey(const ValueKey('team-dept-quality')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('team-dept-production')));
    await tester.pumpAndSettle();
    slow.complete(reply(snapshot(dept: 'quality')));
    await tester.pumpAndSettle();
    expect(find.text('Gurpreet Singh'), findsOneWidget);
    expect(find.text('Simran Kaur'), findsNothing);
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('team-dept-production'))).selected, isTrue);
  });

  testWidgets('narrow Punjabi layout with large text and long names does not overflow', (tester) async {
    final adapter = TeamAdapter((_) => reply(snapshot(longName: 'ਗੁਰਪ੍ਰੀਤ ਸਿੰਘ ਬਹੁਤ ਲੰਮਾ ਮੁਲਾਜ਼ਮ ਨਾਮ')));
    await openTeam(tester, adapter, lang: 'pa', width: 320, scale: 2);
    expect(find.text(T.s('Live Team', 'pa')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(T.s('Upcoming Leaves', 'pa')));
    await tester.pumpAndSettle();
    expect(find.text(T.s('Only approved leave is shown', 'pa')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('date-only labels never shift to the previous day', () {
    expect(teamShortDate('2026-09-28', 'en'), '28 Sep');
    expect(teamShortDate('2026-09-28', 'pa'), '28 ਸਤੰਬਰ');
  });

  testWidgets('avatar auth is same-origin only; absolute legacy photos still work', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Row(children: [
      HmAvatar(name: 'Internal', photo: '/api/photo/one', headers: {'Authorization': 'Bearer test'}),
      HmAvatar(name: 'External', photo: 'https://images.example.invalid/avatar.jpg', headers: {'Authorization': 'Bearer test'}),
    ])));
    final avatars = tester.widgetList<CircleAvatar>(find.byType(CircleAvatar)).toList();
    final internal = avatars[0].foregroundImage! as NetworkImage;
    final external = avatars[1].foregroundImage! as NetworkImage;
    expect(internal.url, '$kApiBaseUrl/api/photo/one');
    expect(internal.headers, {'Authorization': 'Bearer test'});
    expect(external.url, 'https://images.example.invalid/avatar.jpg');
    expect(external.headers, isNull);
    await tester.pumpAndSettle();
  });
}
