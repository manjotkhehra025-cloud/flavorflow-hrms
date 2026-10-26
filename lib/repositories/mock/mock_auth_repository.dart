import '../../core/app_exception.dart';
import '../../models/employee.dart';
import '../auth_repository.dart';
import 'mock_database.dart';

class MockAuthRepository implements AuthRepository {
  MockAuthRepository(this._db);
  final MockDatabase _db;

  @override
  Future<Employee> login({required String employeeId, required String password}) async {
    await MockDatabase.latency(600);
    final id = employeeId.trim().toUpperCase();
    final employee = _db.employee(id);
    if (employee == null || _db.passwords[id] != password) {
      throw const AppException('Invalid employee ID or password');
    }
    if (!employee.isActive) {
      throw const AppException('Your account is inactive. Please contact HR.');
    }
    _db.currentUserId = id;
    return employee;
  }

  @override
  Future<Employee?> currentUser() async {
    await MockDatabase.latency(100);
    final id = _db.currentUserId;
    return id == null ? null : _db.employee(id);
  }

  @override
  Future<void> logout() async {
    await MockDatabase.latency(100);
    _db.currentUserId = null;
  }

  @override
  Future<void> changePassword({required String employeeId, required String oldPassword, required String newPassword}) async {
    await MockDatabase.latency();
    if (_db.passwords[employeeId] != oldPassword) {
      throw const AppException('Current password is incorrect');
    }
    if (newPassword.length < 6) {
      throw const AppException('New password must be at least 6 characters');
    }
    _db.passwords[employeeId] = newPassword;
  }
}
