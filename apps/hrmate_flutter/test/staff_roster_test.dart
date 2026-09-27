import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hrmate/core/api.dart';
import 'package:hrmate/core/i18n.dart';
import 'package:hrmate/core/session.dart';
import 'package:hrmate/core/theme.dart';
import 'package:hrmate/features/roster/staff_roster_models.dart';
import 'package:hrmate/features/roster/staff_roster_screen.dart';

ResponseBody reply(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body), status, headers: {Headers.contentTypeHeader: ['application/json']},
);

Map<String, dynamic> cell({String shiftId = '', bool isOff = false}) => {'shiftId': shiftId, 'isOff': isOff};

Map<String, dynamic> snapshot({String weekStart = '2026-09-21', bool empty = false, String? longName}) {
  const days = ['2026-09-21', '2026-09-22', '2026-09-23', '2026-09-24', '2026-09-25', '2026-09-26', '2026-09-27'];
  Map<String, dynamic> cells({String off = '', String night = ''}) => {
    for (final d in days) d: cell(shiftId: d == night ? 'night' : '', isOff: d == off),
  };
  final employees = empty ? <Map<String, dynamic>>[] : [
    {
      'id': 'one', 'code': 'FF-014', 'name': longName ?? 'Gurpreet Singh', 'dept': 'Production', 'deptId': 'production',
      'defShift': 'General', 'defStart': '08:00', 'cells': cells(off: '2026-09-23', night: '2026-09-25'),
    },
    {
      'id': 'two', 'code': 'FF-021', 'name': 'Harleen Kaur', 'dept': 'Quality', 'deptId': 'quality',
      'defShift': 'General', 'defStart': '08:00', 'cells': cells(off: '2026-09-24'),
    },
    {
      'id': 'three', 'code': 'FF-008', 'name': 'Ravi Kumar', 'dept': 'Production', 'deptId': 'production',
      'defShift': 'Season', 'defStart': '07:00', 'cells': cells(night: '2026-09-21'),
    },
  ];
  return {
    'weekStart': weekStart, 'weekEnd': '2026-09-27', 'prevW': '2026-09-14', 'nextW': '2026-09-28',
    'today': '2026-09-27', 'days': days,
    'departments': [{'id': 'production', 'name': 'Production'}, {'id': 'quality', 'name': 'Quality'}],
    'shifts': [
      {'id': 'general', 'name': 'General Day', 'startTime': '08:00', 'durationH': 9},
      {'id': 'night', 'name': 'Night', 'startTime': '19:00', 'durationH': 12},
    ],
    'employees': employees,
    'swaps': empty ? [] : [
      {'id': 'swap-1', 'requester': 'Gurpreet Singh', 'peer': 'Ravi Kumar', 'date': '2026-09-21', 'note': 'Family function', 'status': 'PENDING', 'mine': false},
      {'id': 'swap-2', 'requester': 'Harleen Kaur', 'peer': 'Simran Kaur', 'date': '2026-09-18', 'note': null, 'status': 'APPROVED', 'mine': false},
    ],
    'peers': [
      {'id': 'two', 'name': 'Harleen Kaur', 'code': 'FF-021', 'department': 'Quality'},
    ],
    'myEmployeeId': 'one',
    'canSwap': true,
    'pendingSwapCount': empty ? 0 : 1,
  };
}

class RosterAdapter implements HttpClientAdapter {
  FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  RosterAdapter(this.respond);
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

Future<void> tapDepartment(WidgetTester tester, String id) async {
  final target = find.byKey(ValueKey('roster-dept-$id'));
  await Scrollable.of(tester.element(target), axis: Axis.horizontal).position.ensureVisible(
    tester.renderObject(target), alignment: 0.5,
  );
  await tester.pump();
  await tester.tap(target);
}

Future<void> openRoster(
  WidgetTester tester,
  RosterAdapter adapter, {
  String role = 'HR',
  String lang = 'en',
  double width = 390,
  double scale = 1,
  double height = 900,
  bool settle = true,
  bool fromMore = false,
  GlobalKey? previewKey,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = TestSession()..setUser(HmUser(
    id: 'user', name: 'Test user', email: 'test@example.invalid', role: role,
    employeeId: 'one', mustChangePassword: false, canApprove: true, perms: const {'canSwapShift': true},
  ));
  final dio = Dio(BaseOptions(baseUrl: 'https://hr.example'))..httpClientAdapter = adapter;
  final router = GoRouter(initialLocation: fromMore ? '/more' : '/duty-roster', routes: [
    GoRoute(path: '/more', builder: (_, __) => const Scaffold(body: Text('More'))),
    GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('Home'))),
    GoRoute(path: '/duty-roster', builder: (_, __) => const StaffRosterScreen()),
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
      builder: (context, child) => RepaintBoundary(
        key: previewKey,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  ));
  if (fromMore) router.push('/duty-roster');
  if (settle) await tester.pumpAndSettle();
  else await tester.pump();
}

void main() {
  final previousHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = previousHitTestPolicy);

  for (final role in ['ADMIN', 'HR']) {
    testWidgets('$role sees week grid, default/override/off chips and department filter', (tester) async {
      final adapter = RosterAdapter((_) => reply(snapshot()));
      await openRoster(tester, adapter, role: role);
      expect(find.text('Duty Roster'), findsOneWidget);
      expect(find.text('Gurpreet Singh'), findsOneWidget);
      expect(find.text('21–27 September'), findsOneWidget);
      expect(find.text('OFF'), findsWidgets);
      expect(find.text('Night'), findsWidgets);
      await tapDepartment(tester, 'quality');
      await tester.pumpAndSettle();
      expect(find.text('Gurpreet Singh'), findsNothing);
      expect(find.text('Harleen Kaur'), findsOneWidget);
      expect(adapter.requests.where((r) => r.path == '/api/roster/staff').length, 1);
    });
  }

  testWidgets('employee approvers cannot load the board', (tester) async {
    final adapter = RosterAdapter((_) => reply(snapshot()));
    await openRoster(tester, adapter, role: 'EMPLOYEE');
    expect(find.text('Only HR / admin can edit the duty roster.'), findsOneWidget);
    expect(adapter.requests, isEmpty);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('roster-refresh'))).onPressed, isNull);
  });

  testWidgets('Sunday without an assignment stays default, not auto-off', (tester) async {
    final adapter = RosterAdapter((_) => reply(snapshot()));
    await openRoster(tester, adapter);
    expect(find.byKey(const ValueKey('roster-cell-one-2026-09-27')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('roster-cell-one-2026-09-27')), matching: find.text('Def')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('roster-cell-one-2026-09-27')), matching: find.text('OFF')), findsNothing);
  });

  testWidgets('tapping a cell offers default, every shift and OFF, then Save sends only dirty cells', (tester) async {
    final adapter = RosterAdapter((req) => req.method == 'PATCH'
      ? reply({'saved': 1})
      : reply(snapshot()));
    await openRoster(tester, adapter);
    await tester.tap(find.byKey(const ValueKey('roster-cell-one-2026-09-22')));
    await tester.pumpAndSettle();
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('General Day'), findsOneWidget);
    expect(find.text('Night'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('roster-option-off')));
    await tester.pumpAndSettle();
    expect(find.text('Save roster · 1 cells'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('roster-save')));
    await tester.pumpAndSettle();
    final patch = adapter.requests.lastWhere((r) => r.method == 'PATCH');
    expect(patch.path, '/api/roster/staff');
    expect(patch.data['entries'], [
      {'employeeId': 'one', 'date': '2026-09-22', 'shiftId': null, 'isOff': true},
    ]);
    expect(find.textContaining('Roster saved for 1 cells'), findsOneWidget);
  });

  testWidgets('a failed save keeps the dirty cell; refresh is disabled while saving', (tester) async {
    final saving = Completer<ResponseBody>();
    final adapter = RosterAdapter((req) => req.method == 'PATCH' ? saving.future : reply(snapshot()));
    await openRoster(tester, adapter);
    await tester.tap(find.byKey(const ValueKey('roster-cell-one-2026-09-22')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('roster-option-night')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('roster-save')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('roster-refresh'))).onPressed, isNull);
    saving.complete(reply({'error': 'Could not save the roster. Try again.'}, 500));
    await tester.pumpAndSettle();
    expect(find.text('Could not save the roster. Try again.'), findsOneWidget);
    expect(find.text('Save roster · 1 cells'), findsOneWidget);
  });

  testWidgets('Shift Swaps approve/reject and request a swap', (tester) async {
    final adapter = RosterAdapter((req) {
      if (req.path == '/api/approvals/decide') return reply({'ok': true});
      if (req.method == 'POST') return reply({'swap': {}}, 201);
      return reply(snapshot());
    });
    await openRoster(tester, adapter);
    await tester.tap(find.byKey(const ValueKey('roster-tab-swaps')));
    await tester.pumpAndSettle();
    expect(find.text('Pending swaps'), findsOneWidget);
    expect(find.textContaining('Gurpreet Singh'), findsWidgets);
    expect(find.textContaining('Family function'), findsOneWidget);
    expect(find.text('APPROVED'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('roster-approve-swap-1')));
    await tester.pumpAndSettle();
    expect(adapter.requests.any((r) => r.path == '/api/approvals/decide' && r.data['action'] == 'approve'), isTrue);

    await tester.tap(find.byKey(const ValueKey('roster-swap-peer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Harleen Kaur · Quality').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('roster-swap-send')));
    await tester.pumpAndSettle();
    expect(adapter.requests.any((r) => r.path == '/api/roster' && r.method == 'POST'), isTrue);
  });

  testWidgets('week navigation requests w= and an older response cannot replace a newer week', (tester) async {
    final slow = Completer<ResponseBody>();
    final started = Completer<void>();
    final adapter = RosterAdapter((req) {
      final w = '${req.queryParameters['w'] ?? ''}';
      if (w == '2026-09-28') {
        started.complete();
        return slow.future;
      }
      return reply(snapshot(weekStart: w.isEmpty ? '2026-09-21' : w));
    });
    await openRoster(tester, adapter);
    await tester.tap(find.byKey(const ValueKey('roster-week-next')));
    for (var frame = 0; frame < 5 && !started.isCompleted; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(started.isCompleted, isTrue);
    await tester.tap(find.byKey(const ValueKey('roster-week-prev')));
    await tester.pumpAndSettle();
    slow.complete(reply(snapshot(weekStart: '2026-09-28')));
    await tester.pumpAndSettle();
    expect(adapter.requests.last.queryParameters['w'], '2026-09-14');
  });

  testWidgets('initial error, retry, empty filter and pull refresh work', (tester) async {
    var fail = true;
    final adapter = RosterAdapter((_) => fail
      ? reply({'error': 'Could not load the duty roster. Try again.'}, 500)
      : reply(snapshot(empty: true)));
    await openRoster(tester, adapter);
    expect(find.text('Could not load the duty roster. Try again.'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No employees in this filter.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('roster-tab-swaps')));
    await tester.pumpAndSettle();
    expect(find.text('No pending swap requests'), findsOneWidget);
  });

  testWidgets('narrow Punjabi layout with large text and long names does not overflow', (tester) async {
    final adapter = RosterAdapter((_) => reply(snapshot(longName: 'ਗੁਰਪ੍ਰੀਤ ਸਿੰਘ ਬਹੁਤ ਲੰਮਾ ਮੁਲਾਜ਼ਮ ਨਾਮ')));
    await openRoster(tester, adapter, lang: 'pa', width: 320, scale: 2);
    expect(find.text(T.s('Duty Roster', 'pa')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('roster-tab-swaps')));
    await tester.pumpAndSettle();
    expect(find.text(T.s('Pending swaps', 'pa')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('week title and date-only labels never shift to the previous day', () {
    expect(rosterWeekTitle(['2026-09-21', '2026-09-22', '2026-09-23', '2026-09-24', '2026-09-25', '2026-09-26', '2026-09-27']), '21–27 September');
    expect(rosterShortDate('2026-09-28'), '28 Sep');
  });

  testWidgets('render approved Duty Roster layouts with sample data', (tester) async {
    final output = Platform.environment['TEAM_PREVIEW_DIR'];
    if (output == null) return;
    await tester.runAsync(() async {
      final bytes = await File('test/fonts/Roboto.ttf').readAsBytes();
      final font = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(bytes)));
      await font.load();
    });
    final boundaryKey = GlobalKey();
    await openRoster(tester, RosterAdapter((_) => reply(snapshot())), height: 850, fromMore: true, previewKey: boundaryKey);
    final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    Future<void> capture(String filename) async {
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ImageByteFormat.png);
        Directory(output).createSync(recursive: true);
        File('$output/$filename').writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(find.byType(BackButton), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture('duty-roster-grid.png');
    await tester.tap(find.byKey(const ValueKey('roster-tab-swaps')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture('duty-roster-swaps.png');
  });
}
