import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/attendance.dart';
import '../models/leave.dart';

Color attendanceColor(AttendanceStatus s) {
  switch (s) {
    case AttendanceStatus.present:
      return AppTheme.success;
    case AttendanceStatus.absent:
      return AppTheme.danger;
    case AttendanceStatus.leave:
      return AppTheme.warning;
    case AttendanceStatus.holiday:
      return Colors.purple;
    case AttendanceStatus.weekend:
      return AppTheme.muted;
    case AttendanceStatus.notMarked:
      return Colors.blueGrey;
  }
}

Color leaveStatusColor(LeaveStatus s) {
  switch (s) {
    case LeaveStatus.pending:
      return AppTheme.warning;
    case LeaveStatus.approved:
      return AppTheme.success;
    case LeaveStatus.rejected:
      return AppTheme.danger;
    case LeaveStatus.cancelled:
      return AppTheme.muted;
  }
}
