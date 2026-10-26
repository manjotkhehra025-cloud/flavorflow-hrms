import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/attendance.dart';
import '../../providers/attendance_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/punch_card.dart';
import '../../widgets/status_colors.dart';

class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AttendanceProvider>();
    final summary = p.monthSummary;
    final records = p.monthRecords.reversed.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const PunchCard(),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => p.changeMonth(-1)),
                      Expanded(
                        child: Text(Fmt.month(p.selectedMonth),
                            textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: p.isCurrentMonth ? null : () => p.changeMonth(1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (p.loading)
                    const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())
                  else
                    _MonthCalendar(month: p.selectedMonth, records: p.monthRecords),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      AttendanceStatus.present,
                      AttendanceStatus.absent,
                      AttendanceStatus.leave,
                      AttendanceStatus.holiday,
                      AttendanceStatus.weekend,
                    ].map((s) => _Legend(status: s, count: summary[s] ?? 0)).toList(),
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Stat('Present days', '${summary[AttendanceStatus.present] ?? 0}'),
                      _Stat('Total hours', Fmt.duration(p.monthWorked)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SectionHeader('History'),
          if (records.isEmpty && !p.loading)
            const EmptyState(icon: Icons.event_busy, message: 'No attendance for this month'),
          ...records.map((r) => _HistoryTile(record: r)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({required this.month, required this.records});
  final DateTime month;
  final List<AttendanceRecord> records;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = DateTime(month.year, month.month, 1).weekday - 1; // Monday first
    final byDay = {for (final r in records) r.date.day: r};
    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final cells = <Widget>[
      ...weekdays.map((d) => Center(child: Text(d, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.muted)))),
      ...List.generate(leading, (_) => const SizedBox()),
      ...List.generate(daysInMonth, (i) {
        final day = i + 1;
        final r = byDay[day];
        final color = r == null ? null : attendanceColor(r.status);
        final isToday = isSameDay(DateTime(month.year, month.month, day), DateTime.now());
        return Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: color?.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: isToday ? Border.all(color: AppTheme.primary, width: 2) : null,
          ),
          alignment: Alignment.center,
          child: Text(
            '$day',
            style: TextStyle(color: color ?? Colors.grey.shade400, fontWeight: FontWeight.w600),
          ),
        );
      }),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cells,
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.status, required this.count});
  final AttendanceStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: attendanceColor(status), shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text('${status.label} ($count)', style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record});
  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final color = attendanceColor(record.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${record.date.day}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
                Text(Fmt.weekday(record.date), style: TextStyle(fontSize: 11, color: color)),
              ],
            ),
          ),
          title: record.hasPunchedIn
              ? Text('${Fmt.time(record.punchIn)}  -  ${Fmt.time(record.punchOut)}')
              : Text(record.note ?? record.status.label),
          subtitle: record.hasPunchedIn ? Text('Worked ${Fmt.duration(record.workedDuration)}') : null,
          trailing: StatusChip(record.status.label, color),
        ),
      ),
    );
  }
}
