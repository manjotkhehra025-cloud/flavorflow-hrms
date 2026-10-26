import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/nav.dart';
import '../../models/leave.dart';
import '../../providers/auth_provider.dart';
import '../../providers/leave_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/leave_balance_card.dart';
import '../../widgets/status_colors.dart';
import '../admin/leave_approvals_screen.dart';
import 'apply_leave_screen.dart';

class LeaveScreen extends StatelessWidget {
  const LeaveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final leave = context.watch<LeaveProvider>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leave'),
        actions: [
          if (auth.isAdmin)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => pushScreen(context, const LeaveApprovalsScreen()),
              icon: Badge(
                isLabelVisible: leave.pendingApprovals.isNotEmpty,
                label: Text('${leave.pendingApprovals.length}'),
                child: const Icon(Icons.fact_check),
              ),
              label: const Text('Approvals'),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => pushScreen(context, const ApplyLeaveScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Apply Leave'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (user != null) await leave.loadMine(user.id);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            const SectionHeader('Balance (this year)'),
            SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: leave.balances.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (_, i) => LeaveBalanceCard(balance: leave.balances[i]),
              ),
            ),
            const SectionHeader('My requests'),
            if (leave.loading && leave.myRequests.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (leave.myRequests.isEmpty)
              const EmptyState(icon: Icons.event_available, message: 'No leave requests yet')
            else
              ...leave.myRequests.map((r) => LeaveRequestTile(request: r, onCancel: () => _cancel(context, r))),
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, LeaveRequest r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel leave request?'),
        content: Text('${r.type.label}: ${Fmt.shortDate(r.fromDate)} - ${Fmt.shortDate(r.toDate)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, cancel')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final error = await context.read<LeaveProvider>().cancel(r);
    if (!context.mounted) return;
    showSnack(context, error ?? 'Leave request cancelled', error: error != null);
  }
}

class LeaveRequestTile extends StatelessWidget {
  const LeaveRequestTile({super.key, required this.request, this.onCancel, this.showEmployee = false, this.actions});
  final LeaveRequest request;
  final VoidCallback? onCancel;
  final bool showEmployee;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final dates = isSameDay(r.fromDate, r.toDate)
        ? Fmt.date(r.fromDate)
        : '${Fmt.shortDate(r.fromDate)} - ${Fmt.date(r.toDate)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      showEmployee ? '${r.employeeName} (${r.employeeId})' : r.type.label,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  StatusChip(r.status.label, leaveStatusColor(r.status)),
                ],
              ),
              const SizedBox(height: 6),
              if (showEmployee) Text(r.type.label, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text('$dates  \u2022  ${r.days} day${r.days == 1 ? '' : 's'}'),
              const SizedBox(height: 4),
              Text('Reason: ${r.reason}', style: TextStyle(color: Colors.grey.shade700)),
              if (r.approverComment != null) ...[
                const SizedBox(height: 4),
                Text('HR comment: ${r.approverComment}', style: TextStyle(color: Colors.grey.shade700, fontStyle: FontStyle.italic)),
              ],
              Text('Applied on ${Fmt.date(r.appliedOn)}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              if (onCancel != null && r.status == LeaveStatus.pending)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: onCancel, child: const Text('Cancel request')),
                ),
              if (actions != null) actions!,
            ],
          ),
        ),
      ),
    );
  }
}
