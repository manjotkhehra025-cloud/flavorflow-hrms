import '../../core/app_exception.dart';
import '../../core/formatters.dart';
import '../../models/leave.dart';
import '../leave_repository.dart';
import 'mock_database.dart';

class MockLeaveRepository implements LeaveRepository {
  MockLeaveRepository(this._db);
  final MockDatabase _db;
  int _seq = 100;

  @override
  Future<List<LeaveBalance>> getBalances(String employeeId) async {
    await MockDatabase.latency(150);
    final year = DateTime.now().year;
    return MockDatabase.leaveQuota.entries.map((q) {
      double used = 0, pending = 0;
      for (final l in _db.leaves) {
        if (l.employeeId != employeeId || l.type != q.key || l.fromDate.year != year) continue;
        if (l.status == LeaveStatus.approved) used += l.days;
        if (l.status == LeaveStatus.pending) pending += l.days;
      }
      return LeaveBalance(type: q.key, total: q.value, used: used, pending: pending);
    }).toList();
  }

  @override
  Future<List<LeaveRequest>> getMyRequests(String employeeId) async {
    await MockDatabase.latency();
    final list = _db.leaves.where((l) => l.employeeId == employeeId).toList();
    list.sort((a, b) => b.appliedOn.compareTo(a.appliedOn));
    return list;
  }

  @override
  Future<List<LeaveRequest>> getAllRequests({bool pendingOnly = false}) async {
    await MockDatabase.latency();
    final list = _db.leaves.where((l) => !pendingOnly || l.status == LeaveStatus.pending).toList();
    list.sort((a, b) => b.appliedOn.compareTo(a.appliedOn));
    return list;
  }

  @override
  Future<LeaveRequest> apply({
    required String employeeId,
    required String employeeName,
    required LeaveType type,
    required DateTime fromDate,
    required DateTime toDate,
    required String reason,
  }) async {
    await MockDatabase.latency(400);
    final from = dateOnly(fromDate);
    final to = dateOnly(toDate);
    if (to.isBefore(from)) throw const AppException('End date cannot be before start date');
    final days = countLeaveDays(from, to);
    if (days == 0) throw const AppException('Selected dates fall on week-offs only');
    if (reason.trim().isEmpty) throw const AppException('Please enter a reason');

    for (final l in _db.leaves) {
      if (l.employeeId != employeeId) continue;
      if (l.status != LeaveStatus.pending && l.status != LeaveStatus.approved) continue;
      final overlaps = !(to.isBefore(dateOnly(l.fromDate)) || from.isAfter(dateOnly(l.toDate)));
      if (overlaps) throw const AppException('You already have a leave request for these dates');
    }

    if (type.hasQuota) {
      final balances = await getBalances(employeeId);
      final b = balances.firstWhere((x) => x.type == type);
      final free = b.available - b.pending;
      if (days > free) {
        throw AppException('Not enough ${type.label} balance (available: ${free.toStringAsFixed(0)} days)');
      }
    }

    final request = LeaveRequest(
      id: 'L${_seq++}',
      employeeId: employeeId,
      employeeName: employeeName,
      type: type,
      fromDate: from,
      toDate: to,
      reason: reason.trim(),
      appliedOn: DateTime.now(),
    );
    _db.leaves.add(request);
    return request;
  }

  @override
  Future<LeaveRequest> cancel(String requestId) async {
    await MockDatabase.latency();
    final i = _db.leaves.indexWhere((l) => l.id == requestId);
    if (i < 0) throw const AppException('Leave request not found');
    if (_db.leaves[i].status != LeaveStatus.pending) {
      throw const AppException('Only pending requests can be cancelled');
    }
    _db.leaves[i] = _db.leaves[i].copyWith(status: LeaveStatus.cancelled);
    return _db.leaves[i];
  }

  @override
  Future<LeaveRequest> updateStatus(String requestId, LeaveStatus status, {String? comment}) async {
    await MockDatabase.latency();
    final i = _db.leaves.indexWhere((l) => l.id == requestId);
    if (i < 0) throw const AppException('Leave request not found');
    _db.leaves[i] = _db.leaves[i].copyWith(status: status, approverComment: comment);
    // TODO(push): notify the employee (e.g. Firebase Cloud Messaging).
    return _db.leaves[i];
  }
}
