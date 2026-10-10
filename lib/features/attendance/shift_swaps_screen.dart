import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class ShiftSwapsScreen extends StatefulWidget {
  const ShiftSwapsScreen({super.key});

  @override
  State<ShiftSwapsScreen> createState() => _ShiftSwapsScreenState();
}

class _ShiftSwapsScreenState extends State<ShiftSwapsScreen> {
  List<Map<String, dynamic>> _requests = const [];
  List<Map<String, dynamic>> _options = const [];
  DateTime _windowStart = _today();
  bool _loading = true;
  String? _error;
  String _filter = 'all';

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
      final end = _windowStart.add(const Duration(days: 29));
      final results = await Future.wait<dynamic>([
        api.get('shift-swap-requests'),
        api.get('shift-swap-options', query: {
          'from': _dateKey(_windowStart),
          'to': _dateKey(end),
        }),
      ]);
      if (!mounted) return;
      final requests = asJsonList(asJsonMap(results[0])['items']);
      setState(() {
        _requests = requests;
        _options = asJsonList(asJsonMap(results[1])['items']);
      });
      if (user.employeeId == null) {
        setState(() => _error = 'Your account is not linked to an employee profile, so it cannot request a swap.');
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeWindow(int offset) async {
    var next = _windowStart.add(Duration(days: offset * 30));
    final today = _today();
    if (next.isBefore(today)) next = today;
    final latestStart = today.add(const Duration(days: 61));
    if (next.isAfter(latestStart)) next = latestStart;
    if (next == _windowStart) return;
    setState(() => _windowStart = next);
    await _load();
  }

  Future<void> _newRequest() async {
    final employeeId = AppScope.of(context).user!.employeeId;
    if (employeeId == null) {
      _showMessage('Your account must be linked to an employee profile before requesting a swap.');
      return;
    }
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _SwapRequestDialog(options: _options, ownEmployeeId: employeeId),
    );
    if (values == null || !mounted) return;
    try {
      await AppScope.of(context).api.post('shift-swap-requests', values);
      if (!mounted) return;
      _showMessage('Swap request sent to your colleague for consent.');
      await _load();
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _act(Map<String, dynamic> request, String action) async {
    final id = stringValue(request['id']);
    String path;
    Map<String, dynamic> body;
    if (action == 'accept' || action == 'decline') {
      path = 'shift-swap-requests/$id/target-decision';
      body = {'decision': action == 'accept' ? 'accept' : 'reject'};
    } else if (action == 'approve' || action == 'reject') {
      path = 'shift-swap-requests/$id/decision';
      body = {'decision': action};
    } else {
      path = 'shift-swap-requests/$id/cancel';
      body = const <String, dynamic>{};
    }
    try {
      await AppScope.of(context).api.post(path, body);
      if (!mounted) return;
      final message = switch (action) {
        'accept' => 'Swap accepted and sent to the manager for approval.',
        'decline' => 'Swap request declined.',
        'approve' => 'Shift swap approved.',
        'reject' => 'Shift swap rejected.',
        _ => 'Swap request cancelled.',
      };
      _showMessage(message);
      await _load();
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user!;
    final canApprove = user.canAny(const ['shifts.swap.approve', 'shifts.manage']);
    final requests = _requests.where((request) => _filter == 'all' || request['status'] == _filter).toList();
    final end = _windowStart.add(const Duration(days: 29));
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
                  title: 'Shift swaps',
                  subtitle: 'Request a peer exchange, then route it through colleague consent and manager approval.',
                  trailing: FilledButton.icon(
                    onPressed: _newRequest,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Request swap'),
                  ),
                ),
                AppPanel(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    const Icon(Icons.calendar_month_outlined, color: AppColors.blue, size: 19),
                    const SizedBox(width: 9),
                    Expanded(child: Text('Available shifts · ${_dateLabel(_windowStart)} – ${_dateLabel(end)}', style: const TextStyle(color: AppColors.ink, fontSize: 11, fontWeight: FontWeight.w700))),
                    IconButton(onPressed: () => _changeWindow(-1), tooltip: 'Previous 30 days', icon: const Icon(Icons.chevron_left_rounded)),
                    IconButton(onPressed: () => _changeWindow(1), tooltip: 'Next 30 days', icon: const Icon(Icons.chevron_right_rounded)),
                  ]),
                ),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _SwapFilter(label: 'All', selected: _filter == 'all', onTap: () => _setFilter('all')),
                  _SwapFilter(label: 'Needs consent', selected: _filter == 'pending_target', onTap: () => _setFilter('pending_target')),
                  _SwapFilter(label: 'Needs manager', selected: _filter == 'pending_manager', onTap: () => _setFilter('pending_manager')),
                  _SwapFilter(label: 'Completed', selected: _filter == 'approved', onTap: () => _setFilter('approved')),
                ]),
                const SizedBox(height: 13),
                if (_error != null) ErrorNotice(message: _error!, onRetry: _load)
                else if (_loading && _requests.isEmpty)
                  const SizedBox(height: 220, child: LoadingView(label: 'Loading shift swaps…'))
                else if (requests.isEmpty)
                  const AppPanel(child: EmptyNotice(
                    title: 'No shift swaps to show',
                    subtitle: 'Eligible future shifts and swap requests will appear here.',
                    icon: Icons.swap_horiz_rounded,
                  ))
                else
                  ...requests.map((request) => Padding(
                        padding: const EdgeInsets.only(bottom: 11),
                        child: _SwapRequestCard(
                          request: request,
                          ownEmployeeId: user.employeeId,
                          canApprove: canApprove && (user.can('shifts.manage') || (user.employeeId != int.tryParse(stringValue(request['requester_employee_id'])) && user.employeeId != int.tryParse(stringValue(request['target_employee_id'])))),
                          onAction: (action) => _act(request, action),
                        ),
                      )),
                if (_loading && _requests.isNotEmpty)
                  const Padding(padding: EdgeInsets.all(14), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setFilter(String value) async {
    if (_filter == value) return;
    setState(() => _filter = value);
  }
}

class _SwapRequestCard extends StatelessWidget {
  const _SwapRequestCard({required this.request, required this.ownEmployeeId, required this.canApprove, required this.onAction});
  final Map<String, dynamic> request;
  final int? ownEmployeeId;
  final bool canApprove;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final requesterId = int.tryParse(stringValue(request['requester_employee_id']));
    final targetId = int.tryParse(stringValue(request['target_employee_id']));
    final isRequester = requesterId == ownEmployeeId;
    final isTarget = targetId == ownEmployeeId;
    final status = stringValue(request['status'], fallback: 'pending_target');
    final date = _dateLabel(DateTime.tryParse(stringValue(request['work_date'])) ?? DateTime.now());
    return AppPanel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.swap_horiz_rounded, color: AppColors.blue)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${stringValue(request['requester_name'])}  ⇄  ${stringValue(request['target_name'])}', style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(date, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
          ])),
          _SwapStatusPill(status: status),
        ]),
        const SizedBox(height: 13),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _ShiftSummary(label: stringValue(request['requester_name']), name: stringValue(request['requester_shift_name']), start: stringValue(request['requester_start_time']), end: stringValue(request['requester_end_time']))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12), child: Icon(Icons.swap_horiz_rounded, color: AppColors.teal, size: 20)),
          Expanded(child: _ShiftSummary(label: stringValue(request['target_name']), name: stringValue(request['target_shift_name']), start: stringValue(request['target_start_time']), end: stringValue(request['target_end_time']))),
        ]),
        const SizedBox(height: 10),
        Text(stringValue(request['reason']), style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
        if (status == 'pending_target' && isTarget) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => onAction('decline'), child: const Text('Decline'))),
            const SizedBox(width: 9),
            Expanded(child: FilledButton(onPressed: () => onAction('accept'), child: const Text('Accept swap'))),
          ]),
        ] else if (status == 'pending_manager' && canApprove) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => onAction('reject'), child: const Text('Reject'))),
            const SizedBox(width: 9),
            Expanded(child: FilledButton(onPressed: () => onAction('approve'), child: const Text('Approve'))),
          ]),
        ] else if (status == 'pending_target' && isRequester || status == 'pending_manager' && isRequester) ...[
          const SizedBox(height: 9),
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => onAction('cancel'), child: const Text('Cancel request'))),
        ],
      ]),
    );
  }
}

class _ShiftSummary extends StatelessWidget {
  const _ShiftSummary({required this.label, required this.name, required this.start, required this.end});
  final String label;
  final String name;
  final String start;
  final String end;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 9, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.ink, fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text('$start – $end', style: const TextStyle(color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _SwapStatusPill extends StatelessWidget {
  const _SwapStatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'approved' => AppColors.success,
      'pending_manager' => const Color(0xFFB57814),
      'rejected' || 'cancelled' => const Color(0xFFCA4B50),
      _ => AppColors.blue,
    };
    final label = switch (status) {
      'pending_target' => 'Needs consent',
      'pending_manager' => 'Needs manager',
      _ => status.replaceAll('_', ' '),
    };
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(30)), child: Text(label.toUpperCase(), style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w800)));
  }
}

class _SwapFilter extends StatelessWidget {
  const _SwapFilter({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label), selected: selected, onSelected: (_) => onTap(),
        selectedColor: AppColors.softBlue,
        labelStyle: TextStyle(color: selected ? AppColors.blue : AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700),
        side: BorderSide(color: selected ? AppColors.blue.withValues(alpha: 0.25) : AppColors.line),
      );
}

class _SwapRequestDialog extends StatefulWidget {
  const _SwapRequestDialog({required this.options, required this.ownEmployeeId});
  final List<Map<String, dynamic>> options;
  final int ownEmployeeId;

  @override
  State<_SwapRequestDialog> createState() => _SwapRequestDialogState();
}

class _SwapRequestDialogState extends State<_SwapRequestDialog> {
  int? _requesterAssignmentId;
  int? _targetAssignmentId;
  final _reason = TextEditingController();

  List<Map<String, dynamic>> get _myOptions => widget.options.where((option) => int.tryParse(stringValue(option['employee_id'])) == widget.ownEmployeeId).toList();

  List<Map<String, dynamic>> get _targetOptions {
    final selected = _myOptions.where((option) => int.tryParse(stringValue(option['assignment_id'])) == _requesterAssignmentId);
    if (selected.isEmpty) return const [];
    final workDate = stringValue(selected.first['work_date']);
    return widget.options.where((option) =>
      stringValue(option['work_date']) == workDate && int.tryParse(stringValue(option['employee_id'])) != widget.ownEmployeeId
    ).toList();
  }

  @override
  void initState() {
    super.initState();
    if (_myOptions.isNotEmpty) _requesterAssignmentId = int.tryParse(stringValue(_myOptions.first['assignment_id']));
    final targets = _targetOptions;
    if (targets.isNotEmpty) _targetAssignmentId = int.tryParse(stringValue(targets.first['assignment_id']));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _optionLabel(Map<String, dynamic> option) => '${stringValue(option['employee_name'])} · ${stringValue(option['shift_name'])} · ${_dateLabel(DateTime.tryParse(stringValue(option['work_date'])) ?? DateTime.now())} (${stringValue(option['start_time'])}–${stringValue(option['end_time'])})';

  @override
  Widget build(BuildContext context) {
    final targetOptions = _targetOptions;
    final myOptions = _myOptions;
    return AlertDialog(
      title: const Text('Request a shift swap'),
      content: SizedBox(
        width: 520,
        child: myOptions.isEmpty
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('No future shifts are available for your employee profile in this date window.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)))
            : SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<int>(
                  value: _requesterAssignmentId,
                  decoration: const InputDecoration(labelText: 'Your shift'),
                  items: myOptions.map((option) => DropdownMenuItem<int>(value: int.tryParse(stringValue(option['assignment_id'])), child: Text(_optionLabel(option), maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (value) => setState(() {
                    _requesterAssignmentId = value;
                    final targets = _targetOptions;
                    _targetAssignmentId = targets.isEmpty ? null : int.tryParse(stringValue(targets.first['assignment_id']));
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: targetOptions.any((option) => int.tryParse(stringValue(option['assignment_id'])) == _targetAssignmentId) ? _targetAssignmentId : null,
                  decoration: const InputDecoration(labelText: 'Colleague shift on the same date'),
                  items: targetOptions.map((option) => DropdownMenuItem<int>(value: int.tryParse(stringValue(option['assignment_id'])), child: Text(_optionLabel(option), maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (value) => setState(() => _targetAssignmentId = value),
                ),
                const SizedBox(height: 12),
                TextField(controller: _reason, onChanged: (_) => setState(() {}), maxLength: 1000, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Reason for the swap')),
                const SizedBox(height: 4),
                const Align(alignment: Alignment.centerLeft, child: Text('The colleague must consent, then a manager must approve before schedules change.', style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.4))),
              ])),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: targetOptions.isEmpty || _requesterAssignmentId == null || _targetAssignmentId == null || _reason.text.trim().isEmpty
              ? null
              : () {
                  final target = targetOptions.firstWhere((option) => int.tryParse(stringValue(option['assignment_id'])) == _targetAssignmentId);
                  Navigator.pop(context, {
                    'target_employee_id': int.tryParse(stringValue(target['employee_id'])),
                    'requester_assignment_id': _requesterAssignmentId,
                    'target_assignment_id': _targetAssignmentId,
                    'reason': _reason.text.trim(),
                  });
                },
          child: const Text('Send request'),
        ),
      ],
    );
  }
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String _dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _dateLabel(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
