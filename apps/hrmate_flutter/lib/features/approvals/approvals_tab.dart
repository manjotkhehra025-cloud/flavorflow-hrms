import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../alerts/alerts_sheet.dart';

final approvalsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(apiProvider);
  final res = await dio.get<Map<String, dynamic>>('/api/approvals');
  final d = res.data ?? const {};
  final items = <Map<String, dynamic>>[
    ...((d['leaves'] as List?) ?? const []).cast(),
    ...((d['punches'] as List?) ?? const []).cast(),
    ...((d['gates'] as List?) ?? const []).cast(),
    ...((d['swaps'] as List?) ?? const []).cast(),
  ].map((e) => (e as Map).cast<String, dynamic>()).toList();
  items.sort((a, b) => ('${a['at'] ?? ''}').compareTo('${b['at'] ?? ''}'));
  return items;
});

final approvalFilterProvider = StateProvider<String>((ref) => 'all');

/// Routed approval inbox (super admin / route heads — SM / AGM).
/// P3: unified filter chips + decide bottom-sheet (mockups p3-inbox / p3-decide).
class ApprovalsTab extends ConsumerWidget {
  const ApprovalsTab({super.key});

  static const _kinds = ['all', 'leave', 'punch', 'gate', 'swap'];
  static const _labels = {'all': 'All', 'leave': 'Leave', 'punch': 'Punch', 'gate': 'Gate pass', 'swap': 'Swap'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final filter = ref.watch(approvalFilterProvider);
    final inbox = ref.watch(approvalsProvider);

    return Scaffold(
      backgroundColor: HMC.bg,
      appBar: AppBar(
        centerTitle: false,
        title: Row(children: [
          Text(T.s('Approvals', lang)),
          const SizedBox(width: 8),
          inbox.maybeWhen(
            data: (rows) => rows.isEmpty
                ? const SizedBox.shrink()
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                    decoration: BoxDecoration(color: HMC.amber, borderRadius: BorderRadius.circular(999)),
                    child: Text('${rows.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: HMC.ink)),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ]),
      ),
      body: Column(children: [
        // filter chips (All / Leave / Punch / Gate / Swap)
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              for (final k in _kinds)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: filter == k,
                    selectedColor: HMC.primaryFade,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: filter == k ? HMC.primaryDark : HMC.ink,
                    ),
                    label: Text(T.s(_labels[k] ?? k, lang)),
                    onSelected: (_) => ref.read(approvalFilterProvider.notifier).state = k,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: HMC.primary,
            onRefresh: () async => ref.invalidate(approvalsProvider),
            child: inbox.when(
              loading: () => const Center(child: CircularProgressIndicator(color: HMC.primary)),
              error: (e, _) => ListView(children: [
                const SizedBox(height: 120),
                Center(child: Text(apiErrorMessage(e), style: TextStyle(color: Colors.grey.shade600))),
              ]),
              data: (rows) {
                final visible = filter == 'all' ? rows : rows.where((r) => r['kind'] == filter).toList();
                return visible.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 110),
                        Icon(Icons.check_circle_outline, size: 52, color: Colors.grey.shade300),
                        const SizedBox(height: 10),
                        Center(child: Text(T.s('All clear — nothing waiting on you', lang), style: TextStyle(color: Colors.grey.shade500))),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _ApprovalCard(row: visible[i]),
                      );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class _ApprovalCard extends ConsumerWidget {
  final Map<String, dynamic> row;
  const _ApprovalCard({required this.row});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final kind = row['kind'] as String;
    final emp = (row['employee'] as Map).cast<String, dynamic>();

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openSheet(context, ref),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: _kindColor(kind).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text(kind.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: _kindColor(kind), letterSpacing: 0.8)),
            ),
            const Spacer(),
            Text('${emp['name']} · ${emp['code']}', style: const TextStyle(fontWeight: FontWeight.w800, color: HMC.ink)),
          ]),
          const SizedBox(height: 8),
          Text(_title(row, lang), style: TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.35)),
          if ((row['peer'] as Map?) != null)
            Text('⇄ ${(row['peer'] as Map)['name']}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton.icon(
              onPressed: () => _decide(context, ref, kind, false),
              icon: const Icon(Icons.close, size: 16, color: HMC.danger),
              label: Text(T.s('Reject', lang), style: const TextStyle(color: HMC.danger, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: HMC.primaryDark, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
              onPressed: () => _openSheet(context, ref, focusApprove: true),
              icon: const Icon(Icons.check, size: 16),
              label: Text(T.s('Approve', lang), style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context, WidgetRef ref, {bool focusApprove = false}) async {
    final decided = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DecideSheet(row: row),
    );
    if (decided == true) {
      ref.invalidate(approvalsProvider);
      ref.invalidate(alertsProvider);
    }
  }

  Future<void> _decide(BuildContext context, WidgetRef ref, String kind, bool approve) async {
    final lang = ref.read(langProvider);
    try {
      await ref.read(apiProvider).post('/api/approvals/decide', data: {
        'kind': kind,
        'id': row['id'],
        'action': approve ? 'approve' : 'reject',
      });
      ref.invalidate(approvalsProvider);
      ref.invalidate(alertsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approve ? T.s('Approved ✓', lang) : T.s('Rejected', lang)),
          backgroundColor: approve ? HMC.primaryDark : HMC.danger,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  String _title(Map<String, dynamic> r, String lang) {
    switch (r['kind']) {
      case 'leave':
        return '${r['type']} · ${_d(r['from'])} → ${_d(r['to'])} (${r['days']}${r['halfDay'] == true ? '½' : ''}d)'
            '${r['reason'] != null ? ' · "${r['reason']}"' : ''}';
      case 'punch':
        return r['type'] == 'OT'
            ? 'OT · ${_d(r['date'])} · ${r['hours']}h · "${r['reason']}"'
            : '${r['type'] == 'MANUAL_IN' ? 'Punch in' : 'Punch out'} · ${_d(r['date'])} at ${r['time']} · "${r['reason']}"';
      case 'gate':
        return 'Gate pass · ${_d(r['date'])} · out ${r['exitAt']}${r['returnAt'] != null ? ' → back ${r['returnAt']}' : ''}'
            '${r['reason'] != null ? ' · "${r['reason']}"' : ''}';
      case 'swap':
        return 'Swap ${_d(r['date'])}${r['note'] != null ? ' · "${r['note']}"' : ''}';
      default:
        return '';
    }
  }

  static Color _kindColor(String kind) => switch (kind) {
        'leave' => HMC.amber,
        'punch' => const Color(0xFF2563EB),
        'gate' => HMC.teal,
        'swap' => const Color(0xFF7C3AED),
        _ => Colors.grey,
      };
}

/// Decide bottom-sheet (mockup p3-decide) — avatar + details + balance hint.
class _DecideSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> row;
  const _DecideSheet({required this.row});

  @override
  ConsumerState<_DecideSheet> createState() => _DecideSheetState();
}

class _DecideSheetState extends ConsumerState<_DecideSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _decide(bool approve) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).post('/api/approvals/decide', data: {
        'kind': widget.row['kind'],
        'id': widget.row['id'],
        'action': approve ? 'approve' : 'reject',
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approve ? 'Approved ✓' : 'Rejected'),
        backgroundColor: approve ? HMC.primaryDark : HMC.danger,
      ));
    } catch (e) {
      setState(() {
        _busy = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final kind = r['kind'] as String;
    final emp = (r['employee'] as Map).cast<String, dynamic>();
    final name = '${emp['name'] ?? ''}';
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).map((w) => w[0]).take(2).join().toUpperCase();

    // Balance hint: server sends remaining for the requester's leave type.
    String? hint;
    if (kind == 'leave' && r['remaining'] != null) {
      final rem = (r['remaining'] as num).toDouble();
      final days = (r['days'] as num?)?.toDouble() ?? 0;
      final after = rem - days;
      hint = '${r['type']} balance after: ${after < 0 ? 0 : (after == after.roundToDouble() ? after.round().toString() : after.toStringAsFixed(1))} days';
    }

    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 14),
        Text('$name asks for ${kind == 'leave' ? 'leave' : kind == 'punch' ? 'a punch fix' : kind == 'gate' ? 'a gate pass' : 'a shift swap'}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: HMC.ink)),
        const SizedBox(height: 12),
        Row(children: [
          CircleAvatar(backgroundColor: HMC.primaryFade, child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w900, color: HMC.primaryDark))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w800, color: HMC.ink, fontSize: 15)),
              Text('${emp['code']}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: _ApprovalCard._kindColor(kind).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(kind.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: _ApprovalCard._kindColor(kind))),
          ),
        ]),
        const SizedBox(height: 12),
        if (kind == 'leave') _kv('Dates', '${_d(r['from'])} – ${_d(r['to'])}   (${r['days']}${r['halfDay'] == true ? '½' : ''} days)'),
        if (kind == 'punch') _kv('When', '${_d(r['date'])}${r['time'] != null ? ' at ${r['time']}' : ''}${r['type'] == 'OT' ? ' · OT ${r['hours']}h' : ''}'),
        if (kind == 'gate') _kv('Out', '${r['exitAt']}${r['returnAt'] != null ? ' → ${r['returnAt']}' : ''} · ${_d(r['date'])}'),
        if (kind == 'swap') _kv('Swap', '${_d(r['date'])} ⇄ ${(r['peer'] as Map?)?['name'] ?? ''}'),
        if ((r['reason'] ?? r['note']) != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: HMC.bg, borderRadius: BorderRadius.circular(12)),
            child: Text('“${r['reason'] ?? r['note']}”', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey.shade700, fontSize: 13, height: 1.35)),
          ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 15, color: HMC.teal),
              const SizedBox(width: 6),
              Text(hint, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: HMC.teal)),
            ]),
          ),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: HMC.danger, fontWeight: FontWeight.w600))),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: HMC.primaryDark),
          onPressed: _busy ? null : () => _decide(true),
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.check),
          label: const Text('Approve', style: TextStyle(fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: HMC.danger,
            side: const BorderSide(color: HMC.danger),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          onPressed: _busy ? null : () => _decide(false),
          icon: const Icon(Icons.close),
          label: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text('Decision is final — $name gets a notification',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ),
      ]),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Text('$k:  ', style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w600)),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w800, color: HMC.ink, fontSize: 13.5))),
        ]),
      );
}

/// Format an ISO date as "Sep 26" (file-private helper for cards + sheet).
String _d(Object? iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse('$iso')?.toLocal();
  if (d == null) return '$iso';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[d.month - 1]} ${d.day}';
}
