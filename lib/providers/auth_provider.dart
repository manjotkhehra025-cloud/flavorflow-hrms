import 'package:flutter/foundation.dart';

import '../core/app_exception.dart';
import '../models/employee.dart';
import '../repositories/auth_repository.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._repo);
  final AuthRepository _repo;

  Employee? _user;
  bool _loading = false;
  String? _error;

  Employee? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> restoreSession() async {
    _user = await _repo.currentUser();
    notifyListeners();
  }

  Future<bool> login(String employeeId, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _user = await _repo.login(employeeId: employeeId, password: password);
      return true;
    } on AppException catch (e) {
      _error = e.message;
      return false;
    } catch (_) {
      _error = 'Something went wrong. Please try again.';
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    _user = null;
    notifyListeners();
  }

  /// Keep the session user in sync after an admin edits their own profile.
  void refreshUser(Employee updated) {
    if (_user?.id == updated.id) {
      _user = updated;
      notifyListeners();
    }
  }

  Future<String?> changePassword(String oldPassword, String newPassword) async {
    final u = _user;
    if (u == null) return 'Not logged in';
    try {
      await _repo.changePassword(employeeId: u.id, oldPassword: oldPassword, newPassword: newPassword);
      return null;
    } on AppException catch (e) {
      return e.message;
    }
  }
}
