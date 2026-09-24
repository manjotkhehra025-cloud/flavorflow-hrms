import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';

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

/// Routed approval inbox (super admin / route heads — SM / AGM).
class ApprovalsTab extends ConsumerWidget {
  const ApprovalsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final inbox = ref.watch(approvalsProvider);
    return Scaffold(
      backgroundColor: HMC.bg,
      appBar: AppBar(title: Text(T.s('Approvals', lang)), centerTitle: false),
      body: RefreshIndicator(
        color: HMC.primary,
        onRefresh: () async => ref.invalidate(approvalsProvider),
        child: inbox.when(
          loading: () => const Center(child: CircularProgressIndicator(color: HMC.primary)),
          error: (e, _) => ListView(children: [
            const SizedBox(height: 120),
            Center(child: Text(apiErrorMessage(e), style: TextStyle(color: Colors.grey.shade600))),
          ]),
          data: (rows) => rows.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 110),
                  Icon(Icons.check_circle_outline, size: 52, color: Colors.grey.shade300),
                  const SizedBox(height: 10),
                  Center(child: Text(T.s('All clear — nothing waiting on you', lang), style: TextStyle(color: Colors.grey.shade500))),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _ApprovalCard(row: rows[i]),
                ),
        ),
      ),
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
    final title = _title(row, lang);
    final decides = ValueNotifier<bool>(false);

    return Container(
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
        Text(title, style: TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.35)),
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
            onPressed: () => _decide(context, ref, kind, true),
            icon: const Icon(Icons.check, size: 16),
            label: Text(T.s('Approve', lang), style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ]),
        ValueListenableBuilder<bool>(valueListenable: decides, builder: (_, __, ___) => const SizedBox.shrink()),
      ]),
    );
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
        return '${r['type']} · ${_d(r['from'])} → ${_d(r['to'])} (${r['days']}d)'
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

  Color _kindColor(String kind) => switch (kind) {
        'leave' => HMC.amber,
        'punch' => const Color(0xFF2563EB),
        'gate' => HMC.teal,
        'swap' => const Color(0xFF7C3AED),
        _ => Colors.grey,
      };

  String _d(Object? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse('$iso')?.toLocal();
    if (d == null) return '$iso';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}';
  }
}
