import '../models/employee.dart';

/// Authentication contract.
///
/// The app only talks to this interface. Today it is backed by
/// [MockAuthRepository]; to go live, create e.g. `FirebaseAuthRepository`
/// that implements this class and register it in `repository_factory.dart`.
abstract class AuthRepository {
  /// Logs in with employee ID + password. Throws AppException on failure.
  Future<Employee> login({required String employeeId, required String password});

  /// Returns the logged-in employee, or null if nobody is logged in.
  Future<Employee?> currentUser();

  Future<void> logout();

  Future<void> changePassword({required String employeeId, required String oldPassword, required String newPassword});
}
