import 'attendance_repository.dart';
import 'auth_repository.dart';
import 'content_repository.dart';
import 'employee_repository.dart';
import 'leave_repository.dart';
import 'mock/mock_attendance_repository.dart';
import 'mock/mock_auth_repository.dart';
import 'mock/mock_content_repository.dart';
import 'mock/mock_database.dart';
import 'mock/mock_employee_repository.dart';
import 'mock/mock_leave_repository.dart';
import 'mock/mock_payslip_repository.dart';
import 'payslip_repository.dart';

/// All data sources used by the app, in one place.
class Repositories {
  const Repositories({
    required this.auth,
    required this.employees,
    required this.attendance,
    required this.leave,
    required this.payslips,
    required this.content,
  });

  final AuthRepository auth;
  final EmployeeRepository employees;
  final AttendanceRepository attendance;
  final LeaveRepository leave;
  final PayslipRepository payslips;
  final ContentRepository content;
}

/// THE ONE PLACE TO SWITCH BACKENDS.
///
/// Right now every repository is a mock that keeps data in memory
/// (data resets when the app restarts). To connect a real backend:
///   1. Create classes such as `FirebaseAuthRepository implements AuthRepository`
///      (or `RestAuthRepository` for your own API) in `lib/repositories/firebase/`.
///   2. Return them here instead of the mock ones.
/// No screen or provider needs to change.
Repositories buildRepositories() {
  final db = MockDatabase.seeded();
  return Repositories(
    auth: MockAuthRepository(db),
    employees: MockEmployeeRepository(db),
    attendance: MockAttendanceRepository(db),
    leave: MockLeaveRepository(db),
    payslips: MockPayslipRepository(db),
    content: MockContentRepository(db),
  );
}
