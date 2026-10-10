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

  static const inactivityTimeout = Duration(minutes: 15);
  static const String _tokenKey = 'flavorflow.hrms.session';
  static const String _biometricTokenKey = 'flavorflow.hrms.biometric_token';
  static const String _rememberedEmailKey = 'flavorflow.hrms.remembered_email';
  static const String _biometricEnabledKey = 'flavorflow.hrms.biometric_enabled';
  static const String _lastActivityKey = 'flavorflow.hrms.last_activity_at';
  static const String _forceReauthKey = 'flavorflow.hrms.force_reauth';
  static const String _inactivityMinutesKey = 'flavorflow.hrms.inactivity_minutes';
  static const String _textScaleKey = 'flavorflow.hrms.text_scale';
  static const Duration _activityPersistenceInterval = Duration(seconds: 30);

  final ApiClient api;
  final FlutterSecureStorage _secureStorage;
  final LocalAuthentication _localAuth;

  SessionUser? user;
  String? rememberedEmail;
  DateTime? lastActivityAt;
  bool isRestoring = true;
  bool hasBiometricLoginSession = false;
  bool autoBiometricPromptPending = false;
  DateTime? _lastPersistedActivityAt;
  int inactivityTimeoutMinutes = 15;
  double textScaleFactor = 1.0;

  Duration get sessionInactivityTimeout => Duration(minutes: inactivityTimeoutMinutes);

  bool get isAuthenticated => user != null;

  Future<bool> canUseBiometricsOnDevice() async {
    try {
      if (!await _localAuth.canCheckBiometrics) return false;
      return (await _localAuth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> setInactivityTimeoutMinutes(int minutes) async {
    if (!const {5, 10, 15, 30, 60}.contains(minutes)) {
      throw ArgumentError.value(minutes, 'minutes', 'Unsupported session timeout.');
    }
    await _secureStorage.write(key: _inactivityMinutesKey, value: '$minutes');
    inactivityTimeoutMinutes = minutes;
    notifyListeners();
  }

  Future<void> setTextScaleFactor(double factor) async {
    if (!const {0.9, 1.0, 1.1, 1.2}.contains(factor)) {
      throw ArgumentError.value(factor, 'factor', 'Unsupported text size.');
    }
    await _secureStorage.write(key: _textScaleKey, value: factor.toStringAsFixed(1));
    textScaleFactor = factor;
    notifyListeners();
  }

  Future<void> restoreSession() async {
    try {
      final biometricEnabled =
          await _secureStorage.read(key: _biometricEnabledKey) == 'true';
      rememberedEmail = await _secureStorage.read(key: _rememberedEmailKey);
      final storedTimeout = int.tryParse(await _secureStorage.read(key: _inactivityMinutesKey) ?? '');
      if (const {5, 10, 15, 30, 60}.contains(storedTimeout)) {
        inactivityTimeoutMinutes = storedTimeout!;
      }
      final storedTextScale = double.tryParse(await _secureStorage.read(key: _textScaleKey) ?? '');
      if (const {0.9, 1.0, 1.1, 1.2}.contains(storedTextScale)) {
        textScaleFactor = storedTextScale!;
      }
      final lastActivityValue = await _secureStorage.read(key: _lastActivityKey);
      final restoredActivity =
          lastActivityValue == null ? null : DateTime.tryParse(lastActivityValue);
      lastActivityAt = restoredActivity?.toUtc();
      _lastPersistedActivityAt = lastActivityAt;
      final forceReauth = await _secureStorage.read(key: _forceReauthKey) == 'true';
      final inactivityExpired = lastActivityAt == null
          ? !biometricEnabled
          : DateTime.now().toUtc().difference(lastActivityAt!) >= sessionInactivityTimeout;

      if (forceReauth || inactivityExpired) {
        final savedSessionToken = await _secureStorage.read(key: _tokenKey);
        if (savedSessionToken != null && savedSessionToken.isNotEmpty) {
          try {
            await api.postWithToken(
              'auth/logout',
              const <String, dynamic>{},
              savedSessionToken,
            );
          } catch (_) {
            // Local sign-out still applies when the server cannot be reached.
          }
        }
        api.token = null;
        await _deleteStoredValue(_tokenKey);
        await _deleteStoredValue(_forceReauthKey);
        hasBiometricLoginSession = biometricEnabled;
        autoBiometricPromptPending = biometricEnabled;
      } else if (biometricEnabled) {
        // Never read or use the device credential before local authentication.
        hasBiometricLoginSession = true;
        autoBiometricPromptPending = true;
      } else {
        final storedToken = await _secureStorage.read(key: _tokenKey);
        if (storedToken != null && storedToken.isNotEmpty) {
          api.token = storedToken;
          final response = await api.get('auth/me');
          user = SessionUser.fromJson(Map<String, dynamic>.from(response as Map));
        }
      }
    } on ApiException catch (error) {
      api.token = null;
      if (error.statusCode == 401) await _clearSession();
    } catch (_) {
      // Keep remembered credentials if the API is temporarily unavailable.
      api.token = null;
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
    String? previousBiometricToken;
    try {
      previousBiometricToken = await _secureStorage.read(key: _biometricTokenKey);
    } catch (_) {
      previousBiometricToken = null;
    }
    final requestBody = <String, dynamic>{
      'email': loginEmail,
      'password': password,
      'enable_biometrics': rememberMe && enableBiometricLogin,
    };
    if (previousBiometricToken != null && previousBiometricToken.isNotEmpty) {
      requestBody['replace_biometric_token'] = previousBiometricToken;
    }

    final response = await api.post('auth/login', requestBody);
    final payload = Map<String, dynamic>.from(response as Map);
    final token = payload['token']?.toString();
    if (token == null || token.isEmpty) {
      throw const ApiException('The API did not return a valid sign-in session.');
    }

    final now = DateTime.now().toUtc();
    final biometricToken = payload['biometric_token']?.toString();
    api.token = token;
    user = SessionUser.fromJson(Map<String, dynamic>.from(payload['user'] as Map));
    hasBiometricLoginSession = false;
    autoBiometricPromptPending = false;
    rememberedEmail = rememberMe ? loginEmail : null;
    lastActivityAt = now;
    _lastPersistedActivityAt = null;

    try {
      await _deleteStoredValue(_forceReauthKey);
      if (rememberMe) {
        await _secureStorage.write(key: _tokenKey, value: token);
        await _secureStorage.write(key: _rememberedEmailKey, value: loginEmail);
        if (enableBiometricLogin &&
            biometricToken != null &&
            biometricToken.isNotEmpty) {
          await _secureStorage.write(
            key: _biometricTokenKey,
            value: biometricToken,
          );
          await _secureStorage.write(key: _biometricEnabledKey, value: 'true');
          hasBiometricLoginSession = true;
        } else {
          await _deleteStoredValue(_biometricTokenKey);
          await _deleteStoredValue(_biometricEnabledKey);
        }
      } else {
        await _deleteRememberedSession();
      }
      await _persistLastActivity(force: true);
    } catch (_) {
      // In-memory sign-in remains usable; failed secure storage disables remember-me.
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

    String? biometricToken;
    String? previousSessionToken;
    try {
      biometricToken = await _secureStorage.read(key: _biometricTokenKey);
      previousSessionToken = await _secureStorage.read(key: _tokenKey);
    } catch (_) {
      throw const ApiException(
        'The saved session is unavailable. Please sign in with your password.',
      );
    }

    if (biometricToken != null && biometricToken.isNotEmpty) {
      return _signInWithDeviceToken(biometricToken, previousSessionToken);
    }

    // Migrate devices enrolled by the earlier app version: only read the
    // existing API session after local biometrics have succeeded.
    if (previousSessionToken == null || previousSessionToken.isEmpty) {
      await _clearSession();
      notifyListeners();
      throw const ApiException(
        'The saved session is unavailable. Please sign in with your password.',
      );
    }

    api.token = previousSessionToken;
    try {
      final profile = await api.get('auth/me');
      final registration = await api.post('auth/biometric-register');
      final newBiometricToken =
          Map<String, dynamic>.from(registration as Map)['biometric_token']
              ?.toString();
      if (newBiometricToken == null || newBiometricToken.isEmpty) {
        throw const ApiException(
          'Biometric sign-in could not be set up. Please use your password.',
        );
      }
      await _secureStorage.write(key: _biometricTokenKey, value: newBiometricToken);
      await _secureStorage.write(key: _biometricEnabledKey, value: 'true');
      await _deleteStoredValue(_forceReauthKey);
      user = SessionUser.fromJson(Map<String, dynamic>.from(profile as Map));
      hasBiometricLoginSession = true;
      autoBiometricPromptPending = false;
      lastActivityAt = DateTime.now().toUtc();
      _lastPersistedActivityAt = null;
      await _persistLastActivity(force: true);
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

  Future<bool> _signInWithDeviceToken(
    String biometricToken,
    String? previousSessionToken,
  ) async {
    api.token = null;
    final requestBody = <String, dynamic>{'biometric_token': biometricToken};
    if (previousSessionToken != null && previousSessionToken.isNotEmpty) {
      requestBody['previous_session_token'] = previousSessionToken;
    }
    try {
      final response = await api.post('auth/biometric-login', requestBody);
      final payload = Map<String, dynamic>.from(response as Map);
      final sessionToken = payload['token']?.toString();
      final rotatedBiometricToken = payload['biometric_token']?.toString();
      if (sessionToken == null ||
          sessionToken.isEmpty ||
          rotatedBiometricToken == null ||
          rotatedBiometricToken.isEmpty) {
        throw const ApiException(
          'The saved biometric session is invalid. Sign in with your password.',
        );
      }

      final signedInUser =
          SessionUser.fromJson(Map<String, dynamic>.from(payload['user'] as Map));
      await _secureStorage.write(key: _tokenKey, value: sessionToken);
      await _secureStorage.write(
        key: _biometricTokenKey,
        value: rotatedBiometricToken,
      );
      await _secureStorage.write(key: _biometricEnabledKey, value: 'true');
      await _deleteStoredValue(_forceReauthKey);
      api.token = sessionToken;
      user = signedInUser;
      hasBiometricLoginSession = true;
      autoBiometricPromptPending = false;
      lastActivityAt = DateTime.now().toUtc();
      _lastPersistedActivityAt = null;
      await _persistLastActivity(force: true);
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      api.token = null;
      if (error.statusCode == 401) {
        await _clearSession();
        notifyListeners();
        throw const ApiException(
          'Your saved biometric sign-in expired. Sign in with your password again.',
          statusCode: 401,
        );
      }
      rethrow;
    } catch (_) {
      api.token = null;
      rethrow;
    }
  }

  bool consumeAutomaticBiometricPrompt() {
    if (!autoBiometricPromptPending || !hasBiometricLoginSession || user != null) {
      return false;
    }
    autoBiometricPromptPending = false;
    return true;
  }

  Future<void> recordUserActivity() async {
    if (!isAuthenticated) return;
    lastActivityAt = DateTime.now().toUtc();
    await _persistLastActivity();
  }

  Future<void> persistLastActivityAt() => _persistLastActivity(force: true);

  Future<void> _persistLastActivity({bool force = false}) async {
    final activity = lastActivityAt;
    if (activity == null) return;
    final lastPersisted = _lastPersistedActivityAt;
    if (!force &&
        lastPersisted != null &&
        activity.difference(lastPersisted) < _activityPersistenceInterval) {
      return;
    }
    _lastPersistedActivityAt = activity;
    try {
      await _secureStorage.write(
        key: _lastActivityKey,
        value: activity.toUtc().toIso8601String(),
      );
    } catch (_) {
      // The in-memory idle timer still protects an active app session.
    }
  }

  Future<void> refreshUser() async {
    final response = await api.get('auth/me');
    user = SessionUser.fromJson(Map<String, dynamic>.from(response as Map));
    notifyListeners();
  }

  Future<void> signOut() async {
    final token = api.token;
    String? biometricToken;
    try {
      biometricToken = await _secureStorage.read(key: _biometricTokenKey);
    } catch (_) {
      biometricToken = null;
    }

    final revokeRequest = biometricToken == null || biometricToken.isEmpty
        ? null
        : api.post('auth/biometric-revoke', {
            'biometric_token': biometricToken,
          });
    final logoutRequest = token == null || token.isEmpty
        ? null
        : api.postWithToken('auth/logout', const <String, dynamic>{}, token);

    api.token = null;
    user = null;
    lastActivityAt = null;
    _lastPersistedActivityAt = null;
    await _deleteRememberedSession();
    await _deleteStoredValue(_lastActivityKey);
    notifyListeners();
    await _ignoreFailure(revokeRequest);
    await _ignoreFailure(logoutRequest);
  }

  Future<void> signOutForInactivity({
    bool promptBiometricsOnNextLogin = false,
  }) async {
    final token = api.token;
    final logoutRequest = token == null || token.isEmpty
        ? null
        : api.postWithToken('auth/logout', const <String, dynamic>{}, token);

    api.token = null;
    user = null;
    autoBiometricPromptPending =
        promptBiometricsOnNextLogin && hasBiometricLoginSession;
    try {
      await _secureStorage.write(key: _forceReauthKey, value: 'true');
    } catch (_) {
      // Clear the in-memory session even if secure storage is temporarily unavailable.
    }
    await _deleteStoredValue(_tokenKey);
    notifyListeners();
    await _ignoreFailure(logoutRequest);
  }

  Future<void> _signOutLocally({bool keepBiometrics = false}) async {
    api.token = null;
    user = null;
    autoBiometricPromptPending = false;
    if (!keepBiometrics) {
      await _deleteRememberedSession();
    }
  }

  Future<void> _clearSession() async {
    await _signOutLocally();
    lastActivityAt = null;
    _lastPersistedActivityAt = null;
    for (final key in const [_lastActivityKey, _forceReauthKey]) {
      await _deleteStoredValue(key);
    }
  }

  Future<void> _deleteRememberedSession() async {
    hasBiometricLoginSession = false;
    autoBiometricPromptPending = false;
    rememberedEmail = null;
    for (final key in const [
      _tokenKey,
      _biometricTokenKey,
      _rememberedEmailKey,
      _biometricEnabledKey,
      _forceReauthKey,
    ]) {
      await _deleteStoredValue(key);
    }
  }

  Future<void> _deleteStoredValue(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } catch (_) {
      // A secure-storage failure should not block returning to the sign-in view.
    }
  }

  Future<void> _ignoreFailure(Future<dynamic>? request) async {
    if (request == null) return;
    try {
      await request;
    } catch (_) {
      // Local sign-out remains effective if the API is unavailable.
    }
  }

  @override
  void dispose() {
    api.dispose();
    super.dispose();
  }
}
