import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<Map<String, dynamic>> _records = const [];
  List<Map<String, dynamic>> _locations = const [];
  List<Map<String, dynamic>> _overtimeRequests = const [];
  List<Map<String, dynamic>> _manualPunchRequests = const [];
  List<Map<String, dynamic>> _leaveRequests = const [];
  List<Map<String, dynamic>> _holidays = const [];
  List<String> _weeklyOffDays = const [];
  String? _employmentStartDate;
  Map<String, dynamic>? _active;
  DateTime _month = DateUtils.dateOnly(DateTime.now());
  DateTime _selectedDay = DateUtils.dateOnly(DateTime.now());
  bool _loading = true;
  bool _punching = false;
  bool _savingRequest = false;
  String _requestType = 'overtime';
  String _requestStatus = 'all';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<dynamic> _optionalGet(String path, {Map<String, String>? query}) async {
    try {
      return await AppScope.of(context).api.get(path, query: query);
    } on ApiException {
      return const <String, dynamic>{};
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = AppScope.of(context).user!;
      final api = AppScope.of(context).api;
      final canReadAttendance = user.canAny(const [
        'attendance.read', 'attendance.read.team', 'attendance.read.self', 'attendance.manage', 'attendance.punch',
      ]);
      final canReadRequests = user.canAny(const [
        'attendance.request', 'attendance.approve', 'attendance.manage',
        'attendance.read', 'attendance.read.team', 'attendance.read.self', 'attendance.punch',
      ]);
      final canReadLeave = user.canAny(const [
        'leave.read', 'leave.read.self', 'leave.read.team', 'leave.create', 'leave.approve', 'leave.manage',
      ]);
      final canReadEmployees = user.canAny(const ['employees.read', 'employees.read.team', 'employees.read.self']);
      final responses = await Future.wait<dynamic>([
        canReadAttendance
            ? api.get('attendance', query: const {'limit': '200'})
            : Future<dynamic>.value(const <String, dynamic>{}),
        user.can('locations.read') ? _optionalGet('locations') : Future<dynamic>.value(const <String, dynamic>{}),
        canReadRequests ? _optionalGet('attendance/overtime-requests') : Future<dynamic>.value(const <String, dynamic>{}),
        canReadRequests ? _optionalGet('attendance/manual-punch-requests') : Future<dynamic>.value(const <String, dynamic>{}),
        canReadLeave ? _optionalGet('leave-requests') : Future<dynamic>.value(const <String, dynamic>{}),
        user.can('calendar.read') ? _optionalGet('holidays') : Future<dynamic>.value(const <String, dynamic>{}),
        canReadEmployees ? _optionalGet('employees') : Future<dynamic>.value(const <String, dynamic>{}),
      ]);
      if (!mounted) return;
      final attendance = asJsonMap(responses[0]);
      final employees = asJsonList(asJsonMap(responses[6])['items']);
      final ownEmployee = employees.where(
        (employee) => int.tryParse(stringValue(employee['id'])) == user.employeeId,
      ).toList();
      final selfAttendance = user.employeeId != null && user.canAny(const ['attendance.read.self', 'attendance.punch']);
      final scheduleEmployees = selfAttendance ? ownEmployee : employees;
      final weeklyOffDays = <String>{
        for (final employee in scheduleEmployees) ...asStringList(employee['weekly_off_days']),
      }.toList();
      setState(() {
        _records = asJsonList(attendance['items']);
        _active = attendance['active'] == null ? null : asJsonMap(attendance['active']);
        _locations = asJsonList(asJsonMap(responses[1])['items']);
        _overtimeRequests = asJsonList(asJsonMap(responses[2])['items']);
        _manualPunchRequests = asJsonList(asJsonMap(responses[3])['items']);
        _leaveRequests = asJsonList(asJsonMap(responses[4])['items']);
        _holidays = asJsonList(asJsonMap(responses[5])['items']);
        _weeklyOffDays = weeklyOffDays;
        _employmentStartDate = selfAttendance && ownEmployee.isNotEmpty ? stringValue(ownEmployee.first['start_date']) : null;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Position> _currentPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) throw const ApiException('Turn on location services before punching in or out.');

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw const ApiException('Location permission is required for GPS-verified attendance.');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 25),
      ),
    );
  }

  Future<void> _punch() async {
    setState(() {
      _punching = true;
      _error = null;
    });
    try {
      final api = AppScope.of(context).api;
      final wasCheckedIn = _active != null;
      final position = await _currentPosition();
      final action = wasCheckedIn ? 'punch-out' : 'punch-in';
      await api.post('attendance/$action', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy_m': position.accuracy,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(wasCheckedIn ? 'You are punched out.' : 'You are punched in.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Unable to read your location. ${error.toString()}');
    } finally {
      if (mounted) setState(() => _punching = false);
    }
  }

  Future<void> _newOvertimeRequest() async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _OvertimeRequestDialog(),
    );
    if (values == null || !mounted) return;
    await _submitAttendanceRequest('attendance/overtime-requests', values, 'Overtime request submitted.');
  }

  Future<void> _newManualPunchRequest() async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _ManualPunchRequestDialog(),
    );
    if (values == null || !mounted) return;
    await _submitAttendanceRequest('attendance/manual-punch-requests', values, 'Manual-punch request submitted for review.');
  }

  Future<void> _submitAttendanceRequest(String path, Map<String, dynamic> values, String successMessage) async {
    try {
      setState(() => _savingRequest = true);
      await AppScope.of(context).api.post(path, values);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _savingRequest = false);
    }
  }

  Future<void> _decideAttendanceRequest(String kind, Map<String, dynamic> request, String decision) async {
    final endpoint = kind == 'overtime' ? 'overtime-requests' : 'manual-punch-requests';
    try {
      setState(() => _savingRequest = true);
      await AppScope.of(context).api.post(
        'attendance/$endpoint/${request['id']}/decision',
        {'decision': decision},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Attendance request $decision.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _savingRequest = false);
    }
  }

  void _changeMonth(int offset) {
    setState(() {
      _month = DateTime(_month.year, _month.month + offset, 1);
      _selectedDay = DateTime(_month.year, _month.month, 1);
    });
  }

  Map<String, String> _attendanceByDay() {
    final user = AppScope.of(context).user!;
    final selfAttendance = user.employeeId != null && user.canAny(const ['attendance.read.self', 'attendance.punch']);
    final records = _records.where((record) {
      if (!selfAttendance) return true;
      final employeeId = int.tryParse(stringValue(record['employee_id']));
      return employeeId == user.employeeId;
    });
    final byDay = <String, String>{};
    for (final record in records) {
      final rawDate = DateTime.tryParse(stringValue(record['punch_in_at']));
      if (rawDate == null) continue;
      final day = rawDate.toLocal();
      if (day.year == _month.year && day.month == _month.month) byDay[_dateString(day)] = 'present';
    }

    final approvedLeaves = _leaveRequests.where((request) {
      final employeeId = int.tryParse(stringValue(request['employee_id']));
      return stringValue(request['status']) == 'approved' &&
          (!selfAttendance || employeeId == user.employeeId);
    }).toList();
    final holidaysByDate = <String>{for (final holiday in _holidays) stringValue(holiday['holiday_date'])};
    final weeklyDays = _weeklyOffDays.map((day) => day.toLowerCase()).toSet();
    final today = DateUtils.dateOnly(DateTime.now());
    final employmentStart = DateTime.tryParse(stringValue(_employmentStartDate));
    final firstWorkDate = employmentStart == null ? null : DateUtils.dateOnly(employmentStart);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    for (var dayNumber = 1; dayNumber <= daysInMonth; dayNumber++) {
      final day = DateTime(_month.year, _month.month, dayNumber);
      if (firstWorkDate != null && day.isBefore(firstWorkDate)) continue;
      final key = _dateString(day);
      if (byDay.containsKey(key)) continue;
      final onLeave = approvedLeaves.any((request) =>
          stringValue(request['start_date']).compareTo(key) <= 0 &&
          stringValue(request['end_date']).compareTo(key) >= 0);
      if (onLeave) {
        byDay[key] = 'leave';
      } else if (holidaysByDate.contains(key)) {
        byDay[key] = 'holiday';
      } else if (weeklyDays.contains(_weekdayName(day.weekday).toLowerCase())) {
        byDay[key] = 'off';
      } else if (!day.isAfter(today)) {
        byDay[key] = 'missing';
      }
    }
    return byDay;
  }

  List<Map<String, dynamic>> _visibleMonthRecords() {
    return _records.where((record) {
      final rawDate = DateTime.tryParse(stringValue(record['punch_in_at']));
      return rawDate != null && rawDate.toLocal().year == _month.year && rawDate.toLocal().month == _month.month;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user!;
    final canPunch = user.can('attendance.punch');
    final canReadAttendance = user.canAny(const ['attendance.read', 'attendance.read.team', 'attendance.read.self', 'attendance.manage', 'attendance.punch']);
    final canRequest = user.can('attendance.request');
    final canReview = user.canAny(const ['attendance.approve', 'attendance.manage']);
    final showEmployee = user.canAny(const ['attendance.read', 'attendance.read.team', 'attendance.manage']);
    final dayStatuses = _attendanceByDay();
    final visibleMonthRecords = _visibleMonthRecords();
    final ownRecords = user.employeeId == null
        ? const <Map<String, dynamic>>[]
        : _records.where((record) => int.tryParse(stringValue(record['employee_id'])) == user.employeeId).toList();
    final canViewSelf = user.employeeId != null && user.canAny(const ['attendance.read.self', 'attendance.punch']);
    final allRequests = _requestType == 'overtime' ? _overtimeRequests : _manualPunchRequests;
    final visibleRequests = allRequests.where((request) =>
      _requestStatus == 'all' || stringValue(request['status']) == _requestStatus).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1250),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeading(
                  title: 'Attendance',
                  subtitle: 'Verified punches, monthly attendance and correction requests.',
                  trailing: IconButton.filledTonal(onPressed: _load, tooltip: 'Refresh attendance', icon: const Icon(Icons.refresh_rounded)),
                ),
                if (_error != null) ...[
                  ErrorNotice(message: _error!, onRetry: _load),
                  const SizedBox(height: 14),
                ],
                LayoutBuilder(builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 850;
                  final punchCard = _PunchCard(
                    active: _active,
                    busy: _punching,
                    canPunch: canPunch,
                    locationCount: _locations.where((location) => location['is_active'] == true || location['is_active'] == 1).length,
                    onPunch: _punch,
                  );
                  final todayCard = canReadAttendance
                      ? _TodaySummary(
                          records: canViewSelf ? ownRecords : _records,
                          active: _active,
                          canViewSelf: canViewSelf,
                        )
                      : const AppPanel(
                          child: EmptyNotice(
                            title: 'Attendance history is restricted',
                            subtitle: 'Your role can submit attendance requests but cannot view punch history.',
                            icon: Icons.lock_outline_rounded,
                          ),
                        );
                  if (!wide) return Column(children: [punchCard, const SizedBox(height: 15), todayCard]);
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 6, child: punchCard),
                    const SizedBox(width: 15),
                    Expanded(flex: 4, child: todayCard),
                  ]);
                }),
                const SizedBox(height: 23),
                if (canReadAttendance)
                  _MonthAttendanceCalendar(
                    month: _month,
                    selectedDay: _selectedDay,
                    statuses: dayStatuses,
                    onMonthChanged: _changeMonth,
                    onDaySelected: (day) => setState(() => _selectedDay = day),
                  )
                else
                  const AppPanel(
                    child: EmptyNotice(
                      title: 'Monthly calendar unavailable',
                      subtitle: 'Your role does not include access to attendance history.',
                      icon: Icons.lock_outline_rounded,
                    ),
                  ),
                const SizedBox(height: 23),
                PageHeading(
                  title: 'Punch logs',
                  subtitle: 'Recorded work sessions for this month.',
                  trailing: Text('${visibleMonthRecords.length} records', style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                if (!canReadAttendance)
                  const AppPanel(child: EmptyNotice(title: 'Punch logs are restricted', subtitle: 'Your role cannot view attendance history.', icon: Icons.lock_outline_rounded))
                else if (_loading && _records.isEmpty)
                  const AppPanel(child: SizedBox(height: 130, child: LoadingView(label: 'Loading attendance logs…')))
                else if (visibleMonthRecords.isEmpty)
                  const AppPanel(child: EmptyNotice(title: 'No attendance this month', subtitle: 'Verified GPS punches and approved manual entries will appear here.', icon: Icons.schedule_rounded))
                else
                  AppPanel(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(children: [
                      for (var index = 0; index < visibleMonthRecords.length; index++) ...[
                        _AttendanceRow(record: visibleMonthRecords[index], showEmployee: showEmployee),
                        if (index < visibleMonthRecords.length - 1) const Divider(height: 1),
                      ],
                    ]),
                  ),
                const SizedBox(height: 24),
                PageHeading(
                  title: canReview ? 'Attendance requests & reviews' : 'My attendance requests',
                  subtitle: canReview ? 'Review overtime and manual-punch submissions from your authorized team.' : 'Request overtime or submit a missing-punch correction for approval.',
                ),
                if (canRequest) ...[
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(onPressed: _savingRequest ? null : _newOvertimeRequest, icon: const Icon(Icons.more_time_rounded, size: 17), label: const Text('Request OT')),
                    OutlinedButton.icon(onPressed: _savingRequest ? null : _newManualPunchRequest, icon: const Icon(Icons.edit_calendar_outlined, size: 17), label: const Text('Manual punch')),
                  ]),
                  const SizedBox(height: 11),
                ],
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'overtime', label: Text('Overtime'), icon: Icon(Icons.more_time_rounded)),
                    ButtonSegment(value: 'manual', label: Text('Manual punches'), icon: Icon(Icons.edit_calendar_outlined)),
                  ],
                  selected: {_requestType},
                  onSelectionChanged: (selection) => setState(() => _requestType = selection.first),
                  showSelectedIcon: false,
                ),
                const SizedBox(height: 10),
                _AttendanceRequestFilters(selected: _requestStatus, onSelected: (status) => setState(() => _requestStatus = status)),
                const SizedBox(height: 11),
                if (visibleRequests.isEmpty)
                  AppPanel(
                    child: EmptyNotice(
                      title: _requestStatus == 'all' ? 'No ${_requestType == 'overtime' ? 'overtime' : 'manual-punch'} requests' : 'No $_requestStatus requests',
                      subtitle: canRequest ? 'Requests and approval status will show here after submission.' : 'There are no requests in this review queue.',
                      icon: _requestType == 'overtime' ? Icons.more_time_rounded : Icons.edit_calendar_outlined,
                    ),
                  )
                else
                  Column(children: [
                    for (final request in visibleRequests)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _AttendanceRequestCard(
                          request: request,
                          kind: _requestType,
                          showEmployee: showEmployee,
                          canReview: canReview && stringValue(request['status']) == 'pending',
                          busy: _savingRequest,
                          onApprove: () => _decideAttendanceRequest(_requestType, request, 'approved'),
                          onReject: () => _decideAttendanceRequest(_requestType, request, 'rejected'),
                        ),
                      ),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

class _MonthAttendanceCalendar extends StatelessWidget {
  const _MonthAttendanceCalendar({
    required this.month,
    required this.selectedDay,
    required this.statuses,
    required this.onMonthChanged,
    required this.onDaySelected,
  });

  final DateTime month;
  final DateTime selectedDay;
  final Map<String, String> statuses;
  final ValueChanged<int> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingDays = DateTime(month.year, month.month, 1).weekday - 1;
    final cellCount = ((leadingDays + daysInMonth + 6) ~/ 7) * 7;
    final statusCounts = <String, int>{
      for (final status in const ['present', 'leave', 'holiday', 'off', 'missing'])
        status: statuses.values.where((value) => value == status).length,
    };
    return AppPanel(
      padding: const EdgeInsets.all(17),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Monthly attendance', style: TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w800)),
            SizedBox(height: 4),
            Text('Tap a date to review the month at a glance.', style: TextStyle(color: AppColors.muted, fontSize: 10)),
          ])),
          IconButton(onPressed: () => onMonthChanged(-1), tooltip: 'Previous month', icon: const Icon(Icons.chevron_left_rounded)),
          Text(_monthLabel(month), style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w800)),
          IconButton(onPressed: () => onMonthChanged(1), tooltip: 'Next month', icon: const Icon(Icons.chevron_right_rounded)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          for (final day in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
            Expanded(child: Center(child: Text(day, style: const TextStyle(color: AppColors.muted, fontSize: 9, fontWeight: FontWeight.w800)))),
        ]),
        const SizedBox(height: 7),
        GridView.builder(
          itemCount: cellCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            crossAxisSpacing: 5,
            mainAxisSpacing: 5,
            childAspectRatio: 1.08,
          ),
          itemBuilder: (context, index) {
            final dayNumber = index - leadingDays + 1;
            if (dayNumber < 1 || dayNumber > daysInMonth) return const SizedBox.shrink();
            final day = DateTime(month.year, month.month, dayNumber);
            final key = _dateString(day);
            final status = statuses[key];
            final selected = DateUtils.isSameDay(day, selectedDay);
            return _CalendarDayCell(
              day: day,
              status: status,
              selected: selected,
              onTap: () => onDaySelected(day),
            );
          },
        ),
        const SizedBox(height: 13),
        const Wrap(spacing: 12, runSpacing: 8, children: [
          _CalendarLegend(color: AppColors.success, label: 'Present'),
          _CalendarLegend(color: AppColors.blue, label: 'Leave'),
          _CalendarLegend(color: Color(0xFFAE751C), label: 'Holiday'),
          _CalendarLegend(color: AppColors.muted, label: 'Weekly off'),
          _CalendarLegend(color: Color(0xFFC94D54), label: 'No punch'),
        ]),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, constraints) {
          final items = <(String, String, Color)>[
            ('Present', '${statusCounts['present']}', AppColors.success),
            ('Leave', '${statusCounts['leave']}', AppColors.blue),
            ('Holidays', '${statusCounts['holiday']}', const Color(0xFFAE751C)),
            ('Weekly off', '${statusCounts['off']}', AppColors.muted),
            ('No punch', '${statusCounts['missing']}', const Color(0xFFC94D54)),
          ];
          final width = (constraints.maxWidth - 16) / 3;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final item in items)
              SizedBox(
                width: constraints.maxWidth > 800 ? (constraints.maxWidth - 32) / 5 : width,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(color: item.$3.withValues(alpha: .07), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Text(item.$2, style: TextStyle(color: item.$3, fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 7),
                    Expanded(child: Text(item.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 9, fontWeight: FontWeight.w600))),
                  ]),
                ),
              ),
          ]);
        }),
      ]),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({required this.day, required this.status, required this.selected, required this.onTap});
  final DateTime day;
  final String? status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _calendarStatusColor(status);
    final background = switch (status) {
      'present' => AppColors.softGreen,
      'leave' => AppColors.softBlue,
      'holiday' => AppColors.softAmber,
      'off' => const Color(0xFFF0F3F7),
      'missing' => AppColors.softRed,
      _ => Colors.white,
    };
    return Tooltip(
      message: status == null ? _dateString(day) : '${_dateString(day)} · ${_calendarStatusLabel(status!)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          decoration: BoxDecoration(
            color: selected ? AppColors.softBlue : background,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: selected ? AppColors.blue : AppColors.line),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${day.day}', style: TextStyle(color: selected ? AppColors.blue : AppColors.ink, fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
            const SizedBox(height: 4),
            Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          ]),
        ),
      ),
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 5), Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 9, fontWeight: FontWeight.w600))]);
}

class _AttendanceRequestFilters extends StatelessWidget {
  const _AttendanceRequestFilters({required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final status in const ['all', 'pending', 'approved', 'rejected']) ...[
            ChoiceChip(
              label: Text(status == 'all' ? 'All' : _titleCase(status)),
              selected: selected == status,
              onSelected: (_) => onSelected(status),
              selectedColor: AppColors.softBlue,
              labelStyle: TextStyle(color: selected == status ? AppColors.blue : AppColors.ink, fontSize: 10, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 7),
          ],
        ]),
      );
}

class _AttendanceRequestCard extends StatelessWidget {
  const _AttendanceRequestCard({
    required this.request,
    required this.kind,
    required this.showEmployee,
    required this.canReview,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });
  final Map<String, dynamic> request;
  final String kind;
  final bool showEmployee;
  final bool canReview;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final overtime = kind == 'overtime';
    final details = overtime
        ? '${formatDate(request['work_date'])} · ${_numberText(request['hours'])} hours'
        : '${formatDate(request['work_date'])} · ${formatDateTime(request['requested_punch_in'])} – ${request['requested_punch_out'] == null ? 'No punch-out' : formatDateTime(request['requested_punch_out'])}';
    return AppPanel(
      padding: const EdgeInsets.all(15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(12)), child: Icon(overtime ? Icons.more_time_rounded : Icons.edit_calendar_outlined, color: AppColors.blue, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(overtime ? 'Overtime request' : 'Manual-punch submission', style: const TextStyle(color: AppColors.ink, fontSize: 11, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(showEmployee ? '${stringValue(request['employee_name'], fallback: 'Employee')} · ${stringValue(request['employee_code'])}' : details, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 9)),
          ])),
          StatusBadge(status: stringValue(request['status'], fallback: 'pending')),
        ]),
        const SizedBox(height: 10),
        Text(showEmployee ? details : stringValue(request['reason']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.ink, fontSize: 10, height: 1.4)),
        if (showEmployee && stringValue(request['reason']).isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(stringValue(request['reason']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 9, height: 1.4)),
        ],
        if (canReview) ...[
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: busy ? null : onReject, child: const Text('Reject')),
            const SizedBox(width: 5),
            FilledButton.icon(onPressed: busy ? null : onApprove, icon: const Icon(Icons.check_rounded, size: 15), label: const Text('Approve')),
          ]),
        ],
      ]),
    );
  }
}

class _OvertimeRequestDialog extends StatefulWidget {
  const _OvertimeRequestDialog();
  @override
  State<_OvertimeRequestDialog> createState() => _OvertimeRequestDialogState();
}

class _OvertimeRequestDialogState extends State<_OvertimeRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  final _hours = TextEditingController();
  final _reason = TextEditingController();
  DateTime _workDate = DateUtils.dateOnly(DateTime.now());

  @override
  void dispose() {
    _hours.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _workDate,
      firstDate: DateTime(today.year - 2),
      lastDate: DateTime(today.year + 1),
    );
    if (picked != null) setState(() => _workDate = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, <String, dynamic>{
      'work_date': _dateString(_workDate),
      'hours': double.parse(_hours.text.trim()),
      'reason': _reason.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Request overtime', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 410,
          child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
            _AttendanceDateField(label: 'Work date', value: _workDate, onTap: _pickDate),
            const SizedBox(height: 12),
            TextFormField(
              controller: _hours,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Overtime hours', hintText: 'For example: 1.5'),
              validator: (value) {
                final hours = double.tryParse(value?.trim() ?? '');
                if (hours == null || hours <= 0 || hours > 24) return 'Enter a value from 0.1 to 24 hours';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _reason, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Reason'), validator: (value) => (value?.trim().isEmpty ?? true) ? 'Reason is required' : null),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton.icon(onPressed: _submit, icon: const Icon(Icons.send_rounded, size: 16), label: const Text('Submit request')),
        ],
      );
}

class _ManualPunchRequestDialog extends StatefulWidget {
  const _ManualPunchRequestDialog();
  @override
  State<_ManualPunchRequestDialog> createState() => _ManualPunchRequestDialogState();
}

class _ManualPunchRequestDialogState extends State<_ManualPunchRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late DateTime _workDate;
  late DateTime _punchIn;
  late DateTime _punchOut;
  bool _includePunchOut = true;
  bool _invalidTimes = false;

  @override
  void initState() {
    super.initState();
    _workDate = DateUtils.dateOnly(DateTime.now().subtract(const Duration(days: 1)));
    _punchIn = DateTime(_workDate.year, _workDate.month, _workDate.day, 9);
    _punchOut = DateTime(_workDate.year, _workDate.month, _workDate.day, 17);
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _workDate,
      firstDate: DateTime(today.year - 3),
      lastDate: today,
    );
    if (picked == null) return;
    setState(() {
      _workDate = picked;
      _punchIn = DateTime(picked.year, picked.month, picked.day, _punchIn.hour, _punchIn.minute);
      _punchOut = DateTime(picked.year, picked.month, picked.day, _punchOut.hour, _punchOut.minute);
      _invalidTimes = false;
    });
  }

  Future<void> _pickTime({required bool punchIn}) async {
    final current = punchIn ? _punchIn : _punchOut;
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (picked == null) return;
    setState(() {
      final updated = DateTime(_workDate.year, _workDate.month, _workDate.day, picked.hour, picked.minute);
      if (punchIn) {
        _punchIn = updated;
      } else {
        _punchOut = updated;
      }
      _invalidTimes = false;
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_includePunchOut && !_punchOut.isAfter(_punchIn)) {
      setState(() => _invalidTimes = true);
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'work_date': _dateString(_workDate),
      'punch_in': _isoWithOffset(_punchIn),
      'punch_out': _includePunchOut ? _isoWithOffset(_punchOut) : null,
      'reason': _reason.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Submit manual punch', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 430,
          child: Form(key: _formKey, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            _AttendanceDateField(label: 'Work date', value: _workDate, onTap: _pickDate),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _AttendanceTimeField(label: 'Punch-in', value: _punchIn, onTap: () => _pickTime(punchIn: true))),
              const SizedBox(width: 10),
              Expanded(child: _AttendanceTimeField(label: 'Punch-out', value: _punchOut, onTap: () => _pickTime(punchIn: false))),
            ]),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _includePunchOut,
              onChanged: (value) => setState(() => _includePunchOut = value),
              title: const Text('Include punch-out time', style: TextStyle(color: AppColors.ink, fontSize: 11, fontWeight: FontWeight.w700)),
              subtitle: const Text('Turn off to correct check-in only; an existing punch-out is preserved.', style: TextStyle(color: AppColors.muted, fontSize: 9)),
            ),
            if (_invalidTimes) const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Punch-out must be later than punch-in.', style: TextStyle(color: Color(0xFFC94D54), fontSize: 10)))),
            TextFormField(controller: _reason, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Reason'), validator: (value) => (value?.trim().isEmpty ?? true) ? 'Reason is required' : null),
          ]))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton.icon(onPressed: _submit, icon: const Icon(Icons.send_rounded, size: 16), label: const Text('Submit for review')),
        ],
      );
}

class _AttendanceDateField extends StatelessWidget {
  const _AttendanceDateField({required this.label, required this.value, required this.onTap});
  final String label;
  final DateTime value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_month_outlined, size: 18)),
          child: Text(_dateString(value), style: const TextStyle(color: AppColors.ink, fontSize: 11)),
        ),
      );
}

class _AttendanceTimeField extends StatelessWidget {
  const _AttendanceTimeField({required this.label, required this.value, required this.onTap});
  final String label;
  final DateTime value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.schedule_rounded, size: 18)),
          child: Text('${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}', style: const TextStyle(color: AppColors.ink, fontSize: 11)),
        ),
      );
}

String _monthLabel(DateTime month) => '${_monthName(month.month)} ${month.year}';
String _monthName(int month) => const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][month - 1];
String _weekdayName(int weekday) => const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][weekday - 1];
String _calendarStatusLabel(String status) => switch (status) {
      'present' => 'Present',
      'leave' => 'Approved leave',
      'holiday' => 'Company holiday',
      'off' => 'Weekly off',
      'missing' => 'No punch recorded',
      _ => 'No record',
    };
Color _calendarStatusColor(String? status) => switch (status) {
      'present' => AppColors.success,
      'leave' => AppColors.blue,
      'holiday' => const Color(0xFFAE751C),
      'off' => AppColors.muted,
      'missing' => const Color(0xFFC94D54),
      _ => AppColors.line,
    };
String _numberText(Object? value) => value is num ? (value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1)) : (value?.toString() ?? '0');
String _isoWithOffset(DateTime value) {
  final offset = value.timeZoneOffset;
  final minutes = offset.inMinutes.abs();
  final sign = offset.isNegative ? '-' : '+';
  final hoursText = (minutes ~/ 60).toString().padLeft(2, '0');
  final minutesText = (minutes % 60).toString().padLeft(2, '0');
  return '${value.toIso8601String().substring(0, 19)}$sign$hoursText:$minutesText';
}
String _dateString(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String _titleCase(String value) => value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

class _PunchCard extends StatelessWidget {
  const _PunchCard({required this.active, required this.busy, required this.canPunch, required this.locationCount, required this.onPunch});

  final Map<String, dynamic>? active;
  final bool busy;
  final bool canPunch;
  final int locationCount;
  final VoidCallback onPunch;

  @override
  Widget build(BuildContext context) {
    final checkedIn = active != null;
    final location = checkedIn ? stringValue(active!['location_name'], fallback: 'Assigned work location') : 'GPS verified at punch time';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.navy, Color(0xFF123E64), Color(0xFF0B696E)]),
        boxShadow: const [BoxShadow(color: Color(0x17132A40), blurRadius: 20, offset: Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Container(width: 9, height: 9, decoration: BoxDecoration(color: checkedIn ? const Color(0xFF43D99C) : const Color(0xFFB8C6D4), shape: BoxShape.circle)), const SizedBox(width: 9), Text(checkedIn ? 'SHIFT IN PROGRESS' : 'READY FOR YOUR SHIFT', style: const TextStyle(color: Color(0xFFD3E5EE), fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.1))]),
          const SizedBox(height: 16),
          Text(checkedIn ? 'You’re checked in.' : 'Make today count.', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(checkedIn ? 'Started ${formatDateTime(active!['punch_in_at'])}' : 'Your location is checked against an active work geofence.', style: const TextStyle(color: Color(0xFFC4D5E0), fontSize: 13)),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(13), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: Color(0xFF82E2D1), size: 19),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(checkedIn ? 'CURRENT SITE' : 'ACTIVE LOCATIONS', style: const TextStyle(color: Color(0xFFAFC4D2), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                            const SizedBox(height: 4),
                            Text(checkedIn ? location : '$locationCount available', overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (canPunch)
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: busy ? null : onPunch,
                    style: FilledButton.styleFrom(backgroundColor: checkedIn ? AppColors.success : Colors.white, foregroundColor: checkedIn ? Colors.white : AppColors.navy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
                    icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue)) : Icon(checkedIn ? Icons.logout_rounded : Icons.login_rounded, size: 18),
                    label: Text(busy ? 'Checking…' : checkedIn ? 'Punch out' : 'Punch in', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                )
              else
                const Icon(Icons.verified_user_outlined, color: Color(0xFFAFC4D2), size: 24),
            ],
          ),
          if (!canPunch) ...[
            const SizedBox(height: 13),
            const Text('Your current role can view attendance but cannot punch in or out.', style: TextStyle(color: Color(0xFFC4D5E0), fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.records, required this.active, required this.canViewSelf});
  final List<Map<String, dynamic>> records;
  final Map<String, dynamic>? active;
  final bool canViewSelf;

  @override
  Widget build(BuildContext context) {
    final today = _dateString(DateUtils.dateOnly(DateTime.now()));
    final todaysRecords = records.where((record) {
      final punchIn = DateTime.tryParse(stringValue(record['punch_in_at']));
      return punchIn != null && _dateString(punchIn.toLocal()) == today;
    }).toList()
      ..sort((a, b) =>
          DateTime.parse(stringValue(a['punch_in_at'])).compareTo(DateTime.parse(stringValue(b['punch_in_at']))));
    final first = todaysRecords.isEmpty ? null : todaysRecords.first;
    final last = todaysRecords.isEmpty ? null : todaysRecords.last;
    final shiftStatus = active != null ? 'In progress' : last?['punch_out_at'] != null ? 'Completed' : 'Not punched in';
    if (!canViewSelf) {
      final inProgress = todaysRecords.where((record) => record['punch_out_at'] == null).length;
      return AppPanel(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Team today', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 4),
          const Text('Attendance in your authorized view', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 15),
          _SummaryLine(icon: Icons.login_rounded, label: 'Check-ins today', value: '${todaysRecords.length}', color: AppColors.blue),
          const SizedBox(height: 12),
          _SummaryLine(icon: Icons.timelapse_rounded, label: 'Shifts in progress', value: '$inProgress', color: AppColors.success),
          const SizedBox(height: 12),
          _SummaryLine(icon: Icons.history_rounded, label: 'Records shown', value: '${records.length}', color: AppColors.teal),
        ]),
      );
    }
    return AppPanel(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Today', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 4),
        const Text('Your attendance snapshot', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 15),
        _SummaryLine(icon: Icons.login_rounded, label: 'First check-in', value: first == null ? '—' : formatDateTime(first['punch_in_at']), color: AppColors.blue),
        const SizedBox(height: 12),
        _SummaryLine(icon: Icons.logout_rounded, label: 'Check-out', value: last == null || last['punch_out_at'] == null ? '—' : formatDateTime(last['punch_out_at']), color: AppColors.success),
        const SizedBox(height: 12),
        _SummaryLine(icon: Icons.timelapse_rounded, label: 'Shift status', value: shiftStatus, color: active != null ? AppColors.success : last != null ? AppColors.blue : AppColors.muted),
      ]),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(children: [Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: color, size: 18)), const SizedBox(width: 10), Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12))), Text(value, style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w700))]);
}

class _AttendanceRow extends StatelessWidget {
  const _AttendanceRow({required this.record, required this.showEmployee});
  final Map<String, dynamic> record;
  final bool showEmployee;

  @override
  Widget build(BuildContext context) {
    final checkedOut = record['punch_out_at'] != null;
    final duration = _shiftDuration(record['punch_in_at'], record['punch_out_at']);
    final source = stringValue(record['punch_source'], fallback: 'gps');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth > 650;
        return Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.schedule_rounded, color: AppColors.blue, size: 20)),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(showEmployee ? stringValue(record['employee_name'], fallback: 'My shift') : 'My shift', style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text('${formatDate(record['punch_in_at'])} · ${stringValue(record['location_name'], fallback: 'Work site')}${source == 'manual' ? ' · Manual' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11))])),
          if (wide) Expanded(child: Text('${formatDateTime(record['punch_in_at'])} – ${checkedOut ? formatDateTime(record['punch_out_at']) : 'Now'}', style: const TextStyle(color: AppColors.muted, fontSize: 11))),
          Text(duration, style: const TextStyle(color: AppColors.ink, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          StatusBadge(status: checkedOut ? 'complete' : 'present'),
        ]);
      }),
    );
  }
}

String _shiftDuration(Object? startValue, Object? endValue) {
  final start = DateTime.tryParse(stringValue(startValue));
  final end = DateTime.tryParse(stringValue(endValue)) ?? DateTime.now();
  if (start == null) return '—';
  final difference = end.difference(start);
  if (difference.isNegative) return '—';
  final hours = difference.inHours;
  final minutes = difference.inMinutes.remainder(60);
  return '${hours}h ${minutes}m';
}
