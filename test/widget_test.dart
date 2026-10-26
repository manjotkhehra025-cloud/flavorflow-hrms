import 'package:flutter_test/flutter_test.dart';
import 'package:ihrms/models/leave.dart';
import 'package:ihrms/repositories/repository_factory.dart';

void main() {
  test('leave day count skips Sundays', () {
    // 2026-10-24 is a Saturday, 2026-10-26 a Monday.
    expect(countLeaveDays(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
  });

  test('mock login works with demo credentials', () async {
    final repos = buildRepositories();
    final user = await repos.auth.login(employeeId: 'emp001', password: 'emp123');
    expect(user.id, 'EMP001');
    final slips = await repos.payslips.getPayslips(user.id);
    expect(slips, isNotEmpty);
    expect(slips.first.netPay, greaterThan(0));
  });
}
