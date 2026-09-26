import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';

final rosterProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = ref.read(apiProvider);
  final res = await dio.get<Map<String, dynamic>>('/api/roster');
  return res.data ?? const {};
});

const _dows = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// My Roster (mockup p4-roster): week strip + shift rows + swap FAB.
class RosterScreen extends ConsumerWidget {
  const RosterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final data = ref.watch(rosterProvider);

    return Scaffold(
      appBar: AppBar(title: Text(T.s('My Roster', lang))),
      backgroundColor: HMC.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        onPressed: () async {
          final done = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const _SwapSheet(),
          );
          if (done == true) ref.invalidate(rosterProvider);
        },
        icon: const Icon(Icons.swap_horiz),
        label: Text(T.s('Swap shift', lang), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        color: HMC.primary,
        onRefresh: () async => ref.invalidate(rosterProvider),
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator(color: HMC.primary)),
          error: (e, _) => ListView(children: [
            const SizedBox(height: 120),
            Center(child: Text(apiErrorMessage(e), style: TextStyle(color: Colors.grey.shade600))),
          ]),
          data: (j) {
            final days = ((j['days'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
            final swaps = ((j['swaps'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
            final byDate = {for (final s in swaps) '${s['date']}': s};
            final monthAnchor = days.isNotEmpty ? DateTime.tryParse('${days[days.length ~/ 2]['date']}') : DateTime.now();
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
              children: [
                // week strip
                if (monthAnchor != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12, top: 4),
                    child: Text('${_months[monthAnchor.month - 1]} ${monthAnchor.year}',
                        style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                Row(children: [
                  for (final d in days) Expanded(child: _DayChip(day: d)),
                ]),
                const SizedBox(height: 16),
                for (final d in days) _DayRow(day: d, swap: byDate['${d['date']}'] , lang: lang),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  final Map<String, dynamic> day;
  const _DayChip({required this.day});

  @override
  Widget build(BuildContext context) {
    final dd = DateTime.parse('${day['date']}');
    final today = day['isToday'] == true;
    return Column(children: [
      Text(_dows[dd.weekday - 1], style: TextStyle(fontSize: 10.5, color: today ? HMC.primaryDark : Colors.grey.shade500, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Container(
        width: 34, height: 44,
        decoration: BoxDecoration(
          color: today ? HMC.primaryDark : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${dd.day}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: today ? Colors.white : HMC.ink)),
          Text(_months[dd.month - 1], style: TextStyle(fontSize: 8.5, color: today ? Colors.white70 : Colors.grey.shade500)),
        ]),
      ),
    ]);
  }
}

class _DayRow extends StatelessWidget {
  final Map<String, dynamic> day;
  final Map<String, dynamic>? swap;
  final String lang;
  const _DayRow({required this.day, required this.swap, required this.lang});

  @override
  Widget build(BuildContext context) {
    final dd = DateTime.parse('${day['date']}');
    final today = day['isToday'] == true;
    final off = day['off'] == true;
    final shift = (day['shift'] as Map?)?.cast<String, dynamic>();
    final end = shift == null ? null : _endTime(shift['startTime'] as String? ?? '09:00', (shift['durationH'] as num?)?.toDouble() ?? 9);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: today ? Border.all(color: HMC.primary, width: 1.4) : Border.all(color: const Color(0x11000000)),
      ),
      child: Row(children: [
        Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: today ? HMC.primaryFade : HMC.bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Text(today ? T.s('Today', lang) : _dows[dd.weekday - 1], style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: today ? HMC.primaryDark : Colors.grey.shade500)),
            Text('${dd.day}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: HMC.ink)),
            Text(_months[dd.month - 1], style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            off
                ? Text(T.s('OFF DAY', lang), style: TextStyle(fontWeight: FontWeight.w800, color: Colors.grey.shade500, fontSize: 14))
                : Text('${shift?['name'] ?? T.s('General Shift', lang)}', style: const TextStyle(fontWeight: FontWeight.w900, color: HMC.ink, fontSize: 14.5)),
            if (!off && shift != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(children: [
                  Icon(Icons.access_time, size: 13, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text('${shift['startTime']} – $end', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ),
          ]),
        ),
        if (swap != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: const Color(0xFF7C3AED).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
            child: Text(
              swap!['status'] == 'PENDING'
                  ? T.s('Swap pending', lang)
                  : '${T.s('Swapped with', lang)} ${(swap!['otherPerson'] as Map)['firstName']}',
              style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 10.5, fontWeight: FontWeight.w900),
            ),
          )
        else if (today)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: HMC.primaryDark, borderRadius: BorderRadius.circular(999)),
            child: Text(T.s('TODAY', lang).toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
          ),
      ]),
    );
  }

  String _endTime(String start, double durH) {
    final parts = start.split(':');
    final h = int.tryParse(parts[0]) ?? 9;
    final m = int.tryParse(parts[1]) ?? 0;
    final total = h * 60 + m + (durH * 60).round();
    return '${((total ~/ 60) % 24).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
  }
}

/// ── Request swap sheet (purple, matches FAB) ─────────────────────────────────

class _SwapSheet extends ConsumerStatefulWidget {
  const _SwapSheet();

  @override
  ConsumerState<_SwapSheet> createState() => _SwapSheetState();
}

class _SwapSheetState extends ConsumerState<_SwapSheet> {
  String? _peerId;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  final _noteCtl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final peers = ((ref.watch(rosterProvider).value?['peers'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();

    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 14),
        Text(T.s('Swap my shift', lang), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: HMC.ink)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          decoration: InputDecoration(
            labelText: T.s('Coworker', lang),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          value: _peerId,
          items: [
            for (final p in peers)
              DropdownMenuItem(value: '${p['id']}', child: Text('${p['name']} (${p['code']})')),
          ],
          onChanged: (v) => setState(() => _peerId = v),
        ),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 60)),
              initialDate: _date,
            );
            if (d != null) setState(() => _date = d);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Icon(Icons.calendar_month_outlined, size: 18, color: HMC.ink),
              const SizedBox(width: 10),
              Text('${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: _noteCtl, maxLength: 200, decoration: InputDecoration(labelText: T.s('Note (optional)', lang))),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: const TextStyle(color: HMC.danger, fontWeight: FontWeight.w600))),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.swap_horiz),
          label: Text(T.s('Send swap request', lang), style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }

  Future<void> _submit() async {
    if (_peerId == null) {
      setState(() => _error = 'Pick a coworker first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).post('/api/roster', data: {
        'peerId': _peerId,
        'date': '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
        if (_noteCtl.text.trim().isNotEmpty) 'note': _noteCtl.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Swap request sent ✔'),
        backgroundColor: Color(0xFF7C3AED),
      ));
    } catch (e) {
      setState(() {
        _busy = false;
        _error = apiErrorMessage(e);
      });
    }
  }
}
