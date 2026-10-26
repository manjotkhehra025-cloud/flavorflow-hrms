import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/payslip.dart';
import '../../providers/auth_provider.dart';
import '../../providers/payslip_provider.dart';
import '../../widgets/common.dart';

class PayslipDetailScreen extends StatefulWidget {
  const PayslipDetailScreen({super.key, required this.payslip});
  final Payslip payslip;

  @override
  State<PayslipDetailScreen> createState() => _PayslipDetailScreenState();
}

class _PayslipDetailScreenState extends State<PayslipDetailScreen> {
  bool _downloading = false;

  Future<void> _download() async {
    setState(() => _downloading = true);
    final path = await context.read<PayslipProvider>().downloadPdf(widget.payslip);
    if (!mounted) return;
    setState(() => _downloading = false);
    // TODO(pdf): open/share the generated file.
    showSnack(context, path == null ? 'PDF download coming soon (connect backend / pdf package)' : 'Saved to $path');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.payslip;
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: AppBar(title: Text('Payslip - ${Fmt.month(s.month)}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.primaryDark]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Net Pay', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 4),
                Text(Fmt.inrPrecise(s.netPay), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text('Paid days: ${s.paidDays.toStringAsFixed(0)} / ${s.workingDays}', style: const TextStyle(color: Colors.white)),
                if (s.bankAccountMasked != null)
                  Text('Bank A/c: ${s.bankAccountMasked}', style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          if (user != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _row('Employee', '${user.name} (${user.id})'),
                    _row('Designation', user.designation),
                    _row('Department', user.department),
                  ],
                ),
              ),
            ),
          ],
          const SectionHeader('Earnings'),
          _table(s.earnings, 'Gross Earnings', s.grossEarnings, AppTheme.success),
          const SectionHeader('Deductions'),
          _table(s.deductions, 'Total Deductions', s.totalDeductions, AppTheme.danger),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _downloading ? null : _download,
            icon: _downloading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.picture_as_pdf),
            label: const Text('Download PDF'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 110, child: Text(label, style: const TextStyle(color: AppTheme.muted))),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
      );

  Widget _table(List<PayItem> items, String totalLabel, double total, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            ...items.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(e.label)),
                      Text(Fmt.inrPrecise(e.amount)),
                    ],
                  ),
                )),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text(totalLabel, style: const TextStyle(fontWeight: FontWeight.bold))),
                  Text(Fmt.inrPrecise(total), style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
