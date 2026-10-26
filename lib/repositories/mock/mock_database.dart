import 'dart:math';

import '../../core/formatters.dart';
import '../../models/models.dart';

/// Demo login credentials (mock only - never ship real passwords in code).
const demoCredentials = {
  'ADM001': 'admin123',
  'EMP001': 'emp123',
};

/// In-memory "database" shared by all mock repositories.
/// Data resets every time the app restarts.
class MockDatabase {
  MockDatabase._();

  final List<Employee> employees = [];
  final Map<String, String> passwords = {};

  /// key: "EMP001|2026-10-26"
  final Map<String, AttendanceRecord> attendance = {};
  final List<LeaveRequest> leaves = [];
  final List<Holiday> holidays = [];
  final List<Announcement> announcements = [];
  String? currentUserId;

  static const leaveQuota = {
    LeaveType.casual: 12.0,
    LeaveType.sick: 8.0,
    LeaveType.earned: 15.0,
  };

  /// Simulated network latency.
  static Future<void> latency([int ms = 250]) => Future<void>.delayed(Duration(milliseconds: ms));

  static String key(String employeeId, DateTime day) => '$employeeId|${dateKey(day)}';

  Employee? employee(String id) {
    for (final e in employees) {
      if (e.id == id) return e;
    }
    return null;
  }

  Holiday? holidayOn(DateTime day) {
    for (final h in holidays) {
      if (isSameDay(h.date, day)) return h;
    }
    return null;
  }

  LeaveRequest? approvedLeaveOn(String employeeId, DateTime day) {
    for (final l in leaves) {
      if (l.employeeId == employeeId && l.status == LeaveStatus.approved && l.covers(day)) return l;
    }
    return null;
  }

  /// Works out the attendance status of one employee on one day.
  AttendanceRecord resolve(String employeeId, DateTime day) {
    final d = dateOnly(day);
    final stored = attendance[key(employeeId, d)];
    if (stored != null) return stored;
    final today = dateOnly(DateTime.now());
    AttendanceStatus status;
    String? note;
    final holiday = holidayOn(d);
    if (holiday != null) {
      status = AttendanceStatus.holiday;
      note = holiday.name;
    } else if (d.weekday == DateTime.sunday) {
      status = AttendanceStatus.weekend;
    } else if (approvedLeaveOn(employeeId, d) != null) {
      status = AttendanceStatus.leave;
      note = approvedLeaveOn(employeeId, d)!.type.label;
    } else if (d.isBefore(today)) {
      status = AttendanceStatus.absent;
    } else {
      status = AttendanceStatus.notMarked;
    }
    return AttendanceRecord(employeeId: employeeId, date: d, status: status, note: note);
  }

  factory MockDatabase.seeded() {
    final db = MockDatabase._();
    final now = DateTime.now();
    final year = now.year;

    db.employees.addAll([
      Employee(
        id: 'ADM001',
        name: 'Harpreet Kaur',
        email: 'harpreet.kaur@company.com',
        phone: '+91 98140 00001',
        department: 'Human Resources',
        designation: 'HR Manager',
        joiningDate: DateTime(2019, 4, 1),
        monthlyCtc: 65000,
        role: UserRole.admin,
        address: 'Mohali, Punjab',
        bloodGroup: 'B+',
      ),
      Employee(
        id: 'EMP001',
        name: 'Manjot Singh',
        email: 'manjot.singh@company.com',
        phone: '+91 95010 00002',
        department: 'Operations',
        designation: 'Operations Executive',
        joiningDate: DateTime(2024, 6, 3),
        monthlyCtc: 22000,
        managerName: 'Harpreet Kaur',
        address: 'Tarn Taran, Punjab',
        bloodGroup: 'O+',
      ),
      Employee(
        id: 'EMP002',
        name: 'Gurpreet Singh',
        email: 'gurpreet.singh@company.com',
        phone: '+91 98880 00003',
        department: 'Accounts',
        designation: 'Accountant',
        joiningDate: DateTime(2021, 8, 16),
        monthlyCtc: 35000,
        managerName: 'Harpreet Kaur',
        address: 'Amritsar, Punjab',
      ),
      Employee(
        id: 'EMP003',
        name: 'Simran Kaur',
        email: 'simran.kaur@company.com',
        phone: '+91 97790 00004',
        department: 'Sales',
        designation: 'Sales Executive',
        joiningDate: DateTime(2023, 1, 9),
        monthlyCtc: 28000,
        managerName: 'Harpreet Kaur',
        address: 'Jalandhar, Punjab',
      ),
      Employee(
        id: 'EMP004',
        name: 'Rajesh Kumar',
        email: 'rajesh.kumar@company.com',
        phone: '+91 98720 00005',
        department: 'IT',
        designation: 'Software Developer',
        joiningDate: DateTime(2022, 11, 1),
        monthlyCtc: 55000,
        managerName: 'Harpreet Kaur',
        address: 'Chandigarh',
      ),
      Employee(
        id: 'EMP005',
        name: 'Amandeep Kaur',
        email: 'amandeep.kaur@company.com',
        phone: '+91 99150 00006',
        department: 'Customer Support',
        designation: 'Support Executive',
        joiningDate: DateTime(2025, 2, 17),
        monthlyCtc: 20000,
        managerName: 'Harpreet Kaur',
        address: 'Ludhiana, Punjab',
      ),
    ]);
    for (final e in db.employees) {
      db.passwords[e.id] = demoCredentials[e.id] ?? 'emp123';
    }

    // Sample holiday list - edit to match your company's official list.
    db.holidays.addAll([
      Holiday(name: 'New Year', date: DateTime(year, 1, 1), type: HolidayType.optional),
      Holiday(name: 'Lohri', date: DateTime(year, 1, 13)),
      Holiday(name: 'Republic Day', date: DateTime(year, 1, 26), type: HolidayType.national),
      Holiday(name: 'Holi', date: DateTime(year, 3, 4)),
      Holiday(name: 'Baisakhi', date: DateTime(year, 4, 14)),
      Holiday(name: 'Independence Day', date: DateTime(year, 8, 15), type: HolidayType.national),
      Holiday(name: 'Gandhi Jayanti', date: DateTime(year, 10, 2), type: HolidayType.national),
      Holiday(name: 'Dussehra', date: DateTime(year, 10, 20)),
      Holiday(name: 'Diwali', date: DateTime(year, 11, 8)),
      Holiday(name: 'Guru Nanak Jayanti', date: DateTime(year, 11, 24)),
      Holiday(name: 'Christmas', date: DateTime(year, 12, 25), type: HolidayType.optional),
    ]);

    db.announcements.addAll([
      Announcement(
        id: 'A1',
        title: 'Welcome to iHRMS',
        body: 'Mark your attendance, apply for leave and download payslips - all from this app.',
        date: now.subtract(const Duration(days: 1)),
        author: 'HR Team',
        pinned: true,
      ),
      Announcement(
        id: 'A2',
        title: 'Diwali celebration',
        body: 'Join us for the Diwali celebration in the main hall on the last working day before Diwali at 4 PM. Sweets and gifts for everyone!',
        date: now.subtract(const Duration(days: 3)),
        author: 'Harpreet Kaur',
      ),
      Announcement(
        id: 'A3',
        title: 'Salary credited',
        body: 'Salary for last month has been credited. Payslips are available in the Payslip section.',
        date: now.subtract(const Duration(days: 10)),
        author: 'Accounts',
      ),
    ]);

    DateTime d(int daysAgo) => dateOnly(now.subtract(Duration(days: daysAgo)));
    db.leaves.addAll([
      LeaveRequest(
        id: 'L1',
        employeeId: 'EMP001',
        employeeName: 'Manjot Singh',
        type: LeaveType.casual,
        fromDate: d(24),
        toDate: d(23),
        reason: 'Family function',
        appliedOn: d(30),
        status: LeaveStatus.approved,
        approverComment: 'Approved',
      ),
      LeaveRequest(
        id: 'L2',
        employeeId: 'EMP001',
        employeeName: 'Manjot Singh',
        type: LeaveType.sick,
        fromDate: d(-3),
        toDate: d(-3),
        reason: 'Doctor appointment',
        appliedOn: d(1),
      ),
      LeaveRequest(
        id: 'L3',
        employeeId: 'EMP003',
        employeeName: 'Simran Kaur',
        type: LeaveType.earned,
        fromDate: d(-10),
        toDate: d(-7),
        reason: 'Travelling to native place',
        appliedOn: d(2),
      ),
      LeaveRequest(
        id: 'L4',
        employeeId: 'EMP002',
        employeeName: 'Gurpreet Singh',
        type: LeaveType.casual,
        fromDate: d(12),
        toDate: d(12),
        reason: 'Personal work',
        appliedOn: d(14),
        status: LeaveStatus.rejected,
        approverComment: 'Month-end closing, please plan another day',
      ),
      LeaveRequest(
        id: 'L5',
        employeeId: 'EMP004',
        employeeName: 'Rajesh Kumar',
        type: LeaveType.sick,
        fromDate: d(0),
        toDate: d(0),
        reason: 'Fever',
        appliedOn: d(0),
        status: LeaveStatus.approved,
      ),
    ]);
    // Past attendance: from the 1st of the month two months ago until yesterday.
    final rnd = Random(42);
    final start = DateTime(now.year, now.month - 2, 1);
    final today = dateOnly(now);
    for (final e in db.employees) {
      var day = start;
      while (day.isBefore(today)) {
        final isOff = day.weekday == DateTime.sunday || db.holidayOn(day) != null;
        final onLeave = db.approvedLeaveOn(e.id, day) != null;
        if (!isOff && !onLeave && rnd.nextInt(100) >= 6) {
          final inTime = DateTime(day.year, day.month, day.day, 9, rnd.nextInt(45));
          final outTime = DateTime(day.year, day.month, day.day, 18, rnd.nextInt(50));
          db.attendance[key(e.id, day)] = AttendanceRecord(
            employeeId: e.id,
            date: day,
            status: AttendanceStatus.present,
            punchIn: inTime,
            punchOut: outTime,
          );
        }
        day = DateTime(day.year, day.month, day.day + 1);
      }
    }
    // A couple of colleagues have already punched in today (for the admin report).
    for (final id in ['ADM001', 'EMP002', 'EMP003']) {
      if (today.weekday == DateTime.sunday || db.holidayOn(today) != null) break;
      final t = DateTime(today.year, today.month, today.day, 9, 5 + rnd.nextInt(30));
      if (t.isBefore(now)) {
        db.attendance[key(id, today)] = AttendanceRecord(
          employeeId: id,
          date: today,
          status: AttendanceStatus.present,
          punchIn: t,
        );
      }
    }
    return db;
  }
}
