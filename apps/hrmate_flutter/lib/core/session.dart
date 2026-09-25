import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the app knows about who is signed in (from /api/auth/me).
class HmUser {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? employeeId;
  final bool mustChangePassword;
  final bool canApprove;
  final Map<String, bool> perms;

  const HmUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.employeeId,
    required this.mustChangePassword,
    required this.canApprove,
    required this.perms,
  });

  static HmUser fromJson(Map<String, dynamic> j) => HmUser(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        email: (j['email'] as String?) ?? '',
        role: (j['role'] as String?) ?? 'EMPLOYEE',
        employeeId: j['employeeId'] as String?,
        mustChangePassword: (j['mustChangePassword'] as bool?) ?? false,
        canApprove: (j['canApprove'] as bool?) ?? false,
        perms: ((j['perms'] as Map?) ?? const {}).map(
          (k, v) => MapEntry('$k', v == true),
        ),
      );
}

/// Persists the bearer token + last non-English UI choice (locale lives in here
/// for P1; server-side locale comes later with the web-account link).
class SessionStore extends ChangeNotifier {
  static const _kToken = 'hm_token';

  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? _cachedToken;
  bool _booted = false;
  HmUser? _user;

  String? get cachedToken => _cachedToken;
  bool get booted => _booted;
  HmUser? get user => _user;

  /// [beforeReady] runs after the token is read but before the router is told
  /// we're booted — used to raise the biometric gate with no flash of Home.
  Future<void> bootstrap({Future<void> Function(bool hasToken)? beforeReady}) async {
    _cachedToken = await _secure.read(key: _kToken);
    if (beforeReady != null) await beforeReady(_cachedToken != null);
    _booted = true;
    notifyListeners();
  }

  Future<void> saveToken(String token) async {
    _cachedToken = token;
    await _secure.write(key: _kToken, value: token);
    notifyListeners();
  }

  void setUser(HmUser? u) {
    _user = u;
    notifyListeners();
  }

  Future<void> clear() async {
    _cachedToken = null;
    _user = null;
    await _secure.delete(key: _kToken);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('hm_last_route');
    notifyListeners();
  }
}

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());
