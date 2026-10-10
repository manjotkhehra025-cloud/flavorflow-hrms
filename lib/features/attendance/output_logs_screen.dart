import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class OutputLogsScreen extends StatefulWidget {
  const OutputLogsScreen({super.key});

  @override
  State<OutputLogsScreen> createState() => _OutputLogsScreenState();
}

class _OutputLogsScreenState extends State<OutputLogsScreen> {
  List<Map<String, dynamic>> _logs = const [];
  List<Map<String, dynamic>> _employees = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _canManage => AppScope.of(context).user!.can('output.manage');

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
      final responses = await Future.wait<dynamic>([
        api.get('output-logs', query: {'limit': '200'}),
        _canManage ? api.get('employees') : Future<dynamic>.value(const <String, dynamic>{}),
      ]);
      if (!mounted) return;
      setState(() {
        _logs = asJsonList(asJsonMap(responses[0])['items']);
        _employees = asJsonList(asJsonMap(responses[1])['items']);
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addLog() async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _OutputLogDialog(employees: _canManage ? _employees : const []),
    );
    if (values == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await AppScope.of(context).api.post('output-logs', values);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Output log saved.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user!;
    final canCreate = user.canAny(const ['output.create.self', 'output.manage']);
    final totalQuantity = _logs.fold<double>(0, (sum, row) => sum + (double.tryParse(stringValue(row['quantity'])) ?? 0));
    final totalTarget = _logs.fold<double>(0, (sum, row) => sum + (double.tryParse(stringValue(row['target_quantity'])) ?? 0));
    final attainment = totalTarget > 0 ? (totalQuantity / totalTarget).clamp(0.0, 1.0) : 0.0;

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1060),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PageHeading(
                title: 'Output Logs',
                subtitle: 'Record daily production output alongside shift attendance.',
                trailing: canCreate ? PrimaryButton(label: _saving ? 'Saving…' : 'Add output log', icon: Icons.add_rounded, busy: _saving, onPressed: _saving ? null : _addLog) : null,
              ),
              if (_error != null) ...[
                ErrorNotice(message: _error!, onRetry: _load),
                const SizedBox(height: 13),
              ],
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(15)),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.insights_outlined, color: AppColors.blue, size: 19), SizedBox(width: 9), Expanded(child: Text('Yellow Card staff performance is tracked through shifts, attendance, and output logs—not Official Staff KRA/appraisals. Managers can view reporting-team entries; employees can add their own daily logs.', style: TextStyle(color: AppColors.ink, fontSize: 11, height: 1.45)))]),
              ),
              const SizedBox(height: 15),
              AppPanel(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(child: _OutputMetric(title: 'Output quantity', value: _format(totalQuantity), icon: Icons.inventory_2_outlined, tint: AppColors.blue)),
                  const SizedBox(width: 12),
                  Expanded(child: _OutputMetric(title: 'Target progress', value: totalTarget > 0 ? '${(attainment * 100).round()}%' : '—', icon: Icons.track_changes_rounded, tint: AppColors.success)),
                  const SizedBox(width: 12),
                  Expanded(child: _OutputMetric(title: 'Logs', value: '${_logs.length}', icon: Icons.receipt_long_outlined, tint: const Color(0xFFB77A1C))),
                ]),
              ),
              const SizedBox(height: 15),
              AppPanel(
                padding: const EdgeInsets.all(17),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [const Expanded(child: Text('Production output history', style: TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w800))), Text('${_logs.length} entries', style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700))]),
                  const SizedBox(height: 4),
                  const Text('Entries are auditable and scoped to your role.', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                  const SizedBox(height: 12),
                  if (_loading && _logs.isEmpty)
                    const SizedBox(height: 130, child: LoadingView(label: 'Loading output logs…'))
                  else if (_logs.isEmpty)
                    const EmptyNotice(title: 'No output logs yet', subtitle: 'Add a daily item, quantity, unit, and optional target.', icon: Icons.inventory_2_outlined)
                  else
                    ..._logs.map((log) => _OutputLogRow(log: log)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _OutputMetric extends StatelessWidget {
  const _OutputMetric({required this.title, required this.value, required this.icon, required this.tint});
  final String title;
  final String value;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 35, height: 35, decoration: BoxDecoration(color: tint.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: tint, size: 18)),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 9, fontWeight: FontWeight.w600)), const SizedBox(height: 3), Text(value, style: const TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w800))])),
      ]);
}

class _OutputLogRow extends StatelessWidget {
  const _OutputLogRow({required this.log});
  final Map<String, dynamic> log;

  @override
  Widget build(BuildContext context) {
    final target = double.tryParse(stringValue(log['target_quantity']));
    final quantity = double.tryParse(stringValue(log['quantity'])) ?? 0;
    final progress = target != null && target > 0 ? (quantity / target).clamp(0.0, 1.0).toDouble() : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(width: 37, height: 37, decoration: BoxDecoration(color: AppColors.softGreen, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.precision_manufacturing_outlined, color: AppColors.success, size: 18)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${stringValue(log['output_item'])} · ${_format(quantity)} ${stringValue(log['unit'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text('${stringValue(log['employee_name'], fallback: 'Employee')} · ${stringValue(log['work_date'])}${target == null ? '' : ' · target ${_format(target)}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
          if (progress != null) ...[
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: progress, minHeight: 5, backgroundColor: AppColors.line, color: AppColors.teal)),
          ],
          if (stringValue(log['notes']).isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(stringValue(log['notes']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
          ],
        ])),
      ]),
    );
  }
}

class _OutputLogDialog extends StatefulWidget {
  const _OutputLogDialog({required this.employees});
  final List<Map<String, dynamic>> employees;
  @override
  State<_OutputLogDialog> createState() => _OutputLogDialogState();
}

class _OutputLogDialogState extends State<_OutputLogDialog> {
  final _item = TextEditingController();
  final _quantity = TextEditingController();
  final _unit = TextEditingController(text: 'units');
  final _target = TextEditingController();
  final _notes = TextEditingController();
  final _workDate = TextEditingController(text: _today());
  int? _employeeId;

  @override
  void initState() { super.initState(); if (widget.employees.isNotEmpty) _employeeId = int.tryParse(stringValue(widget.employees.first['id'])); }
  @override
  void dispose() { _item.dispose(); _quantity.dispose(); _unit.dispose(); _target.dispose(); _notes.dispose(); _workDate.dispose(); super.dispose(); }

  void _save() {
    final quantity = double.tryParse(_quantity.text.trim());
    final target = _target.text.trim().isEmpty ? null : double.tryParse(_target.text.trim());
    if (_item.text.trim().isEmpty || quantity == null || quantity <= 0 || _unit.text.trim().isEmpty || DateTime.tryParse(_workDate.text.trim()) == null || (_target.text.trim().isNotEmpty && target == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a date, item, positive quantity, unit, and valid optional target.')));
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'work_date': _workDate.text.trim(),
      'output_item': _item.text.trim(),
      'quantity': quantity,
      'unit': _unit.text.trim(),
      if (target != null) 'target_quantity': target,
      'notes': _notes.text.trim(),
      if (widget.employees.isNotEmpty && _employeeId != null) 'employee_id': _employeeId,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Add output log', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
        content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.employees.isNotEmpty)
            DropdownButtonFormField<int>(value: _employeeId, decoration: const InputDecoration(labelText: 'Employee'), items: widget.employees.where((employee) => stringValue(employee['status']) == 'active').map((employee) => DropdownMenuItem(value: int.tryParse(stringValue(employee['id'])), child: Text('${stringValue(employee['full_name'])} · ${stringValue(employee['employee_code'])}'))).toList(), onChanged: (value) => setState(() => _employeeId = value)),
          TextField(controller: _workDate, keyboardType: TextInputType.datetime, decoration: const InputDecoration(labelText: 'Work date (YYYY-MM-DD)')),
          const SizedBox(height: 10),
          TextField(controller: _item, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Output item / product')),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: TextField(controller: _quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], decoration: const InputDecoration(labelText: 'Quantity'))), const SizedBox(width: 10), Expanded(child: TextField(controller: _unit, decoration: const InputDecoration(labelText: 'Unit')))]),
          const SizedBox(height: 10),
          TextField(controller: _target, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], decoration: const InputDecoration(labelText: 'Target quantity (optional)')),
          const SizedBox(height: 10),
          TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)')),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.check_rounded, size: 17), label: const Text('Save log'))],
      );
}

String _format(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
String _today() { final now = DateTime.now(); return '${now.year.toString().padLeft(4, "0")}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")}'; }
