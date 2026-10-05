import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'app_controller.dart';

class SessionInactivityGuard extends StatefulWidget {
  const SessionInactivityGuard({
    required this.controller,
    required this.child,
    this.timeout = AppController.inactivityTimeout,
    super.key,
  });

  final AppController controller;
  final Widget child;
  final Duration timeout;

  @override
  State<SessionInactivityGuard> createState() => _SessionInactivityGuardState();
}

class _SessionInactivityGuardState extends State<SessionInactivityGuard>
    with WidgetsBindingObserver {
  Timer? _idleTimer;
  DateTime? _lastActivityAt;
  bool _wasAuthenticated = false;
  bool _isForeground = true;
  bool _expirationInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onControllerChanged);
    _wasAuthenticated = widget.controller.isAuthenticated;
    _lastActivityAt = widget.controller.lastActivityAt;
    if (_wasAuthenticated) {
      _lastActivityAt ??= DateTime.now().toUtc();
      _scheduleIdleTimeout();
    }
  }

  @override
  void didUpdateWidget(covariant SessionInactivityGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _wasAuthenticated = widget.controller.isAuthenticated;
      _lastActivityAt = widget.controller.lastActivityAt;
      _scheduleIdleTimeout();
    }
    if (oldWidget.timeout != widget.timeout) _scheduleIdleTimeout();
  }

  void _onControllerChanged() {
    final authenticated = widget.controller.isAuthenticated;
    if (authenticated && !_wasAuthenticated) {
      _wasAuthenticated = true;
      _lastActivityAt = widget.controller.lastActivityAt ?? DateTime.now().toUtc();
      _scheduleIdleTimeout();
    } else if (!authenticated && _wasAuthenticated) {
      _wasAuthenticated = false;
      _idleTimer?.cancel();
    }
  }

  void _registerActivity() {
    if (!widget.controller.isAuthenticated) return;
    _lastActivityAt = DateTime.now().toUtc();
    unawaited(widget.controller.recordUserActivity());
    _scheduleIdleTimeout();
  }

  void _scheduleIdleTimeout() {
    _idleTimer?.cancel();
    if (!_isForeground || !widget.controller.isAuthenticated) return;

    final lastActivity = _lastActivityAt ??
        widget.controller.lastActivityAt ??
        DateTime.now().toUtc();
    _lastActivityAt = lastActivity;
    final elapsed = DateTime.now().toUtc().difference(lastActivity);
    final remaining = widget.timeout - elapsed;
    if (remaining <= Duration.zero) {
      unawaited(_expireSession(promptBiometricsOnNextLogin: false));
      return;
    }
    _idleTimer = Timer(
      remaining,
      () => unawaited(_expireSession(promptBiometricsOnNextLogin: false)),
    );
  }

  Future<void> _expireSession({
    required bool promptBiometricsOnNextLogin,
  }) async {
    if (_expirationInProgress || !_isForeground || !widget.controller.isAuthenticated) {
      return;
    }
    _expirationInProgress = true;
    _idleTimer?.cancel();
    await widget.controller.signOutForInactivity(
      promptBiometricsOnNextLogin: promptBiometricsOnNextLogin,
    );
    _wasAuthenticated = false;
    _expirationInProgress = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isForeground = true;
      if (widget.controller.isAuthenticated) {
        _lastActivityAt ??= widget.controller.lastActivityAt;
        final lastActivity = _lastActivityAt ?? DateTime.now().toUtc();
        if (DateTime.now().toUtc().difference(lastActivity) >= widget.timeout) {
          unawaited(_expireSession(promptBiometricsOnNextLogin: true));
        } else {
          _scheduleIdleTimeout();
        }
      }
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _isForeground = false;
      _idleTimer?.cancel();
      if (widget.controller.isAuthenticated) {
        unawaited(widget.controller.persistLastActivityAt());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        _registerActivity();
        return KeyEventResult.ignored;
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (PointerDownEvent event) => _registerActivity(),
        onPointerMove: (PointerMoveEvent event) => _registerActivity(),
        onPointerSignal: (PointerSignalEvent event) => _registerActivity(),
        onPointerHover: (PointerHoverEvent event) => _registerActivity(),
        child: widget.child,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);
    _idleTimer?.cancel();
    super.dispose();
  }
}
