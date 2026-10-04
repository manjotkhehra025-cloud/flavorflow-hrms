import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'api_client.dart';
import 'models.dart';

class AppController extends ChangeNotifier {
  AppController({
    ApiClient? apiClient,
    FlutterSecureStorage? secureStorage,
    LocalAuthentication? localAuth,
  })  : api = apiClient ?? ApiClient(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _localAuth = localAuth ?? LocalAuthentication();

  static const String _tokenKey = 'flavorflow.hrms.session';
  static const String _rememberedEmailKey = 'flavorflow.hrms.remembered_email';
  static const String _biometricEnabledKey = 'flavorflow.hrms.biometric_enabled';

  final ApiClient api;
  final FlutterSecureStorage _secureStorage;
  final LocalAuthentication _localAuth;

  SessionUser? user;
  String? rememberedEmail;
  bool isRestoring = true;
  bool hasBiometricLoginSession = false;

  bool get isAuthenticated => user != null;

  Future<bool> canUseBiometricsOnDevice() async {
    try {
      if (!await _localAuth.canCheckBiometrics) return false;
      return (await _localAuth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> restoreSession() async {
    try {
      final biometricEnabled =
          await _secureStorage.read(key: _biometricEnabledKey) == 'true';
      rememberedEmail = await _secureStorage.read(key: _rememberedEmailKey);

      if (biometricEnabled) {
        // Defer reading the saved token until after the native biometric prompt.
        hasBiometricLoginSession = true;
      } else {
        final storedToken = await _secureStorage.read(key: _tokenKey);
        if (storedToken != null && storedToken.isNotEmpty) {
          api.token = storedToken;
          final response = await api.get('auth/me');
          user = SessionUser.fromJson(Map<String, dynamic>.from(response as Map));
        }
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

  Future<void> signIn(
    String email,
    String password, {
    required bool rememberMe,
    required bool enableBiometricLogin,
  }) async {
    final loginEmail = email.trim();
    final response = await api.post('auth/login', {
      'email': loginEmail,
      'password': password,
    });
    final payload = Map<String, dynamic>.from(response as Map);
    final token = payload['token']?.toString();
    if (token == null || token.isEmpty) {
      throw const ApiException('The API did not return a valid sign-in session.');
    }

    api.token = token;
    user = SessionUser.fromJson(Map<String, dynamic>.from(payload['user'] as Map));
    hasBiometricLoginSession = false;
    rememberedEmail = null;

    if (rememberMe) {
      try {
        await _secureStorage.write(key: _tokenKey, value: token);
        await _secureStorage.write(key: _rememberedEmailKey, value: loginEmail);
        if (enableBiometricLogin) {
          await _secureStorage.write(key: _biometricEnabledKey, value: 'true');
          hasBiometricLoginSession = true;
        } else {
          await _secureStorage.delete(key: _biometricEnabledKey);
        }
        rememberedEmail = loginEmail;
      } catch (_) {
        // The in-memory sign-in still works, but no token is retained if secure
        // storage cannot safely persist the session and its preferences.
        await _deleteRememberedSession();
      }
    } else {
      await _deleteRememberedSession();
    }

    notifyListeners();
  }

  Future<bool> signInWithBiometrics() async {
    if (!hasBiometricLoginSession) {
      throw const ApiException(
        'Sign in with your password once and keep “Remember me on this device” enabled to set up biometric sign-in.',
      );
    }

    bool authenticated;
    try {
      authenticated = await _localAuth.authenticate(
        localizedReason: 'Verify your identity to sign in to FlavorFlow HRMS',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      throw const ApiException(
        'Biometric verification is unavailable. Please use your password.',
      );
    }
    if (!authenticated) return false;

    String? storedToken;
    try {
      // Read the session only after the device has verified the user.
      storedToken = await _secureStorage.read(key: _tokenKey);
    } catch (_) {
      throw const ApiException(
        'The saved session is unavailable. Please sign in with your password.',
      );
    }
    if (storedToken == null || storedToken.isEmpty) {
      await _clearSession();
      notifyListeners();
      throw const ApiException(
        'The saved session is unavailable. Please sign in with your password.',
      );
    }

    api.token = storedToken;
    try {
      final response = await api.get('auth/me');
      user = SessionUser.fromJson(Map<String, dynamic>.from(response as Map));
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      api.token = null;
      if (error.statusCode == 401) {
        await _clearSession();
        notifyListeners();
        throw const ApiException(
          'Your saved session has expired. Sign in with your password again.',
          statusCode: 401,
        );
      }
      rethrow;
    } catch (_) {
      api.token = null;
      rethrow;
    }
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
    hasBiometricLoginSession = false;
    await _deleteRememberedSession();
  }

  Future<void> _deleteRememberedSession() async {
    hasBiometricLoginSession = false;
    rememberedEmail = null;
    for (final key in const [
      _tokenKey,
      _rememberedEmailKey,
      _biometricEnabledKey,
    ]) {
      try {
        await _secureStorage.delete(key: key);
      } catch (_) {
        // A secure-storage failure should not block return to the sign-in view.
      }
    }
  }

  @override
  void dispose() {
    api.dispose();
    super.dispose();
  }
}
