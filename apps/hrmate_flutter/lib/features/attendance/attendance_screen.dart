import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../home/home_data.dart';

/// Attendance history — approved mockup p2-history.png
/// (month header, present-day stat card, current-week dot strip, day cards,
/// amber "+ Manual punch / OT" sheet).
class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final block = ref.watch(attendanceProvider);

    return Scaffold(
      backgroundColor: HMC.bg,
      body: SafeArea(
        child: block.when(
          loading: () => const Center(child: CircularProgressIndicator(color: HMC.primary)),
          error: (e, _) => Center(child: Text(apiErrorMessage(e))),
          data: (b) {
            final now = DateTime.now();
            final daysThisMonth = now.day;
            final present = b.records.where((r) => r['status'] == 'PRESENT' || r['status'] == 'HALF_DAY').length;
            final records = b.records.take(30).toList();
            final weekStart = now.subtract(Duration(days: now.weekday - 1));
            final byDay = {for (var r in records) _dateKey(DateTime.tryParse('${r['date']}') ?? now): r};

            return Stack(children: [
              ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 120), children: [
                Row(children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: HMC.ink), onPressed: () => context.pop()),
                  const Spacer(),
                  Text(_monthTitle(now, lang), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: HMC.ink)),
                  const Spacer(),
                  const SizedBox(width: 48),
                ]),
                const SizedBox(height: 8),
                // stat card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF0E2233), Color(0xFF12334C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today_outlined, color: Colors.white.withValues(alpha: 0.55), size: 26),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          '${T.s('You were present on', lang)} $present / $daysThisMonth',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, height: 1.3),
                        ),
                        Text(T.s('Sept target: quota met for OT', lang), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 18),
                // week strip
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(7, (i) {
                    final d = weekStart.add(Duration(days: i));
                    if (d.isAfter(now)) return Expanded(child: Text(_wk(i, lang), textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade300, fontSize: 12)));
                    final key = _dateKey(d);
                    final r = byDay[key];
                    var dot = switch (r?['status']) {
                      'VERIFIED' => HMC.emeraldDeep,
                      'PRESENT' => HMC.amber,
                      'ABSENT' => HMC.danger,
                      _ => Colors.grey.shade300,
                    };
                    if (r == null && d.isBefore(now)) dot = HMC.danger;
                    if (r == null && _sameDay(d, now)) dot = Colors.grey.shade300;
                    return Expanded(
                      child: Column(children: [
                        Text(_wk(i, lang), style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                        const SizedBox(height: 6),
                        CircleAvatar(radius: 4, backgroundColor: dot),
                      ]),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                ...records.map((r) => _DayCard(rec: r, lang: lang, shiftName: '${b.shift['name']}')),
              ]),
              Positioned(
                left: 0,
                right: 0,
                bottom: 14,
                child: Center(
                  child: Material(
                    color: HMC.amber,
                    borderRadius: BorderRadius.circular(30),
                    elevation: 8,
                    child: InkWell(
                      onTap: () => showRequestSheet(context, ref, lang),
                      borderRadius: BorderRadius.circular(30),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                        child: Text(
                          T.s('+  MANUAL PUNCH / OT', lang).toUpperCase(),
                          style: const TextStyle(color: HMC.ink, fontWeight: FontWeight.w900, letterSpacing: 1.1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  static final _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  static final _weekNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _monthTitle(DateTime d, String lang) => '${_monthNames[d.month - 1]} ${d.year}';
  String _wk(int i, String lang) => _weekNames[i];
  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

String _dateKey(DateTime d) {
  final local = DateTime(d.year, d.month, d.day);
  return '${local.year}-${local.month}-${local.day}';
}

class _DayCard extends StatelessWidget {
  final Map<String, dynamic> rec;
  final String lang;
  final String shiftName;
  const _DayCard({required this.rec, required this.lang, required this.shiftName});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse('${rec['date']}')?.toLocal();
    final inAt = rec['checkIn'] == null ? null : DateTime.tryParse('${rec['checkIn']}')?.toLocal();
    final outAt = rec['checkOut'] == null ? null : DateTime.tryParse('${rec['checkOut']}')?.toLocal();
    final status = rec['status'] as String? ?? 'PRESENT';
    final tone = switch (status) {
      'PRESENT' => HMC.amber,
      'VERIFIED' => HMC.emeraldDeep,
      'ABSENT' => HMC.danger,
      'HALF_DAY' => Colors.purple,
      _ => Colors.grey,
    };
    final otH = (rec['otHours'] as num?)?.toDouble() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${date?.day ?? ''}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: HMC.ink)),
            Text(_weekday(date, lang).toUpperCase(), style: TextStyle(color: Colors.grey.shade400, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${T.s('Check in', lang)} · ${_hm(inAt)}  ·  ${T.s('Check out', lang)} · ${_hm(outAt)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: HMC.ink)),
              const SizedBox(height: 2),
              Text(shiftName, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_hm(outAt), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: HMC.ink)),
            Text(T.s(status == 'HALF_DAY' ? 'HALF DAY' : status, lang), style: TextStyle(color: tone, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          ]),
        ]),
        if (otH > 0) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.schedule, size: 14, color: HMC.amber),
            const SizedBox(width: 6),
            Text('+${otH.toStringAsFixed(1)} h OT', style: const TextStyle(color: HMC.amber, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ]),
        ],
      ]),
    );
  }

  String _weekday(DateTime? d, String lang) {
    if (d == null) return '';
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return names[d.weekday - 1];
  }

  String _hm(DateTime? d) => d == null ? '—:—' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Bottom sheet for manual punch / OT (server /api/requests).
Future<void> showRequestSheet(BuildContext context, WidgetRef ref, String lang) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _RequestSheet(lang: lang, parentRef: ref),
    ),
  );
}

class _RequestSheet extends ConsumerStatefulWidget {
  final String lang;
  final WidgetRef parentRef;
  const _RequestSheet({required this.lang, required this.parentRef});

  @override
  ConsumerState<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends ConsumerState<_RequestSheet> {
  String _type = 'MANUAL_IN';
  DateTime _date = DateTime.now();
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  double _hours = 1.0;
  final _reason = TextEditingController();
  bool _busy = false;
  String? _err;

  static const _options = [
    ('MANUAL_IN', 'Punch in (manual)'),
    ('MANUAL_OUT', 'Punch out (manual)'),
    ('OT', 'Overtime'),
  ];

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(T.s('REQUEST ATTENDANCE FIX', lang).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, color: HMC.ink, letterSpacing: 1.2)),
          const Spacer(),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: _options.map((o) {
          final active = _type == o.$1;
          return ChoiceChip(
            label: Text(T.s(o.$2, lang)),
            selected: active,
            onSelected: (_) => setState(() => _type = o.$1),
            selectedColor: HMC.primaryFade,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: active ? HMC.primaryDark : HMC.ink),
          );
        }).toList()),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_month, size: 18),
              label: Text('${_date.day}/${_date.month}/${_date.year}'),
              style: OutlinedButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (_type != 'OT')
          OutlinedButton.icon(
            icon: const Icon(Icons.access_time, size: 18),
            label: Text(T.s('Time:', lang) + ' ${_time.format(context)}'),
            style: OutlinedButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () async {
              final t = await showTimePicker(context: context, initialTime: _time);
              if (t != null) setState(() => _time = t);
            },
          )
        else
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${T.s('OT hours', lang)}: ${_hours.toStringAsFixed(1)}h', style: const TextStyle(fontWeight: FontWeight.w700, color: HMC.ink)),
            Slider(
              value: _hours,
              min: 0.5,
              max: 8,
              divisions: 15,
              activeColor: HMC.primary,
              onChanged: (v) => setState(() => _hours = v),
            ),
          ]),
        if (_type != 'OT') const SizedBox(height: 8),
        TextField(
          controller: _reason,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: T.s('Reason (required)', lang),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            isDense: true,
          ),
        ),
        if (_err != null) ...[
          const SizedBox(height: 8),
          Text(_err!, style: const TextStyle(color: HMC.danger, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ],
        const SizedBox(height: 14),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: HMC.ink, padding: const EdgeInsets.symmetric(vertical: 15), shape: const StadiumBorder()),
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? '${T.s('Sending…', lang)}' : T.s('Send for approval', lang), style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }

  Future<void> _submit() async {
    final lang = widget.lang;
    if (_reason.text.trim().length < 4) {
      setState(() => _err = T.s('Reason is required (min 4 chars)', lang));
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    final isoDate = '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
    try {
      final payload = <String, dynamic>{
        'type': _type,
        'date': isoDate,
        'reason': _reason.text.trim(),
        if (_type != 'OT') 'time': '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
        if (_type == 'OT') 'hours': _hours,
      };
      await ref.read(apiProvider).post('/api/requests', data: payload);
      ref.invalidate(attendanceProvider);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(T.s('Request sent ✓ waiting for approval', lang)),
          backgroundColor: HMC.primaryDark,
        ));
      }
    } catch (e) {
      setState(() => _err = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
