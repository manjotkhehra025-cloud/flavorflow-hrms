import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class HelpdeskScreen extends StatefulWidget {
  const HelpdeskScreen({super.key});

  @override
  State<HelpdeskScreen> createState() => _HelpdeskScreenState();
}

class _HelpdeskScreenState extends State<HelpdeskScreen> {
  List<Map<String, dynamic>> _tickets = const [];
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
      final query = _filter == 'all' ? null : {'status': _filter};
      final response = await AppScope.of(context).api.get('helpdesk-tickets', query: query);
      if (!mounted) return;
      setState(() => _tickets = asJsonList(asJsonMap(response)['items']));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newTicket() async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _TicketFormDialog(),
    );
    if (values == null || !mounted) return;
    try {
      final ticket = await AppScope.of(context).api.post('helpdesk-tickets', values);
      if (!mounted) return;
      setState(() => _filter = 'all');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ticket #${stringValue(asJsonMap(ticket)['id'])} submitted.')),
      );
      await _load();
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _openTicket(Map<String, dynamic> summary) async {
    try {
      final response = await AppScope.of(context).api.get('helpdesk-tickets/${summary['id']}');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _TicketDetailDialog(
          ticket: asJsonMap(response),
          canManage: AppScope.of(context).user!.can('helpdesk.manage'),
        ),
      );
      if (mounted) await _load();
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
    final canManage = user.can('helpdesk.manage');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1050),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeading(
                    title: canManage ? 'Helpdesk' : 'Help & support',
                    subtitle: canManage
                        ? 'Review support requests and confidential grievances.'
                        : 'Raise a support request or submit a confidential grievance.',
                    trailing: FilledButton.icon(
                      onPressed: _newTicket,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New ticket'),
                    ),
                  ),
                  if (!canManage)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: AppPanel(
                        padding: EdgeInsets.all(14),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.lock_outline_rounded, color: AppColors.blue, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Grievances are confidential. Only you and People Ops / HR Admin can view them; line managers are excluded.',
                              style: TextStyle(color: AppColors.ink, fontSize: 12, height: 1.45),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterChip(label: 'All', selected: _filter == 'all', onTap: () => _setFilter('all')),
                      _FilterChip(label: 'Open', selected: _filter == 'open', onTap: () => _setFilter('open')),
                      _FilterChip(label: 'In progress', selected: _filter == 'in_progress', onTap: () => _setFilter('in_progress')),
                      _FilterChip(label: 'Resolved', selected: _filter == 'resolved', onTap: () => _setFilter('resolved')),
                      _FilterChip(label: 'Closed', selected: _filter == 'closed', onTap: () => _setFilter('closed')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_error != null) ErrorNotice(message: _error!, onRetry: _load)
                  else if (_loading && _tickets.isEmpty)
                    const SizedBox(height: 220, child: LoadingView(label: 'Loading helpdesk tickets…'))
                  else if (_tickets.isEmpty)
                    AppPanel(
                      child: EmptyNotice(
                        title: canManage ? 'No tickets in this queue' : 'No tickets yet',
                        subtitle: canManage ? 'New employee requests will appear here.' : 'Create a ticket and the support team will follow up.',
                        icon: Icons.support_agent_rounded,
                      ),
                    )
                  else
                    ..._tickets.map((ticket) => Padding(
                          padding: const EdgeInsets.only(bottom: 11),
                          child: _TicketCard(ticket: ticket, canManage: canManage, onTap: () => _openTicket(ticket)),
                        )),
                  if (_loading && _tickets.isNotEmpty)
                    const Padding(padding: EdgeInsets.all(14), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setFilter(String value) async {
    if (_filter == value) return;
    setState(() => _filter = value);
    await _load();
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.softBlue,
        labelStyle: TextStyle(color: selected ? AppColors.blue : AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700),
        side: BorderSide(color: selected ? AppColors.blue.withValues(alpha: 0.25) : AppColors.line),
      );
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.canManage, required this.onTap});
  final Map<String, dynamic> ticket;
  final bool canManage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = stringValue(ticket['status'], fallback: 'open');
    final subject = stringValue(ticket['title'], fallback: 'Support request');
    final name = stringValue(ticket['requester_name'], fallback: 'Team member');
    final confidential = ticket['is_confidential'] == true || ticket['is_confidential'] == 1;
    return AppPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 13, 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: confidential ? AppColors.softAmber : AppColors.softBlue, borderRadius: BorderRadius.circular(13)),
            child: Icon(confidential ? Icons.lock_outline_rounded : Icons.support_agent_rounded, color: confidential ? const Color(0xFFB57814) : AppColors.blue, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w800))),
                _StatusPill(status: status),
              ]),
              const SizedBox(height: 5),
              Text('${_categoryLabel(stringValue(ticket['category']))} · ${stringValue(ticket['priority'], fallback: 'normal').toUpperCase()} priority', style: const TextStyle(color: AppColors.muted, fontSize: 10)),
              const SizedBox(height: 6),
              Text(stringValue(ticket['description']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.ink, fontSize: 11, height: 1.4)),
              const SizedBox(height: 8),
              Row(children: [
                if (canManage) ...[PersonAvatar(name: name, size: 22), const SizedBox(width: 6), Text(name, style: const TextStyle(color: AppColors.muted, fontSize: 10)), const SizedBox(width: 9)],
                Text('Ticket #${stringValue(ticket['id'])}', style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                const Spacer(),
                if (confidential) const Icon(Icons.lock_rounded, size: 13, color: Color(0xFFB57814)),
                const SizedBox(width: 6),
                Text(_dateLabel(stringValue(ticket['created_at'])), style: const TextStyle(color: AppColors.muted, fontSize: 10)),
              ]),
            ]),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 20),
        ]),
      ),
    );
  }
}

class _TicketFormDialog extends StatefulWidget {
  const _TicketFormDialog();

  @override
  State<_TicketFormDialog> createState() => _TicketFormDialogState();
}

class _TicketFormDialogState extends State<_TicketFormDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _category = 'other';
  String _priority = 'normal';
  bool _confidential = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('New helpdesk ticket'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: const [
                  DropdownMenuItem(value: 'payroll', child: Text('Payroll')),
                  DropdownMenuItem(value: 'attendance', child: Text('Attendance')),
                  DropdownMenuItem(value: 'leave', child: Text('Leave')),
                  DropdownMenuItem(value: 'shift', child: Text('Shift roster')),
                  DropdownMenuItem(value: 'workplace', child: Text('Workplace')),
                  DropdownMenuItem(value: 'grievance', child: Text('Confidential grievance')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (value) => setState(() {
                  _category = value ?? 'other';
                  if (_category == 'grievance') _confidential = true;
                }),
              ),
              const SizedBox(height: 12),
              TextField(controller: _title, maxLength: 160, decoration: const InputDecoration(labelText: 'Subject')),
              const SizedBox(height: 12),
              TextField(controller: _description, maxLength: 5000, minLines: 4, maxLines: 7, decoration: const InputDecoration(labelText: 'Details')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Low')),
                  DropdownMenuItem(value: 'normal', child: Text('Normal')),
                  DropdownMenuItem(value: 'high', child: Text('High')),
                ],
                onChanged: (value) => setState(() => _priority = value ?? 'normal'),
              ),
              if (_category != 'grievance')
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _confidential,
                  onChanged: (value) => setState(() => _confidential = value ?? false),
                  title: const Text('Keep this ticket confidential', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Only you and People Ops / HR Admin can see it.', style: TextStyle(fontSize: 10)),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final title = _title.text.trim();
              final description = _description.text.trim();
              if (title.isEmpty || description.isEmpty) return;
              Navigator.pop(context, {
                'category': _category,
                'title': title,
                'description': description,
                'priority': _priority,
                'is_confidential': _confidential || _category == 'grievance',
              });
            },
            child: const Text('Submit ticket'),
          ),
        ],
      );
}

class _TicketDetailDialog extends StatefulWidget {
  const _TicketDetailDialog({required this.ticket, required this.canManage});
  final Map<String, dynamic> ticket;
  final bool canManage;

  @override
  State<_TicketDetailDialog> createState() => _TicketDetailDialogState();
}

class _TicketDetailDialogState extends State<_TicketDetailDialog> {
  late Map<String, dynamic> _ticket;
  final _comment = TextEditingController();
  bool _internal = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket;
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final response = await AppScope.of(context).api.post(
        'helpdesk-tickets/${_ticket['id']}/comments',
        {'body': text, 'is_internal': widget.canManage && _internal},
      );
      if (!mounted) return;
      setState(() {
        _ticket = asJsonMap(response);
        _comment.clear();
      });
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeStatus(String? status) async {
    if (status == null) return;
    setState(() => _busy = true);
    try {
      final response = await AppScope.of(context).api.patch(
        'helpdesk-tickets/${_ticket['id']}',
        {'status': status},
      );
      if (mounted) setState(() => _ticket = asJsonMap(response));
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = asJsonList(_ticket['comments']);
    final status = stringValue(_ticket['status'], fallback: 'open');
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      title: Row(children: [
        Expanded(child: Text(stringValue(_ticket['title']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        if (_ticket['is_confidential'] == true || _ticket['is_confidential'] == 1) const Icon(Icons.lock_outline_rounded, color: Color(0xFFB57814), size: 18),
      ]),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _StatusPill(status: status),
              const SizedBox(width: 8),
              Text('${_categoryLabel(stringValue(_ticket['category']))} · ${stringValue(_ticket['priority']).toUpperCase()}', style: const TextStyle(color: AppColors.muted, fontSize: 10)),
            ]),
            const SizedBox(height: 14),
            Text(stringValue(_ticket['description']), style: const TextStyle(color: AppColors.ink, fontSize: 12, height: 1.5)),
            if (widget.canManage) ...[
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                value: status,
                decoration: const InputDecoration(labelText: 'Ticket status'),
                items: const [
                  DropdownMenuItem(value: 'open', child: Text('Open')),
                  DropdownMenuItem(value: 'in_progress', child: Text('In progress')),
                  DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                  DropdownMenuItem(value: 'closed', child: Text('Closed')),
                ],
                onChanged: _busy ? null : _changeStatus,
              ),
            ],
            const Divider(height: 27),
            const Text('Conversation', style: TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (comments.isEmpty)
              const Text('No replies yet.', style: TextStyle(color: AppColors.muted, fontSize: 11))
            else
              ...comments.map((comment) => Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: comment['is_internal'] == 1 || comment['is_internal'] == true ? AppColors.softAmber : AppColors.canvas,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(stringValue(comment['author_name'], fallback: 'Support'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10, color: AppColors.ink))),
                        if (comment['is_internal'] == 1 || comment['is_internal'] == true) const Text('INTERNAL', style: TextStyle(color: Color(0xFF9E6A13), fontSize: 8, fontWeight: FontWeight.w800)),
                      ]),
                      const SizedBox(height: 4),
                      Text(stringValue(comment['body']), style: const TextStyle(color: AppColors.ink, fontSize: 11, height: 1.4)),
                    ]),
                  )),
            const SizedBox(height: 6),
            TextField(controller: _comment, maxLength: 2000, minLines: 2, maxLines: 4, decoration: const InputDecoration(hintText: 'Write a reply…')),
            if (widget.canManage)
              CheckboxListTile(
                value: _internal,
                onChanged: _busy ? null : (value) => setState(() => _internal = value ?? false),
                title: const Text('Internal note (not visible to the employee)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton.icon(
          onPressed: _busy ? null : _sendComment,
          icon: _busy ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded, size: 16),
          label: const Text('Reply'),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'resolved' || 'closed' || 'approved' => AppColors.success,
      'in_progress' || 'pending_manager' => const Color(0xFFB57814),
      'rejected' || 'cancelled' => const Color(0xFFCA4B50),
      _ => AppColors.blue,
    };
    final label = status.replaceAll('_', ' ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(30)),
      child: Text(label.toUpperCase(), style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
    );
  }
}

String _categoryLabel(String value) => switch (value) {
      'payroll' => 'Payroll',
      'attendance' => 'Attendance',
      'leave' => 'Leave',
      'shift' => 'Shift roster',
      'workplace' => 'Workplace',
      'grievance' => 'Grievance',
      _ => 'Other',
    };

String _dateLabel(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return '';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
