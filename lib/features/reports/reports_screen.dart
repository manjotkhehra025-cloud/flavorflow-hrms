import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Map<String, dynamic> _dashboard = const {};
  List<Map<String, dynamic>> _employees = const [];
  List<Map<String, dynamic>> _attendance = const [];
  List<Map<String, dynamic>> _leaveRequests = const [];
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  late DateTime _rangeStart;
  late DateTime _rangeEnd;

  @override
  void initState() {
    super.initState();
    _rangeEnd = DateTime.now();
    _rangeStart = _rangeEnd.subtract(const Duration(days: 29));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = AppScope.of(context).api;
      final responses = await Future.wait<dynamic>([
        api.get('dashboard'),
        api.get('employees'),
        api.get('attendance', query: {
          'from': _dateOnly(_rangeStart),
          'to': _dateOnly(_rangeEnd),
          'limit': '200',
        }),
        api.get('leave-requests'),
      ]);
      if (!mounted) return;
      setState(() {
        _dashboard = asJsonMap(responses[0]);
        _employees = asJsonList(asJsonMap(responses[1])['items']);
        _attendance = asJsonList(asJsonMap(responses[2])['items']);
        _leaveRequests = asJsonList(asJsonMap(responses[3])['items']);
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final rows = <List<String>>[
        ['Report', 'Attendance detail (${_dateOnly(_rangeStart)} to ${_dateOnly(_rangeEnd)})'],
        ['Employee', 'Employee ID', 'Department', 'Date', 'Punch in', 'Punch out', 'Source'],
      ];
      final departmentByEmployeeId = <String, String>{
        for (final employee in _employees)
          stringValue(employee['id']): stringValue(employee['department']),
      };
      for (final record in _attendance) {
        rows.add([
          stringValue(record['employee_name'], fallback: 'Team member'),
          stringValue(record['employee_code']),
          departmentByEmployeeId[stringValue(record['employee_id'])] ?? '',
          _datePart(record['punch_in_at']),
          _timePart(record['punch_in_at']),
          _timePart(record['punch_out_at']),
          stringValue(record['punch_source'], fallback: 'gps'),
        ]);
      }
      final csv = rows.map((row) => row.map(_csvCell).join(',')).join('\r\n');
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance CSV copied. Paste it into a spreadsheet.')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not prepare the report export.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _chooseRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _rangeStart, end: _rangeEnd),
      helpText: 'Choose report period',
    );
    if (range == null || !mounted) return;
    setState(() {
      _rangeStart = range.start;
      _rangeEnd = range.end;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final stats = asJsonMap(_dashboard['stats']);
    final pendingLeaves = _leaveRequests.where((row) => stringValue(row['status']) == 'pending').length;
    final activeEmployees = int.tryParse(stringValue(stats['active_employees'])) ??
        _employees.where((row) => stringValue(row['status']) == 'active').length;
    final departments = <String, int>{};
    for (final employee in _employees.where((row) => stringValue(row['status']) == 'active')) {
      final department = stringValue(employee['department'], fallback: 'Unassigned');
      departments.update(department, (count) => count + 1, ifAbsent: () => 1);
    }
    final orderedDepartments = departments.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeading(
                  title: 'Reports',
                  subtitle: 'Workforce, attendance, and leave snapshots for your authorized scope.',
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _chooseRange,
                        icon: const Icon(Icons.date_range_rounded, size: 17),
                        label: const Text('Period'),
                      ),
                      PrimaryButton(
                        label: _exporting ? 'Preparing…' : 'Copy CSV',
                        icon: Icons.file_download_outlined,
                        busy: _exporting,
                        onPressed: _exporting || _loading ? null : _exportCsv,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${_dateOnly(_rangeStart)}  –  ${_dateOnly(_rangeEnd)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 13),
                  ErrorNotice(message: _error!, onRetry: _load),
                ],
                const SizedBox(height: 16),
                if (_loading && _dashboard.isEmpty)
                  const SizedBox(height: 200, child: LoadingView(label: 'Preparing reports…'))
                else ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth > 800 ? 4 : constraints.maxWidth > 510 ? 2 : 1;
                      const gap = 12.0;
                      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
                      final metrics = <(String, String, String, IconData, Color)>[
                        ('Active employees', '$activeEmployees', 'Current headcount', Icons.groups_2_outlined, AppColors.blue),
                        ('Attendance records', '${_attendance.length}', 'In selected period', Icons.access_time_rounded, AppColors.teal),
                        ('Pending leave', '$pendingLeaves', 'Awaiting a decision', Icons.event_note_outlined, const Color(0xFFB77A1C)),
                        ('On leave today', stringValue(stats['on_leave_today'], fallback: '0'), 'Approved leave', Icons.beach_access_outlined, AppColors.success),
                      ];
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: metrics.map((metric) => SizedBox(
                          width: width,
                          child: _ReportMetric(title: metric.$1, value: metric.$2, subtitle: metric.$3, icon: metric.$4, color: metric.$5),
                        )).toList(growable: false),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 760;
                      final departmentPanel = AppPanel(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Employees by department', style: TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            const Text('Active profiles in your permitted scope.', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                            const SizedBox(height: 13),
                            if (orderedDepartments.isEmpty)
                              const Text('No department data available.', style: TextStyle(color: AppColors.muted, fontSize: 12))
                            else
                              ...orderedDepartments.take(8).map((entry) {
                                final fraction = activeEmployees > 0 ? entry.value / activeEmployees : 0.0;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [Expanded(child: Text(entry.key, style: const TextStyle(color: AppColors.ink, fontSize: 11, fontWeight: FontWeight.w600))), Text('${entry.value}', style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700))]),
                                      const SizedBox(height: 5),
                                      ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: fraction, minHeight: 5, backgroundColor: AppColors.canvas, color: AppColors.blue)),
                                    ],
                                  ),
                                );
                              }),
                          ],
                        ),
                      );
                      final attendancePanel = AppPanel(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [const Expanded(child: Text('Recent attendance', style: TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w800))), Text('${_attendance.length} records', style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w600))]),
                            const SizedBox(height: 4),
                            const Text('GPS and approved manual entries in the selected period.', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                            const SizedBox(height: 12),
                            if (_attendance.isEmpty)
                              const EmptyNotice(title: 'No attendance records', subtitle: 'No records matched this report period.', icon: Icons.event_busy_outlined)
                            else
                              ..._attendance.take(10).map((record) => _AttendanceReportRow(record: record)),
                          ],
                        ),
                      );
                      if (wide) {
                        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 4, child: departmentPanel), const SizedBox(width: 13), Expanded(flex: 6, child: attendancePanel)]);
                      }
                      return Column(children: [departmentPanel, const SizedBox(height: 13), attendancePanel]);
                    },
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(14)),
                    child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.privacy_tip_outlined, color: AppColors.blue, size: 18), SizedBox(width: 9), Expanded(child: Text('Reports use the same server-enforced access scope as the employee, attendance, and leave APIs. CSV is copied to this device’s clipboard only when you choose to export it.', style: TextStyle(color: AppColors.ink, fontSize: 11, height: 1.4)))]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({required this.title, required this.value, required this.subtitle, required this.icon, required this.color});

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => AppPanel(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: color, size: 20)),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w600)), const SizedBox(height: 4), Text(value, style: const TextStyle(color: AppColors.ink, fontSize: 20, fontWeight: FontWeight.w800)), Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 9))])),
          ],
        ),
      );
}

class _AttendanceReportRow extends StatelessWidget {
  const _AttendanceReportRow({required this.record});
  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(width: 33, height: 33, decoration: BoxDecoration(color: AppColors.softGreen, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 17)),
            const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(stringValue(record['employee_name'], fallback: 'Team member'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.ink, fontSize: 11, fontWeight: FontWeight.w700)), const SizedBox(height: 2), Text('${_datePart(record['punch_in_at'])} · ${_timePart(record['punch_in_at'])} – ${_timePart(record['punch_out_at'])}', style: const TextStyle(color: AppColors.muted, fontSize: 10))])),
            const SizedBox(width: 7),
            Text(stringValue(record['punch_source'], fallback: 'gps') == 'manual' ? 'Manual' : 'GPS', style: const TextStyle(color: AppColors.muted, fontSize: 9, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

String _dateOnly(DateTime date) {
  final year = date.year.toString().padLeft(4, "0");
  final month = date.month.toString().padLeft(2, "0");
  final day = date.day.toString().padLeft(2, "0");
  return '$year-$month-$day';
}

String _datePart(Object? value) {
  final text = stringValue(value);
  return text.length >= 10 ? text.substring(0, 10) : '—';
}

String _timePart(Object? value) {
  final text = stringValue(value);
  return text.length >= 16 ? text.substring(11, 16) : '—';
}

String _csvCell(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}
