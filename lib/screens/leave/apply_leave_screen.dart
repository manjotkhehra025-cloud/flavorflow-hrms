import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/leave.dart';
import '../../providers/auth_provider.dart';
import '../../providers/leave_provider.dart';
import '../../widgets/common.dart';

class ApplyLeaveScreen extends StatefulWidget {
  const ApplyLeaveScreen({super.key});

  @override
  State<ApplyLeaveScreen> createState() => _ApplyLeaveScreenState();
}

class _ApplyLeaveScreenState extends State<ApplyLeaveScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonCtrl = TextEditingController();
  LeaveType _type = LeaveType.casual;
  DateTimeRange? _range;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month - 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range,
      helpText: 'Select leave dates',
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_range == null) {
      showSnack(context, 'Please select leave dates', error: true);
      return;
    }
    final user = context.read<AuthProvider>().user!;
    final error = await context.read<LeaveProvider>().apply(
          employeeId: user.id,
          employeeName: user.name,
          type: _type,
          from: _range!.start,
          to: _range!.end,
          reason: _reasonCtrl.text,
        );
    if (!mounted) return;
    if (error != null) {
      showSnack(context, error, error: true);
    } else {
      showSnack(context, 'Leave request submitted');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final leave = context.watch<LeaveProvider>();
    LeaveBalance? balance;
    for (final b in leave.balances) {
      if (b.type == _type) balance = b;
    }
    final days = _range == null ? 0 : countLeaveDays(_range!.start, _range!.end);

    return Scaffold(
      appBar: AppBar(title: const Text('Apply Leave')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Leave type', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: LeaveType.values
                  .map((t) => ChoiceChip(
                        label: Text(t.label),
                        selected: _type == t,
                        onSelected: (_) => setState(() => _type = t),
                      ))
                  .toList(),
            ),
            if (balance != null) ...[
              const SizedBox(height: 8),
              Text(
                'Available: ${balance.available.toStringAsFixed(0)} of ${balance.total.toStringAsFixed(0)} days'
                '${balance.pending > 0 ? ' (${balance.pending.toStringAsFixed(0)} pending approval)' : ''}',
                style: const TextStyle(color: AppTheme.muted),
              ),
            ],
            const SizedBox(height: 20),
            const Text('Dates', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickDates,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.date_range)),
                child: Text(
                  _range == null
                      ? 'Tap to select from - to'
                      : '${Fmt.date(_range!.start)}  to  ${Fmt.date(_range!.end)}',
                ),
              ),
            ),
            if (_range != null) ...[
              const SizedBox(height: 6),
              Text('$days working day${days == 1 ? '' : 's'} (Sundays not counted)', style: const TextStyle(color: AppTheme.muted)),
            ],
            const SizedBox(height: 20),
            TextFormField(
              controller: _reasonCtrl,
              maxLines: 4,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Reason', alignLabelWithHint: true),
              validator: (v) => (v == null || v.trim().length < 3) ? 'Please enter a reason' : null,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: leave.submitting ? null : _submit,
              icon: leave.submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: const Text('Submit request'),
            ),
          ],
        ),
      ),
    );
  }
}
