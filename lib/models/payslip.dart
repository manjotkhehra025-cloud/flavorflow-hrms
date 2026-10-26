class PayItem {
  const PayItem(this.label, this.amount);
  final String label;
  final double amount;
}

class Payslip {
  const Payslip({
    required this.id,
    required this.employeeId,
    required this.month,
    required this.earnings,
    required this.deductions,
    required this.workingDays,
    required this.paidDays,
    this.bankAccountMasked,
  });

  final String id;
  final String employeeId;

  /// First day of the pay month.
  final DateTime month;
  final List<PayItem> earnings;
  final List<PayItem> deductions;
  final int workingDays;
  final double paidDays;
  final String? bankAccountMasked;

  double get grossEarnings => earnings.fold(0, (sum, e) => sum + e.amount);
  double get totalDeductions => deductions.fold(0, (sum, e) => sum + e.amount);
  double get netPay => grossEarnings - totalDeductions;
}
