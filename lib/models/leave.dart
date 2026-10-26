enum LeaveType { casual, sick, earned, unpaid }

extension LeaveTypeX on LeaveType {
  String get label {
    switch (this) {
      case LeaveType.casual:
        return 'Casual Leave';
      case LeaveType.sick:
        return 'Sick Leave';
      case LeaveType.earned:
        return 'Earned Leave';
      case LeaveType.unpaid:
        return 'Leave Without Pay';
    }
  }

  String get short {
    switch (this) {
      case LeaveType.casual:
        return 'CL';
      case LeaveType.sick:
        return 'SL';
      case LeaveType.earned:
        return 'EL';
      case LeaveType.unpaid:
        return 'LWP';
    }
  }

  /// Paid leave types have a yearly quota.
  bool get hasQuota => this != LeaveType.unpaid;
}

enum LeaveStatus { pending, approved, rejected, cancelled }

extension LeaveStatusX on LeaveStatus {
  String get label {
    switch (this) {
      case LeaveStatus.pending:
        return 'Pending';
      case LeaveStatus.approved:
        return 'Approved';
      case LeaveStatus.rejected:
        return 'Rejected';
      case LeaveStatus.cancelled:
        return 'Cancelled';
    }
  }
}

class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.type,
    required this.fromDate,
    required this.toDate,
    required this.reason,
    required this.appliedOn,
    this.status = LeaveStatus.pending,
    this.approverComment,
  });

  final String id;
  final String employeeId;
  final String employeeName;
  final LeaveType type;
  final DateTime fromDate;
  final DateTime toDate;
  final String reason;
  final DateTime appliedOn;
  final LeaveStatus status;
  final String? approverComment;

  /// Number of leave days (Sundays are not counted).
  int get days => countLeaveDays(fromDate, toDate);

  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final to = DateTime(toDate.year, toDate.month, toDate.day);
    return !d.isBefore(from) && !d.isAfter(to);
  }

  LeaveRequest copyWith({LeaveStatus? status, String? approverComment}) {
    return LeaveRequest(
      id: id,
      employeeId: employeeId,
      employeeName: employeeName,
      type: type,
      fromDate: fromDate,
      toDate: toDate,
      reason: reason,
      appliedOn: appliedOn,
      status: status ?? this.status,
      approverComment: approverComment ?? this.approverComment,
    );
  }
}

int countLeaveDays(DateTime from, DateTime to) {
  var d = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);
  var count = 0;
  while (!d.isAfter(end)) {
    if (d.weekday != DateTime.sunday) count++;
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return count;
}

class LeaveBalance {
  const LeaveBalance({required this.type, required this.total, required this.used, this.pending = 0});
  final LeaveType type;
  final double total;
  final double used;
  final double pending;

  double get available => (total - used).clamp(0, total).toDouble();
}
