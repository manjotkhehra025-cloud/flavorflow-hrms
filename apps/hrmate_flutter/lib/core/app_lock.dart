import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Biometric quick-unlock (fingerprint / face, device PIN as fallback).
///
/// Opt-in per phone from More → "Fingerprint unlock". When on, the app is
/// covered by the unlock screen on cold start and after [relockAfter] in the
/// background. The bearer token never leaves secure storage — this is a local
/// gate on top of it, not a second login.
class AppLock extends ChangeNotifier {
  static const _kEnabled = 'hm_bio_on';
  static const relockAfter = Duration(minutes: 3);

  final LocalAuthentication _auth = LocalAuthentication();

  bool _enabled = false;
  bool _locked = false;
  bool _busy = false;
  DateTime? _backgroundedAt;

  bool get enabled => _enabled;
  bool get locked => _locked;
  bool get busy => _busy;

  /// Read the saved switch; lock right away if a session exists.
  Future<void> load({required bool hasSession}) async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kEnabled) ?? false;
    _locked = _enabled && hasSession;
    notifyListeners();
  }

  /// Device has a fingerprint/face sensor or at least a screen lock.
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Shows the system biometric prompt. True on success.
  Future<bool> authenticate(String reason) async {
    if (_busy) return false;
    _busy = true;
    notifyListeners();
    try {
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } catch (e) {
      debugPrint('[lock] auth failed: $e');
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> unlock(String reason) async {
    final ok = await authenticate(reason);
    if (ok) {
      _locked = false;
      notifyListeners();
    }
    return ok;
  }

  /// Turning ON requires one successful scan, so nobody can enable it on a
  /// phone whose owner never enrolled a fingerprint.
  Future<bool> setEnabled(bool on, String reason) async {
    if (on && !await authenticate(reason)) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, on);
    _enabled = on;
    if (!on) _locked = false;
    notifyListeners();
    return true;
  }

  void onBackground() => _backgroundedAt = DateTime.now();

  void onResume({required bool hasSession}) {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (!_enabled || !hasSession || since == null) return;
    if (DateTime.now().difference(since) >= relockAfter) {
      _locked = true;
      notifyListeners();
    }
  }

  /// Signed out — nothing to protect.
  void release() {
    _locked = false;
    notifyListeners();
  }
}

final appLockProvider = ChangeNotifierProvider<AppLock>((ref) => AppLock());
