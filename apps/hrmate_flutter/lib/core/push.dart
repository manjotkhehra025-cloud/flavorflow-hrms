import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'app_nav.dart';
import 'firebase_boot.dart';
import 'session.dart';
import 'theme.dart';
import '../features/alerts/alerts_sheet.dart';

/// FCM client: registers this phone with `/api/push-token`, shows a banner for
/// pushes that arrive while the app is open, and routes notification taps
/// (`data.appPath`) to the right tab/screen. All no-ops when Firebase is off.
class PushService {
  PushService(this._ref);
  final Ref _ref;

  bool _started = false;
  String? _token;
  final _subs = <StreamSubscription<dynamic>>[];

  bool get _canApprove => _ref.read(sessionStoreProvider).user?.canApprove ?? false;

  /// Idempotent — call when the signed-in shell opens.
  Future<void> start() async {
    if (!firebaseReady || _started) return;
    _started = true;
    try {
      final fm = FirebaseMessaging.instance;
      // Android 13+ runtime prompt; older Android is granted at install.
      await fm.requestPermission(alert: true, badge: true, sound: true);
      _token = await fm.getToken();
      await _register(_token);

      _subs.add(fm.onTokenRefresh.listen((t) {
        _token = t;
        unawaited(_register(t));
      }));
      _subs.add(FirebaseMessaging.onMessage.listen(_onForeground));
      _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(_onTap));

      final initial = await fm.getInitialMessage();
      if (initial != null) _onTap(initial);
    } catch (e) {
      debugPrint('[push] start failed: $e');
      _started = false;
    }
  }

  Future<void> _register(String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      await _ref.read(apiProvider).post('/api/push-token', data: {'token': token, 'platform': 'android'});
    } catch (e) {
      debugPrint('[push] register failed: $e');
    }
  }

  void _onForeground(RemoteMessage m) {
    _ref.invalidate(alertsProvider);
    final n = m.notification;
    if (n == null) return;
    final appPath = m.data['appPath'] as String?;
    scaffoldMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: HMC.ink,
        duration: const Duration(seconds: 5),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(n.title ?? '', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
          if ((n.body ?? '').isNotEmpty) Text(n.body!, style: const TextStyle(color: Colors.white70)),
        ]),
        action: SnackBarAction(
          label: 'OPEN',
          textColor: HMC.emerald,
          onPressed: () => openAppPathFromRef(_ref, appPath, canApprove: _canApprove),
        ),
      ));
  }

  void _onTap(RemoteMessage m) {
    _ref.invalidate(alertsProvider);
    openAppPathFromRef(_ref, m.data['appPath'] as String?, canApprove: _canApprove);
  }

  /// Logout: server forgets this phone for the old user, FCM token rotates.
  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final token = _token;
    _started = false;
    _token = null;
    if (!firebaseReady || token == null) return;
    try {
      await _ref.read(apiProvider).delete('/api/push-token', data: {'token': token});
    } catch (_) {}
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref));
