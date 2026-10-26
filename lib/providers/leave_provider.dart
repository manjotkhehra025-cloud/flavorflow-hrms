import 'package:flutter/foundation.dart';

import '../core/app_exception.dart';
import '../models/leave.dart';
import '../repositories/leave_repository.dart';

class LeaveProvider extends ChangeNotifier {
  LeaveProvider(this._repo);
  final LeaveRepository _repo;

  List<LeaveBalance> _balances = [];
  List<LeaveRequest> _myRequests = [];
  List<LeaveRequest> _allRequests = [];
  bool _loading = false;
  bool _submitting = false;

  List<LeaveBalance> get balances => _balances;
  List<LeaveRequest> get myRequests => _myRequests;
  List<LeaveRequest> get allRequests => _allRequests;
  List<LeaveRequest> get pendingApprovals =>
      _allRequests.where((r) => r.status == LeaveStatus.pending).toList();
  bool get loading => _loading;
  bool get submitting => _submitting;

  Future<void> loadMine(String employeeId) async {
    _loading = true;
    notifyListeners();
    try {
      _balances = await _repo.getBalances(employeeId);
      _myRequests = await _repo.getMyRequests(employeeId);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadAll() async {
    _loading = true;
    notifyListeners();
    try {
      _allRequests = await _repo.getAllRequests();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Returns an error message, or null on success.
  Future<String?> apply({
    required String employeeId,
    required String employeeName,
    required LeaveType type,
    required DateTime from,
    required DateTime to,
    required String reason,
  }) async {
    _submitting = true;
    notifyListeners();
    try {
      await _repo.apply(
        employeeId: employeeId,
        employeeName: employeeName,
        type: type,
        fromDate: from,
        toDate: to,
        reason: reason,
      );
      await loadMine(employeeId);
      return null;
    } on AppException catch (e) {
      return e.message;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  Future<String?> cancel(LeaveRequest request) async {
    try {
      await _repo.cancel(request.id);
      await loadMine(request.employeeId);
      return null;
    } on AppException catch (e) {
      return e.message;
    }
  }

  Future<String?> decide(LeaveRequest request, bool approve, {String? comment}) async {
    try {
      await _repo.updateStatus(
        request.id,
        approve ? LeaveStatus.approved : LeaveStatus.rejected,
        comment: (comment == null || comment.trim().isEmpty) ? null : comment.trim(),
      );
      await loadAll();
      return null;
    } on AppException catch (e) {
      return e.message;
    }
  }
}
