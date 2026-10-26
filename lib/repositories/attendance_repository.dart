import '../models/attendance.dart';

abstract class AttendanceRepository {
  /// Today's record for the employee (status notMarked if no punch yet).
  Future<AttendanceRecord> getToday(String employeeId);

  Future<AttendanceRecord> punchIn(String employeeId, {PunchLocation? location, String? selfieUrl});
  Future<AttendanceRecord> punchOut(String employeeId, {PunchLocation? location});

  /// One record per day of the month up to today.
  Future<List<AttendanceRecord>> getMonth(String employeeId, int year, int month);

  /// Admin: everyone's attendance for one day.
  Future<List<AttendanceRecord>> getDailyReport(DateTime date);
}
