import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

/// ── data ─────────────────────────────────────────────────────────────────────

final leavesDataProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = ref.read(apiProvider);
  final res = await dio.get<Map<String, dynamic>>('/api/leaves');
  return res.data ?? const {};
});

List<Map<String, dynamic>> _rows(Map<String, dynamic>? j, String key) =>
    ((j?[key] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

String _fmtD(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.day} ${months[d.month - 1]}';
}

/// ── Leaves tab: balances + my requests + apply (P3, mockups p3-apply/inbox) ──

class LeavesList extends ConsumerWidget {
  const LeavesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final data = ref.watch(leavesDataProvider);
    final canApplyLeave = ref.watch(sessionStoreProvider).user?.perms['canApplyLeave'] ?? true;

    return Scaffold(
      backgroundColor: HMC.bg,
      appBar: AppBar(title: Text(T.s('My Leaves', lang)), centerTitle: false),
      floatingActionButton: canApplyLeave
          ? FloatingActionButton.extended(
              onPressed: () async {
                final applied = await Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const ApplyLeavePage()));
                if (applied == true) ref.invalidate(leavesDataProvider);
              },
              backgroundColor: HMC.emeraldDeep,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: Text(T.s('Apply leave', lang), style: const TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: RefreshIndicator(
        color: HMC.primary,
        onRefresh: () async => ref.invalidate(leavesDataProvider),
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator(color: HMC.primary)),
          error: (e, _) => ListView(children: [
            const SizedBox(height: 120),
            Center(child: Text(apiErrorMessage(e), style: TextStyle(color: Colors.grey.shade600))),
          ]),
          data: (j) {
            final balances = _rows(j, 'balances');
            final reqs = _rows(j, 'requests');
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                // ── balance cards row (mockup: 3 white cards w/ progress bars)
                SizedBox(
                  height: 116,
                  child: Row(
                    children: [
                      for (final b in balances.take(3)) Expanded(child: _BalanceCard(b: b, lang: lang)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(T.s('My requests', lang),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: HMC.ink)),
                const SizedBox(height: 8),
                if (reqs.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    alignment: Alignment.center,
                    child: Text(T.s('No leave requests yet', lang), style: TextStyle(color: Colors.grey.shade500)),
                  )
                else
                  for (final r in reqs) _RequestRow(r: r, lang: lang),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final Map<String, dynamic> b;
  final String lang;
  const _BalanceCard({required this.b, required this.lang});

  @override
  Widget build(BuildContext context) {
    final quota = (b['quota'] as num?)?.toDouble() ?? 0;
    final used = (b['used'] as num?)?.toDouble() ?? 0;
    final pending = (b['pending'] as num?)?.toDouble() ?? 0;
    final remaining = b.containsKey('remaining') ? b['remaining'] : null;
    final remNum = remaining is num ? remaining.toDouble() : null;
    final left = remNum ?? (quota - used - pending);
    final filled = quota > 0 ? (left / quota).clamp(0.0, 1.0) : 0.0;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x11000000)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${b['name']}', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Text('${remNum == null ? '∞' : _trim(remNum)} ${T.s('left', lang)}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: HMC.ink)),
        const Spacer(),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: filled.toDouble(),
            minHeight: 5,
            backgroundColor: HMC.primaryFade,
            valueColor: const AlwaysStoppedAnimation(HMC.primaryDark),
          ),
        ),
        const SizedBox(height: 4),
        Text(quota > 0 ? '${_trim(quota)} ${T.s('yr', lang)}${pending > 0 ? ' · ${_trim(pending)} ${T.s('pending', lang)}' : ''}' : T.s('unlimited', lang),
            style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500)),
      ]),
    );
  }
}

String _trim(num n) => n == n.roundToDouble() ? '${n.round()}' : (n.toStringAsFixed(1));

class _RequestRow extends StatelessWidget {
  final Map<String, dynamic> r;
  final String lang;
  const _RequestRow({required this.r, required this.lang});

  @override
  Widget build(BuildContext context) {
    final lt = (r['leaveType'] as Map?) ?? const {};
    final status = r['status'] as String? ?? 'PENDING';
    final tone = status == 'APPROVED'
        ? HMC.emeraldDeep
        : status == 'REJECTED'
            ? HMC.danger
            : HMC.amber;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x11000000)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${lt['name'] ?? ''} · ${_fmtD(r['fromDate'] as String?)} – ${_fmtD(r['toDate'] as String?)}',
                style: const TextStyle(fontWeight: FontWeight.w900, color: HMC.ink, fontSize: 14)),
            const SizedBox(height: 2),
            Text(
              '${r['days']}${r['halfDay'] == true ? '½' : ''}d${r['reason'] != null ? ' · ${r['reason']}' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
          child: Text(T.s(status.toLowerCase(), lang),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: tone)),
        ),
      ]),
    );
  }
}

/// ── Apply leave page (mockup p3-apply) ───────────────────────────────────────

class ApplyLeavePage extends ConsumerStatefulWidget {
  const ApplyLeavePage({super.key});

  @override
  ConsumerState<ApplyLeavePage> createState() => _ApplyLeavePageState();
}

class _ApplyLeavePageState extends ConsumerState<ApplyLeavePage> {
  String? _typeId;
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  bool _halfDay = false;
  final _reasonCtl = TextEditingController();
  bool _busy = false;
  String? _error;

  int get _days => _to.difference(_from).inDays + 1;

  Future<void> _pick(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 120)),
      initialDate: isFrom ? _from : _to,
    );
    if (d != null) {
      setState(() {
        if (isFrom) {
          _from = d;
          if (_to.isBefore(_from)) _to = _from;
        } else {
          _to = d;
          if (_to.isBefore(_from)) _from = _to;
        }
      });
    }
  }

  Future<void> _submit(List<Map<String, dynamic>> types) async {
    if (_typeId == null) {
      setState(() => _error = 'Pick a leave type first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).post('/api/leaves', data: {
        'leaveTypeId': _typeId,
        'fromDate': '${_from.year}-${_from.month.toString().padLeft(2, '0')}-${_from.day.toString().padLeft(2, '0')}',
        'toDate': '${_to.year}-${_to.month.toString().padLeft(2, '0')}-${_to.day.toString().padLeft(2, '0')}',
        'reason': _reasonCtl.text.trim().isEmpty ? null : _reasonCtl.text.trim(),
        'halfDay': _halfDay && _days == 1,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(T.s('Leave request sent ✔', ref.read(langProvider))), backgroundColor: HMC.primaryDark),
      );
    } catch (e) {
      setState(() {
        _busy = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final data = ref.watch(leavesDataProvider).value ?? const <String, dynamic>{};
    final types = _rows(data, 'leaveTypes');
    final balances = _rows(data, 'balances');
    _typeId ??= types.isNotEmpty ? types.first['id'] as String? : null;

    return Scaffold(
      backgroundColor: HMC.bg,
      appBar: AppBar(title: Text(T.s('Apply leave', lang))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // balance strip
        SizedBox(
          height: 108,
          child: Row(children: [
            for (final b in balances.take(3)) Expanded(child: _BalanceCard(b: b, lang: lang)),
          ]),
        ),
        const SizedBox(height: 14),
        Text(T.s('Select Leave Type', lang),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: HMC.ink)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in types)
            ChoiceChip(
              selected: _typeId == t['id'],
              selectedColor: HMC.primaryFade,
              labelStyle: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _typeId == t['id'] ? HMC.primaryDark : HMC.ink),
              label: Text('${t['shortCode'] ?? t['name']}'),
              onSelected: (_) => setState(() => _typeId = t['id'] as String),
            ),
        ]),
        const SizedBox(height: 14),
        _DateTile(label: T.s('From', lang), date: _from, onTap: () => _pick(true)),
        const SizedBox(height: 10),
        _DateTile(label: T.s('To', lang), date: _to, onTap: () => _pick(false)),
        const SizedBox(height: 8),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: HMC.primaryDark, borderRadius: BorderRadius.circular(999)),
            child: Text('${_days} ${T.s('days', lang)}${_halfDay && _days == 1 ? ' (½)' : ''}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
          ),
        ),
        if (_days == 1)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: HMC.primaryDark,
            title: Text(T.s('Half day', lang), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            value: _halfDay,
            onChanged: (v) => setState(() => _halfDay = v == true),
          ),
        const SizedBox(height: 6),
        TextField(
          controller: _reasonCtl,
          maxLines: 3,
          maxLength: 200,
          decoration: InputDecoration(labelText: T.s('Reason for leave', lang)),
        ),
        Container(
          margin: const EdgeInsets.only(top: 4, bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.lightbulb_outline, color: HMC.amber, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(T.s('Your head will decide — usually same day', lang),
                  style: TextStyle(color: Colors.grey.shade800, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_error!, style: const TextStyle(color: HMC.danger, fontWeight: FontWeight.w600)),
          ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: HMC.primaryDark),
          onPressed: _busy ? null : () => _submit(types),
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.send_rounded),
          label: Text(T.s('Send for approval', lang)),
        ),
      ]),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;
  const _DateTile({required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: HMC.ink)),
            ]),
          ),
          const Icon(Icons.calendar_today_outlined, size: 18, color: HMC.ink),
        ]),
      ),
    );
  }
}
