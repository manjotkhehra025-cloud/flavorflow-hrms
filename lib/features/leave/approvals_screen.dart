import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  List<Map<String, dynamic>> _requests = const [];
  bool _loading = true;
  String? _error;
  int? _deciding;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await AppScope.of(context).api.get('leave-requests', query: const {'status': 'pending'});
      if (mounted) setState(() => _requests = asJsonList(asJsonMap(response)['items']));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(Map<String, dynamic> request, String decision) async {
    final approved = decision == 'approved';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(approved ? 'Approve this request?' : 'Decline this request?', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
        content: Text('${stringValue(request['employee_name'])} · ${stringValue(request['leave_type'])}\n${formatDate(request['start_date'])} – ${formatDate(request['end_date'])}', style: const TextStyle(height: 1.5, color: AppColors.muted)),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: approved ? AppColors.success : const Color(0xFFC94D54)), child: Text(approved ? 'Approve' : 'Decline'))],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = int.tryParse(stringValue(request['id']));
    if (id == null) return;
    setState(() => _deciding = id);
    try {
      await AppScope.of(context).api.post('leave-requests/$id/decision', {'decision': decision});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approved ? 'Leave request approved.' : 'Leave request declined.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _deciding = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PageHeading(title: 'Approvals', subtitle: 'Review leave requests for your team.'),
              if (_error != null) ...[ErrorNotice(message: _error!, onRetry: _load), const SizedBox(height: 14)],
              if (_loading && _requests.isEmpty)
                const SizedBox(height: 180, child: LoadingView(label: 'Loading approval queue…'))
              else if (_requests.isEmpty)
                const AppPanel(child: EmptyNotice(title: 'Nothing waiting on you', subtitle: 'New team requests will appear in this queue.', icon: Icons.task_alt_rounded))
              else
                AppPanel(
                  padding: const EdgeInsets.all(17),
                  child: Column(children: _requests.map((request) => _ApprovalCard(request: request, busy: _deciding == int.tryParse(stringValue(request['id'])), onApprove: () => _decide(request, 'approved'), onReject: () => _decide(request, 'rejected'))).toList()),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.request, required this.busy, required this.onApprove, required this.onReject});
  final Map<String, dynamic> request;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(color: const Color(0xFFF9FBFD), borderRadius: BorderRadius.circular(17), border: Border.all(color: AppColors.line)),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 690;
        final identity = Row(children: [PersonAvatar(name: stringValue(request['employee_name'], fallback: 'Team member'), size: 43), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(stringValue(request['employee_name'], fallback: 'Team member'), style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 13)), const SizedBox(height: 4), Text('${stringValue(request['employee_code'])} · ${stringValue(request['department'], fallback: 'Team')}', style: const TextStyle(color: AppColors.muted, fontSize: 11))]))]);
        final dateAndType = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(stringValue(request['leave_type']), style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w700)), const SizedBox(height: 5), Text('${formatDate(request['start_date'])} – ${formatDate(request['end_date'])}', style: const TextStyle(color: AppColors.muted, fontSize: 11))]);
        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              onPressed: busy ? null : onReject,
              tooltip: 'Decline request',
              style: IconButton.styleFrom(backgroundColor: AppColors.softRed, foregroundColor: const Color(0xFFC94D54)),
              icon: const Icon(Icons.close_rounded),
            ),
            const SizedBox(width: 7),
            SizedBox(
              height: 42,
              child: FilledButton.icon(
                onPressed: busy ? null : onApprove,
                style: FilledButton.styleFrom(backgroundColor: AppColors.success, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_rounded, size: 17),
                label: const Text('Approve'),
              ),
            ),
          ],
        );
        if (!wide) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [identity, const SizedBox(height: 15), dateAndType, const SizedBox(height: 10), Text(stringValue(request['reason']), style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)), const SizedBox(height: 12), Align(alignment: Alignment.centerRight, child: actions)]);
        return Row(children: [Expanded(flex: 3, child: identity), const SizedBox(width: 18), Expanded(flex: 2, child: dateAndType), const SizedBox(width: 18), Expanded(flex: 3, child: Text(stringValue(request['reason']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4))), const SizedBox(width: 15), actions]);
      }),
    );
  }
}
