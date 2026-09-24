import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';

final leavesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(apiProvider);
  final res = await dio.get<Map<String, dynamic>>('/api/leaves');
  return ((res.data?['requests'] as List?) ?? const [])
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList();
});

/// My leave requests (read-only in P2 — apply flow lands with P3 mockups).
class LeavesList extends ConsumerWidget {
  const LeavesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final leaves = ref.watch(leavesProvider);
    return Scaffold(
      backgroundColor: HMC.bg,
      appBar: AppBar(title: Text(T.s('My Leaves', lang)), centerTitle: false),
      body: RefreshIndicator(
        color: HMC.primary,
        onRefresh: () async => ref.invalidate(leavesProvider),
        child: leaves.when(
          loading: () => const Center(child: CircularProgressIndicator(color: HMC.primary)),
          error: (e, _) => ListView(children: [
            const SizedBox(height: 120),
            Center(child: Text(apiErrorMessage(e), style: TextStyle(color: Colors.grey.shade600))),
          ]),
          data: (rows) => rows.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 110),
                  Icon(Icons.eco_outlined, size: 52, color: Colors.grey.shade300),
                  const SizedBox(height: 10),
                  Center(child: Text(T.s('No leave requests yet', lang), style: TextStyle(color: Colors.grey.shade500))),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    final lt = (r['leaveType'] as Map?) ?? const {};
                    final status = r['status'] as String? ?? 'PENDING';
                    final tone = status == 'APPROVED'
                        ? HMC.emeraldDeep
                        : status == 'REJECTED'
                            ? HMC.danger
                            : HMC.amber;
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 5))],
                      ),
                      child: Row(children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), shape: BoxShape.circle),
                          child: Icon(
                            status == 'APPROVED'
                                ? Icons.check
                                : status == 'REJECTED'
                                    ? Icons.close
                                    : Icons.schedule,
                            color: tone,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${lt['name'] ?? 'Leave'} · ${r['days']}d',
                                style: const TextStyle(fontWeight: FontWeight.w800, color: HMC.ink)),
                            Text(
                              '${_d(r['fromDate'])} → ${_d(r['toDate'])}${r['reason'] != null ? ' · "${r['reason']}"' : ''}',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                            ),
                          ]),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(color: tone.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: tone)),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ),
    );
  }

  String _d(Object? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse('$iso')?.toLocal();
    if (d == null) return '$iso';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}';
  }
}
