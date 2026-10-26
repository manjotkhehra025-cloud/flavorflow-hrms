import '../models/payslip.dart';

abstract class PayslipRepository {
  /// Latest first.
  Future<List<Payslip>> getPayslips(String employeeId);

  /// Returns a local file path / URL of the PDF.
  /// TODO(pdf): generate with the `pdf` + `printing` packages or download from backend.
  Future<String?> downloadPdf(Payslip payslip);
}
