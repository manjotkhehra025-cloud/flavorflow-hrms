import 'package:flutter/foundation.dart';

import '../core/app_exception.dart';
import '../models/attendance.dart';
import '../repositories/attendance_repository.dart';
import '../services/punch_verification_service.dart';

class AttendanceProvider extends ChangeNotifier {
  AttendanceProvider(this._repo, {PunchVerificationService? verification})
      : _verification = verification ?? const PunchVerificationService();

  final AttendanceRepository _repo;
  final PunchVerificationService _verification;

  String? _employeeId;
  AttendanceRecord? _today;
  List<AttendanceRecord> _month = [];
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = false;
  bool _punching = false;

  AttendanceRecord? get today => _today;
  List<AttendanceRecord> get monthRecords => _month;
  DateTime get selectedMonth => _selectedMonth;
  bool get loading => _loading;
  bool get punching => _punching;

  bool get isCurrentMonth {
    final now = DateTime.now();
    return _selectedMonth.year == now.year && _selectedMonth.month == now.month;
  }

  Map<AttendanceStatus, int> get monthSummary {
    final map = <AttendanceStatus, int>{};
    for (final r in _month) {
      map[r.status] = (map[r.status] ?? 0) + 1;
    }
    return map;
  }

  Duration get monthWorked =>
      _month.fold(Duration.zero, (sum, r) => sum + r.workedDuration);

  Future<void> load(String employeeId) async {
    _employeeId = employeeId;
    _loading = true;
    notifyListeners();
    try {
      _today = await _repo.getToday(employeeId);
      _month = await _repo.getMonth(employeeId, _selectedMonth.year, _selectedMonth.month);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> changeMonth(int delta) async {
    final next = DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    final now = DateTime.now();
    if (next.isAfter(DateTime(now.year, now.month))) return;
    _selectedMonth = next;
    final id = _employeeId;
    if (id != null) await load(id);
  }

  /// Punches in, or out if already punched in. Returns an error message or null.
  Future<String?> punch() async {
    final id = _employeeId;
    if (id == null) return 'Not logged in';
    _punching = true;
    notifyListeners();
    try {
      // --- Location / geo-fence hook -------------------------------------
      final location = await _verification.getCurrentLocation();
      if (!_verification.isInsideOffice(location)) {
        return 'You are outside the office area. Punch not allowed.';
      }
      if (_today == null || !_today!.hasPunchedIn) {
        // --- Selfie hook ---------------------------------------------------
        final selfie = await _verification.captureSelfie();
        _today = await _repo.punchIn(id, location: location, selfieUrl: selfie);
      } else if (!_today!.hasPunchedOut) {
        _today = await _repo.punchOut(id, location: location);
      } else {
        return 'You have already completed today\'s attendance';
      }
      if (isCurrentMonth) {
        _month = await _repo.getMonth(id, _selectedMonth.year, _selectedMonth.month);
      }
      return null;
    } on AppException catch (e) {
      return e.message;
    } finally {
      _punching = false;
      notifyListeners();
    }
  }

  void clear() {
    _employeeId = null;
    _today = null;
    _month = [];
    _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  }
}
