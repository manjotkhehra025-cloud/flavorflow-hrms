import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class UnifiedApprovalsScreen extends StatefulWidget {
  const UnifiedApprovalsScreen({super.key});

  @override
  State<UnifiedApprovalsScreen> createState() => _UnifiedApprovalsScreenState();
}

class _UnifiedApprovalsScreenState extends State<UnifiedApprovalsScreen> {
  List<_ApprovalItem> _items = const [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';
  String? _busyKey;

  @override
  void initState() {
    super.initState();
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
      final user = AppScope.of(context).user!;
      final api = AppScope.of(context).api;
      final requests = <({String type, String path, Map<String, String> query})>[];
      if (user.can('leave.approve')) requests.add((type: 'leave', path: 'leave-requests', query: const {'status': 'pending'}));
      if (user.canAny(const ['attendance.approve', 'attendance.manage'])) {
        requests.add((type: 'overtime', path: 'attendance/overtime-requests', query: const {'status': 'pending'}));
        requests.add((type: 'manual', path: 'attendance/manual-punch-requests', query: const {'status': 'pending'}));
      }
      if (user.canAny(const ['gatepass.approve', 'gatepass.manage'])) requests.add((type: 'gate_pass', path: 'gate-passes', query: const {'status': 'pending'}));
      if (user.canAny(const ['shifts.swap.approve', 'shifts.manage'])) requests.add((type: 'shift_swap', path: 'shift-swap-requests', query: const {'status': 'pending_manager'}));
      final responses = await Future.wait<dynamic>(requests.map((request) => api.get(request.path, query: request.query)));
      if (!mounted) return;
      final next = <_ApprovalItem>[];
      for (var index = 0; index < requests.length; index++) {
        final type = requests[index].type;
        var rows = asJsonList(asJsonMap(responses[index])['items']);
        if (type == 'shift_swap' && !user.can('shifts.manage') && user.employeeId != null) {
          rows = rows.where((row) =>
            int.tryParse(stringValue(row['requester_employee_id'])) != user.employeeId &&
            int.tryParse(stringValue(row['target_employee_id'])) != user.employeeId
          ).toList();
        }
        for (final row in rows) {
          next.add(_ApprovalItem(type: type, data: row));
        }
      }
      next.sort((a, b) => stringValue(b.data['requested_at']).compareTo(stringValue(a.data['requested_at'])));
      setState(() => _items = next);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(_ApprovalItem item, bool approve) async {
    final id = stringValue(item.data['id']);
    final key = '${item.type}:$id';
    String path;
    String decision;
    switch (item.type) {
      case 'leave':
        path = 'leave-requests/$id/decision';
        decision = approve ? 'approved' : 'rejected';
        break;
      case 'overtime':
        path = 'attendance/overtime-requests/$id/decision';
        decision = approve ? 'approved' : 'rejected';
        break;
      case 'manual':
        path = 'attendance/manual-punch-requests/$id/decision';
        decision = approve ? 'approved' : 'rejected';
        break;
      case 'gate_pass':
        path = 'gate-passes/$id/decision';
        decision = approve ? 'approved' : 'rejected';
        break;
      default:
        path = 'shift-swap-requests/$id/decision';
        decision = approve ? 'approve' : 'reject';
        break;
    }
    setState(() => _busyKey = key);
    try {
      await AppScope.of(context).api.post(path, {'decision': decision});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? 'Request approved.' : 'Request rejected.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _items.where((item) => _filter == 'all' || item.type == _filter).toList();
    final categories = <(String, String)>[
      ('all', 'All'),
      ('leave', 'Leave'),
      ('overtime', 'Overtime'),
      ('manual', 'Attendance fixes'),
      ('gate_pass', 'Gate passes'),
      ('shift_swap', 'Shift swaps'),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                PageHeading(
                  title: 'Approvals',
                  subtitle: 'One queue for leave, attendance, gate passes, and shift swaps.',
                  trailing: IconButton.filledTonal(onPressed: _load, tooltip: 'Refresh approvals', icon: const Icon(Icons.refresh_rounded)),
                ),
                Wrap(spacing: 8, runSpacing: 8, children: categories.map((entry) {
                  final count = entry.$1 == 'all' ? _items.length : _items.where((item) => item.type == entry.$1).length;
                  return ChoiceChip(
                    label: Text('${entry.$2}  $count'),
                    selected: _filter == entry.$1,
                    onSelected: (_) => setState(() => _filter = entry.$1),
                    selectedColor: AppColors.softBlue,
                    side: BorderSide(color: _filter == entry.$1 ? AppColors.blue.withValues(alpha: 0.24) : AppColors.line),
                    labelStyle: TextStyle(color: _filter == entry.$1 ? AppColors.blue : AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700),
                  );
                }).toList()),
                const SizedBox(height: 14),
                if (_error != null) ErrorNotice(message: _error!, onRetry: _load)
                else if (_loading && _items.isEmpty)
                  const SizedBox(height: 220, child: LoadingView(label: 'Loading approval queues…'))
                else if (filtered.isEmpty)
                  const AppPanel(child: EmptyNotice(
                    title: 'Nothing needs approval',
                    subtitle: 'New requests from your team will appear here when submitted.',
                    icon: Icons.fact_check_outlined,
                  ))
                else
                  ...filtered.map((item) {
                    final key = '${item.type}:${stringValue(item.data['id'])}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 11),
                      child: _ApprovalCard(
                        item: item,
                        busy: _busyKey == key,
                        onApprove: () => _decide(item, true),
                        onReject: () => _decide(item, false),
                      ),
                    );
                  }),
                if (_loading && _items.isNotEmpty)
                  const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalItem {
  const _ApprovalItem({required this.type, required this.data});
  final String type;
  final Map<String, dynamic> data;
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.item, required this.busy, required this.onApprove, required this.onReject});
  final _ApprovalItem item;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final typeLabel = switch (item.type) {
      'leave' => 'Leave',
      'overtime' => 'Overtime',
      'manual' => 'Attendance correction',
      'gate_pass' => 'Gate pass',
      _ => 'Shift swap',
    };
    final name = stringValue(item.data['employee_name'], fallback: stringValue(item.data['requester_name'], fallback: 'Team member'));
    final key = stringValue(item.data['id']);
    final details = switch (item.type) {
      'leave' => '${stringValue(item.data['leave_type'])} · ${stringValue(item.data['start_date'])} – ${stringValue(item.data['end_date'])}',
      'overtime' => '${stringValue(item.data['work_date'])} · ${stringValue(item.data['hours'])} hours',
      'manual' => '${stringValue(item.data['work_date'])} · ${stringValue(item.data['requested_punch_in'])}',
      'gate_pass' => '${stringValue(item.data['pass_type']).replaceAll('_', ' ')} · ${stringValue(item.data['valid_from'])}',
      _ => '${stringValue(item.data['requester_name'])} ⇄ ${stringValue(item.data['target_name'])} · ${stringValue(item.data['work_date'])}',
    };
    final reason = stringValue(item.data['reason'], fallback: stringValue(item.data['purpose'], fallback: 'No additional details provided.'));
    return AppPanel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(13)), child: Icon(_icon(item.type), color: AppColors.blue, size: 19)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 4),
            Text('$typeLabel  ·  $details', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: AppColors.softAmber, borderRadius: BorderRadius.circular(20)), child: Text('#$key', style: const TextStyle(color: Color(0xFF9A6A14), fontSize: 9, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 12),
        Text(reason, style: const TextStyle(color: AppColors.ink, fontSize: 11, height: 1.4)),
        if (item.type == 'shift_swap') ...[
          const SizedBox(height: 7),
          Text('${stringValue(item.data['requester_shift_name'])} (${stringValue(item.data['requester_start_time'])}–${stringValue(item.data['requester_end_time'])})  ⇄  ${stringValue(item.data['target_shift_name'])} (${stringValue(item.data['target_start_time'])}–${stringValue(item.data['target_end_time'])})', style: const TextStyle(color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: busy ? null : onReject, child: const Text('Reject'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton.icon(onPressed: busy ? null : onApprove, icon: busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_rounded, size: 17), label: const Text('Approve'))),
        ]),
      ]),
    );
  }

  IconData _icon(String type) => switch (type) {
        'leave' => Icons.event_note_outlined,
        'overtime' => Icons.more_time_rounded,
        'manual' => Icons.edit_calendar_outlined,
        'gate_pass' => Icons.badge_outlined,
        _ => Icons.swap_horiz_rounded,
      };
}
