import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../models/attendance.dart';
import '../../providers/employee_provider.dart';
import '../../repositories/repository_factory.dart';
import '../../widgets/common.dart';
import '../../widgets/status_colors.dart';

/// Admin: everyone's attendance for a chosen day.
class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  DateTime _date = dateOnly(DateTime.now());
  List<AttendanceRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final employees = context.read<EmployeeProvider>();
      if (employees.all.isEmpty) employees.load();
      _load();
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = context.read<Repositories>().attendance;
    final records = await repo.getDailyReport(_date);
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _date = picked;
      await _load();
    }
  }

  void _shift(int days) {
    final next = _date.add(Duration(days: days));
    if (next.isAfter(DateTime.now())) return;
    _date = dateOnly(next);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final employees = context.watch<EmployeeProvider>();
    final counts = <AttendanceStatus, int>{};
    for (final r in _records) {
      counts[r.status] = (counts[r.status] ?? 0) + 1;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Report'),
        actions: [
          IconButton(
            tooltip: 'Export',
            icon: const Icon(Icons.download),
            // TODO(export): generate CSV/Excel (e.g. `csv` or `excel` package).
            onPressed: () => showSnack(context, 'Export to Excel coming soon'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(Fmt.fullDay(_date), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: isSameDay(_date, DateTime.now()) ? null : () => _shift(1),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _count('Present', counts[AttendanceStatus.present] ?? 0, AttendanceStatus.present),
                _count('Absent', (counts[AttendanceStatus.absent] ?? 0) + (counts[AttendanceStatus.notMarked] ?? 0), AttendanceStatus.absent),
                _count('Leave', counts[AttendanceStatus.leave] ?? 0, AttendanceStatus.leave),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? const EmptyState(icon: Icons.analytics_outlined, message: 'No data')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: _records.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final r = _records[i];
                          final emp = employees.byId(r.employeeId);
                          final color = attendanceColor(r.status);
                          return Card(
                            child: ListTile(
                              leading: EmployeeAvatar(initials: emp?.initials ?? '?'),
                              title: Text(emp?.name ?? r.employeeId, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(r.hasPunchedIn
                                  ? 'In ${Fmt.time(r.punchIn)}  \u2022  Out ${Fmt.time(r.punchOut)}'
                                  : (r.note ?? emp?.department ?? '')),
                              trailing: StatusChip(r.status.label, color),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _count(String label, int value, AttendanceStatus status) {
    final color = attendanceColor(status);
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}
