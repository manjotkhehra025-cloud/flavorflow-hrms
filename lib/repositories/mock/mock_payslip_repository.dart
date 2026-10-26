import '../../models/payslip.dart';
import '../payslip_repository.dart';
import 'mock_database.dart';

/// Generates realistic sample payslips from each employee's monthly CTC.
/// Indian structure: Basic, HRA, Conveyance, Special Allowance;
/// deductions: PF (12% of basic, capped), ESI (0.75% if gross <= 21,000),
/// Professional Tax and TDS.
class MockPayslipRepository implements PayslipRepository {
  MockPayslipRepository(this._db);
  final MockDatabase _db;

  @override
  Future<List<Payslip>> getPayslips(String employeeId) async {
    await MockDatabase.latency();
    final employee = _db.employee(employeeId);
    if (employee == null) return [];
    final now = DateTime.now();
    final slips = <Payslip>[];
    for (var i = 1; i <= 6; i++) {
      final month = DateTime(now.year, now.month - i, 1);
      if (month.isBefore(DateTime(employee.joiningDate.year, employee.joiningDate.month, 1))) break;
      slips.add(_build(employeeId, employee.monthlyCtc, month));
    }
    return slips;
  }

  Payslip _build(String employeeId, double gross, DateTime month) {
    final basic = (gross * 0.5).roundToDouble();
    final hra = (gross * 0.2).roundToDouble();
    const conveyance = 1600.0;
    final special = (gross - basic - hra - conveyance).clamp(0, gross).toDouble();

    final pf = (basic * 0.12).clamp(0, 1800).roundToDouble();
    final esi = gross <= 21000 ? (gross * 0.0075).ceilToDouble() : 0.0;
    const pt = 200.0;
    final tds = gross > 60000 ? ((gross - 60000) * 0.1).roundToDouble() : 0.0;

    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    return Payslip(
      id: '$employeeId-${month.year}-${month.month}',
      employeeId: employeeId,
      month: month,
      workingDays: daysInMonth,
      paidDays: daysInMonth.toDouble(),
      bankAccountMasked: 'XXXX XXXX 4321',
      earnings: [
        PayItem('Basic Salary', basic),
        PayItem('House Rent Allowance', hra),
        const PayItem('Conveyance Allowance', conveyance),
        PayItem('Special Allowance', special),
      ],
      deductions: [
        PayItem('Provident Fund (PF)', pf),
        if (esi > 0) PayItem('ESI', esi),
        const PayItem('Professional Tax', pt),
        if (tds > 0) PayItem('Income Tax (TDS)', tds),
      ],
    );
  }

  @override
  Future<String?> downloadPdf(Payslip payslip) async {
    // TODO(pdf): build the PDF with the `pdf` package and share/save it with
    // `printing` or `share_plus`, or download it from your backend.
    await MockDatabase.latency(300);
    return null;
  }
}
