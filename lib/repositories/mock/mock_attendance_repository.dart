import '../../core/app_exception.dart';
import '../../core/formatters.dart';
import '../../models/attendance.dart';
import '../attendance_repository.dart';
import 'mock_database.dart';

class MockAttendanceRepository implements AttendanceRepository {
  MockAttendanceRepository(this._db);
  final MockDatabase _db;

  @override
  Future<AttendanceRecord> getToday(String employeeId) async {
    await MockDatabase.latency(150);
    return _db.resolve(employeeId, DateTime.now());
  }

  @override
  Future<AttendanceRecord> punchIn(String employeeId, {PunchLocation? location, String? selfieUrl}) async {
    await MockDatabase.latency(400);
    final now = DateTime.now();
    final k = MockDatabase.key(employeeId, now);
    final existing = _db.attendance[k];
    if (existing != null && existing.hasPunchedIn) {
      throw const AppException('You have already punched in today');
    }
    final record = AttendanceRecord(
      employeeId: employeeId,
      date: dateOnly(now),
      status: AttendanceStatus.present,
      punchIn: now,
      punchInLocation: location,
      selfieUrl: selfieUrl,
    );
    _db.attendance[k] = record;
    return record;
  }

  @override
  Future<AttendanceRecord> punchOut(String employeeId, {PunchLocation? location}) async {
    await MockDatabase.latency(400);
    final now = DateTime.now();
    final k = MockDatabase.key(employeeId, now);
    final existing = _db.attendance[k];
    if (existing == null || !existing.hasPunchedIn) {
      throw const AppException('Please punch in first');
    }
    if (existing.hasPunchedOut) {
      throw const AppException('You have already punched out today');
    }
    final record = existing.copyWith(punchOut: now, punchOutLocation: location);
    _db.attendance[k] = record;
    return record;
  }

  @override
  Future<List<AttendanceRecord>> getMonth(String employeeId, int year, int month) async {
    await MockDatabase.latency();
    final today = dateOnly(DateTime.now());
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final result = <AttendanceRecord>[];
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      if (date.isAfter(today)) break;
      result.add(_db.resolve(employeeId, date));
    }
    return result;
  }

  @override
  Future<List<AttendanceRecord>> getDailyReport(DateTime date) async {
    await MockDatabase.latency();
    return _db.employees.where((e) => e.isActive).map((e) => _db.resolve(e.id, date)).toList();
  }
}
