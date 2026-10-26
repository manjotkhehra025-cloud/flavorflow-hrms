import 'package:flutter/foundation.dart';

import '../models/payslip.dart';
import '../repositories/payslip_repository.dart';

class PayslipProvider extends ChangeNotifier {
  PayslipProvider(this._repo);
  final PayslipRepository _repo;

  List<Payslip> _payslips = [];
  bool _loading = false;

  List<Payslip> get payslips => _payslips;
  bool get loading => _loading;
  Payslip? get latest => _payslips.isEmpty ? null : _payslips.first;

  Future<void> load(String employeeId) async {
    _loading = true;
    notifyListeners();
    try {
      _payslips = await _repo.getPayslips(employeeId);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String?> downloadPdf(Payslip payslip) => _repo.downloadPdf(payslip);
}
