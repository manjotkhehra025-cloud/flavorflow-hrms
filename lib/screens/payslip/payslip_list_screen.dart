import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/nav.dart';
import '../../providers/auth_provider.dart';
import '../../providers/payslip_provider.dart';
import '../../widgets/common.dart';
import 'payslip_detail_screen.dart';

class PayslipListScreen extends StatelessWidget {
  const PayslipListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PayslipProvider>();
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: AppBar(title: const Text('Payslips')),
      body: RefreshIndicator(
        onRefresh: () async {
          if (user != null) await p.load(user.id);
        },
        child: p.loading && p.payslips.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : p.payslips.isEmpty
                ? ListView(children: const [EmptyState(icon: Icons.receipt_long, message: 'No payslips yet')])
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: p.payslips.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final s = p.payslips[i];
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                          title: Text(Fmt.month(s.month), style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Gross ${Fmt.inr(s.grossEarnings)}  \u2022  Deductions ${Fmt.inr(s.totalDeductions)}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(Fmt.inr(s.netPay), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const Text('Net pay', style: TextStyle(fontSize: 11)),
                            ],
                          ),
                          onTap: () => pushScreen(context, PayslipDetailScreen(payslip: s)),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
