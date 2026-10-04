import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'models.dart';

class AppController extends ChangeNotifier {
  AppController({ApiClient? apiClient, FlutterSecureStorage? secureStorage})
      : api = apiClient ?? ApiClient(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _tokenKey = 'flavorflow.hrms.session';

  final ApiClient api;
  final FlutterSecureStorage _secureStorage;

  SessionUser? user;
  bool isRestoring = true;

  bool get isAuthenticated => user != null;

  Future<void> restoreSession() async {
    try {
      final storedToken = await _secureStorage.read(key: _tokenKey);
      if (storedToken != null && storedToken.isNotEmpty) {
        api.token = storedToken;
        final response = await api.get('auth/me');
        user = SessionUser.fromJson(Map<String, dynamic>.from(response as Map));
      }
    } on ApiException catch (error) {
      if (error.statusCode == 401) await _clearSession();
    } catch (_) {
      // Keep the sign-in view available if secure storage or the API is not ready.
      await _clearSession();
    } finally {
      isRestoring = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) async {
    final response = await api.post('auth/login', {
      'email': email.trim(),
      'password': password,
    });
    final payload = Map<String, dynamic>.from(response as Map);
    final token = payload['token']?.toString();
    if (token == null || token.isEmpty) {
      throw const ApiException('The API did not return a valid sign-in session.');
    }
    api.token = token;
    await _secureStorage.write(key: _tokenKey, value: token);
    user = SessionUser.fromJson(Map<String, dynamic>.from(payload['user'] as Map));
    notifyListeners();
  }

  Future<void> refreshUser() async {
    final response = await api.get('auth/me');
    user = SessionUser.fromJson(Map<String, dynamic>.from(response as Map));
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await api.post('auth/logout');
    } catch (_) {
      // Local credentials are cleared even if the network is unavailable.
    }
    await _clearSession();
    notifyListeners();
  }

  Future<void> _clearSession() async {
    api.token = null;
    user = null;
    try {
      await _secureStorage.delete(key: _tokenKey);
    } catch (_) {
      // A failed plugin write must not prevent the user from returning to sign-in.
    }
  }

  @override
  void dispose() {
    api.dispose();
    super.dispose();
  }
}
