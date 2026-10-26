import '../../core/app_exception.dart';
import '../../models/employee.dart';
import '../employee_repository.dart';
import 'mock_database.dart';

class MockEmployeeRepository implements EmployeeRepository {
  MockEmployeeRepository(this._db);
  final MockDatabase _db;

  @override
  Future<List<Employee>> getAll() async {
    await MockDatabase.latency();
    final list = List<Employee>.from(_db.employees);
    list.sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  @override
  Future<Employee?> getById(String id) async {
    await MockDatabase.latency(100);
    return _db.employee(id);
  }

  @override
  Future<Employee> add(Employee employee, {required String initialPassword}) async {
    await MockDatabase.latency();
    if (_db.employee(employee.id) != null) {
      throw AppException('Employee ID ${employee.id} already exists');
    }
    _db.employees.add(employee);
    _db.passwords[employee.id] = initialPassword;
    return employee;
  }

  @override
  Future<Employee> update(Employee employee) async {
    await MockDatabase.latency();
    final i = _db.employees.indexWhere((e) => e.id == employee.id);
    if (i < 0) throw const AppException('Employee not found');
    _db.employees[i] = employee;
    return employee;
  }

  @override
  Future<String> nextEmployeeId() async {
    var max = 0;
    for (final e in _db.employees) {
      if (e.id.startsWith('EMP')) {
        final n = int.tryParse(e.id.substring(3)) ?? 0;
        if (n > max) max = n;
      }
    }
    return 'EMP${(max + 1).toString().padLeft(3, '0')}';
  }
}
