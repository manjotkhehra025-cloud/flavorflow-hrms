import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session.dart';

/// Base URL of the HRMate backend (same API the web app serves).
/// Override at build time: --dart-define=API_BASE_URL=https://…
const kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://hr.flavorflow.co.in',
);

final apiProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: kApiBaseUrl,
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
    headers: {'Accept': 'application/json'},
  ));
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      final session = ref.read(sessionStoreProvider);
      final token = session.cachedToken;
      if (token != null && !options.headers.containsKey('Authorization')) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (err, handler) async {
      // Expired / revoked token: drop the session so the router sends the
      // user back to login instead of a dead home screen. Login 401 is a
      // wrong password — don't wipe a session that isn't this request.
      final status = err.response?.statusCode;
      final path = err.requestOptions.path;
      final skip = err.requestOptions.extra['skipAuthWipe'] == true;
      if (status == 401 && !skip && !path.contains('/api/auth/login')) {
        await ref.read(sessionStoreProvider).clear();
      }
      handler.next(err);
    },
  ));
  return dio;
});

/// Error message to show for a failed request (network vs server).
String apiErrorMessage(Object err, {String fallback = 'Something went wrong. Try again.'}) {
  if (err is DioException) {
    final data = err.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      return 'No connection — check your internet and try again.';
    }
  }
  return fallback;
}
