/// A simple, user-friendly error used across the app.
class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => message;
}
