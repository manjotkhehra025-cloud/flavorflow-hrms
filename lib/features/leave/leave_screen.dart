import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key});

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  List<Map<String, dynamic>> _requests = const [];
  List<Map<String, dynamic>> _types = const [];
  bool _loading = true;
  String? _error;

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
      final api = AppScope.of(context).api;
      final responses = await Future.wait([api.get('leave-requests'), api.get('leave-types')]);
      if (!mounted) return;
      setState(() {
        _requests = asJsonList(asJsonMap(responses[0])['items']);
        _types = asJsonList(asJsonMap(responses[1])['items']);
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newRequest() async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _LeaveFormDialog(types: _types),
    );
    if (values == null || !mounted) return;
    try {
      await AppScope.of(context).api.post('leave-requests', values);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leave request submitted.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = AppScope.of(context).user!.can('leave.create');
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1210),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeading(
                  title: 'Leave',
                  subtitle: 'Plan time away and stay up to date on each decision.',
                  trailing: canCreate ? PrimaryButton(label: 'Request leave', icon: Icons.add_rounded, onPressed: _newRequest) : null,
                ),
                Container(
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(color: AppColors.softGreen, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFD4F0E3))),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.event_available_rounded, color: AppColors.success, size: 20), SizedBox(width: 11), Expanded(child: Text('Your leave history is visible here. Requests are routed to an eligible manager or HR approver based on your reporting line and their database-backed role permissions.', style: TextStyle(color: AppColors.ink, fontSize: 12, height: 1.5)))]),
                ),
                const SizedBox(height: 18),
                if (_loading && _requests.isEmpty)
                  const SizedBox(height: 180, child: LoadingView(label: 'Loading leave requests…'))
                else if (_error != null && _requests.isEmpty)
                  ErrorNotice(message: _error!, onRetry: _load)
                else if (_requests.isEmpty)
                  const AppPanel(child: EmptyNotice(title: 'No leave requests yet', subtitle: 'When a request is submitted, its status will appear here.', icon: Icons.event_note_outlined))
                else
                  AppPanel(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    child: Column(children: _requests.map((request) => _LeaveRequestRow(request: request, showEmployee: AppScope.of(context).user!.canAny(const ['leave.read', 'leave.read.team', 'leave.manage']))).toList()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LeaveRequestRow extends StatelessWidget {
  const _LeaveRequestRow({required this.request, required this.showEmployee});
  final Map<String, dynamic> request;
  final bool showEmployee;

  @override
  Widget build(BuildContext context) {
    final range = '${formatDate(request['start_date'])} – ${formatDate(request['end_date'])}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.event_note_rounded, color: AppColors.blue, size: 20)),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(stringValue(request['leave_type'], fallback: 'Leave request'), style: const TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(showEmployee ? '${stringValue(request['employee_name'])} · $range' : range, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11))])),
        if (MediaQuery.sizeOf(context).width > 730) Expanded(flex: 2, child: Text(stringValue(request['reason']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11))),
        const SizedBox(width: 10),
        StatusBadge(status: stringValue(request['status'], fallback: 'pending')),
      ]),
    );
  }
}

class _LeaveFormDialog extends StatefulWidget {
  const _LeaveFormDialog({required this.types});
  final List<Map<String, dynamic>> types;

  @override
  State<_LeaveFormDialog> createState() => _LeaveFormDialogState();
}

class _LeaveFormDialogState extends State<_LeaveFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  int? _typeId;
  DateTime? _start;
  DateTime? _end;
  bool _datesInvalid = false;

  @override
  void initState() {
    super.initState();
    if (widget.types.isNotEmpty) _typeId = int.tryParse(stringValue(widget.types.first['id']));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final today = DateTime.now();
    final initial = (start ? _start : _end) ?? _start ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(today) ? today : initial,
      firstDate: today,
      lastDate: DateTime(today.year + 3),
      builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.blue)), child: child!),
    );
    if (picked != null) setState(() { if (start) { _start = picked; if (_end != null && _end!.isBefore(picked)) _end = picked; } else { _end = picked; } _datesInvalid = false; });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_start == null || _end == null || _typeId == null) {
      setState(() => _datesInvalid = true);
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'leave_type_id': _typeId,
      'start_date': _dateString(_start!),
      'end_date': _dateString(_end!),
      'reason': _reason.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
      title: const Text('Request leave', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 450,
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              value: _typeId,
              decoration: const InputDecoration(labelText: 'Leave type'),
              items: widget.types.map((type) => DropdownMenuItem(value: int.tryParse(stringValue(type['id'])), child: Text(stringValue(type['name'])))).toList(),
              onChanged: (value) => setState(() => _typeId = value),
              validator: (value) => value == null ? 'Choose a leave type' : null,
            ),
            const SizedBox(height: 12),
            Row(children: [Expanded(child: _DatePickerField(label: 'From', value: _start, onTap: () => _pickDate(start: true))), const SizedBox(width: 12), Expanded(child: _DatePickerField(label: 'To', value: _end, onTap: () => _pickDate(start: false)))]),
            if (_datesInvalid) const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(top: 6), child: Text('Choose a start and end date.', style: TextStyle(color: Color(0xFFC94D54), fontSize: 11)))),
            const SizedBox(height: 12),
            TextFormField(controller: _reason, minLines: 3, maxLines: 4, decoration: const InputDecoration(labelText: 'Reason', hintText: 'Add a little context for your approver'), validator: (value) => (value?.trim().isEmpty ?? true) ? 'A reason is required' : null),
            if (widget.types.isEmpty) const Padding(padding: EdgeInsets.only(top: 10), child: Text('No active leave types are available.', style: TextStyle(color: Color(0xFFC94D54), fontSize: 12))),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton.icon(onPressed: widget.types.isEmpty ? null : _submit, icon: const Icon(Icons.send_rounded, size: 17), label: const Text('Submit request'))],
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({required this.label, required this.value, required this.onTap});
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_month_outlined, size: 19)),
        child: Text(value == null ? 'Select date' : _dateString(value!), style: TextStyle(color: value == null ? AppColors.muted : AppColors.ink, fontSize: 13)),
      ),
    );
  }
}

String _dateString(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
