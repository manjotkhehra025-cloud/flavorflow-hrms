import 'package:flutter/foundation.dart';

import '../core/app_exception.dart';
import '../models/employee.dart';
import '../repositories/employee_repository.dart';

/// Admin: employee directory.
class EmployeeProvider extends ChangeNotifier {
  EmployeeProvider(this._repo);
  final EmployeeRepository _repo;

  List<Employee> _employees = [];
  bool _loading = false;
  String _query = '';

  bool get loading => _loading;
  List<Employee> get all => _employees;

  List<Employee> get filtered {
    if (_query.isEmpty) return _employees;
    final q = _query.toLowerCase();
    return _employees
        .where((e) =>
            e.name.toLowerCase().contains(q) ||
            e.id.toLowerCase().contains(q) ||
            e.department.toLowerCase().contains(q) ||
            e.designation.toLowerCase().contains(q))
        .toList();
  }

  String nameOf(String id) {
    for (final e in _employees) {
      if (e.id == id) return e.name;
    }
    return id;
  }

  Employee? byId(String id) {
    for (final e in _employees) {
      if (e.id == id) return e;
    }
    return null;
  }

  void search(String query) {
    _query = query.trim();
    notifyListeners();
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _employees = await _repo.getAll();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String> nextId() => _repo.nextEmployeeId();

  Future<String?> add(Employee e, String password) async {
    try {
      await _repo.add(e, initialPassword: password);
      await load();
      return null;
    } on AppException catch (ex) {
      return ex.message;
    }
  }

  Future<String?> update(Employee e) async {
    try {
      await _repo.update(e);
      await load();
      return null;
    } on AppException catch (ex) {
      return ex.message;
    }
  }
}
