import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.details});

  final String message;
  final int? statusCode;
  final Object? details;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? baseUrl})
      : _baseUri = Uri.parse(baseUrl ?? _defaultBaseUrl),
        _httpClient = HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 12);
  }

  static const String _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080/api/v1/',
  );

  final Uri _baseUri;
  final HttpClient _httpClient;
  String? token;

  void dispose() => _httpClient.close(force: true);

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      request('GET', path, query: query);

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
      request('POST', path, body: body ?? const <String, dynamic>{});

  Future<dynamic> postWithToken(
    String path,
    Map<String, dynamic> body,
    String bearerToken,
  ) => request('POST', path, body: body, bearerToken: bearerToken);

  Future<dynamic> patch(String path, Map<String, dynamic> body) =>
      request('PATCH', path, body: body);

  Future<dynamic> delete(String path) => request('DELETE', path);

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    String? bearerToken,
  }) async {
    final basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path
        : '${_baseUri.path}/';
    final relativePath = path.replaceFirst(RegExp(r'^/+'), '');
    final uri = _baseUri.replace(
      path: '$basePath$relativePath',
      queryParameters: query == null || query.isEmpty ? null : query,
    );

    try {
      final request = await _httpClient.openUrl(method, uri).timeout(
            const Duration(seconds: 18),
          );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.contentType = ContentType.json;
      final currentToken = bearerToken ?? token;
      if (currentToken != null && currentToken.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $currentToken');
      }
      if (body != null) request.write(jsonEncode(body));

      final response = await request.close().timeout(const Duration(seconds: 24));
      final responseText = await utf8.decoder.bind(response).join();
      final dynamic decoded = responseText.isEmpty ? <String, dynamic>{} : jsonDecode(responseText);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final responseMap = decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
        final error = responseMap['error'];
        final errorMap = error is Map<String, dynamic> ? error : const <String, dynamic>{};
        throw ApiException(
          errorMap['message']?.toString() ?? 'Request failed (${response.statusCode}).',
          statusCode: response.statusCode,
          details: errorMap['details'],
        );
      }
      return decoded;
    } on ApiException {
      rethrow;
    } on SocketException {
      throw const ApiException(
        'Cannot reach the HRMS API. Start the backend and check the API_BASE_URL setting.',
      );
    } on TimeoutException {
      throw const ApiException('The HRMS API took too long to respond. Please try again.');
    } on FormatException {
      throw const ApiException('The HRMS API returned an invalid response.');
    }
  }
}
