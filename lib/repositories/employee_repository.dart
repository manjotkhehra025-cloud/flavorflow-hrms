import '../models/employee.dart';

abstract class EmployeeRepository {
  Future<List<Employee>> getAll();
  Future<Employee?> getById(String id);

  /// Creates an employee. [initialPassword] is used for their first login.
  Future<Employee> add(Employee employee, {required String initialPassword});
  Future<Employee> update(Employee employee);
  Future<String> nextEmployeeId();
}
