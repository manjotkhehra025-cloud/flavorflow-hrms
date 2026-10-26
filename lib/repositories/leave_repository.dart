import '../models/leave.dart';

abstract class LeaveRepository {
  Future<List<LeaveBalance>> getBalances(String employeeId);
  Future<List<LeaveRequest>> getMyRequests(String employeeId);

  /// Admin: all requests (optionally only pending).
  Future<List<LeaveRequest>> getAllRequests({bool pendingOnly = false});

  Future<LeaveRequest> apply({
    required String employeeId,
    required String employeeName,
    required LeaveType type,
    required DateTime fromDate,
    required DateTime toDate,
    required String reason,
  });

  Future<LeaveRequest> cancel(String requestId);
  Future<LeaveRequest> updateStatus(String requestId, LeaveStatus status, {String? comment});
}
