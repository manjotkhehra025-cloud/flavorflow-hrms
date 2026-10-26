import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/leave.dart';
import '../../providers/leave_provider.dart';
import '../../widgets/common.dart';
import '../leave/leave_screen.dart';

class LeaveApprovalsScreen extends StatefulWidget {
  const LeaveApprovalsScreen({super.key});

  @override
  State<LeaveApprovalsScreen> createState() => _LeaveApprovalsScreenState();
}

class _LeaveApprovalsScreenState extends State<LeaveApprovalsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<LeaveProvider>().loadAll());
  }

  Future<void> _decide(LeaveRequest r, bool approve) async {
    final commentCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve leave?' : 'Reject leave?'),
        content: TextField(
          controller: commentCtrl,
          decoration: InputDecoration(labelText: approve ? 'Comment (optional)' : 'Reason for rejection'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: approve ? AppTheme.success : AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    final comment = commentCtrl.text;
    commentCtrl.dispose();
    if (ok != true || !mounted) return;
    final error = await context.read<LeaveProvider>().decide(r, approve, comment: comment);
    if (!mounted) return;
    showSnack(context, error ?? (approve ? 'Leave approved' : 'Leave rejected'), error: error != null);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LeaveProvider>();
    final pending = p.pendingApprovals;
    final history = p.allRequests.where((r) => r.status != LeaveStatus.pending).toList();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Leave Approvals'),
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Pending (${pending.length})'),
              const Tab(text: 'History'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _list(p, pending, actionable: true),
            _list(p, history, actionable: false),
          ],
        ),
      ),
    );
  }

  Widget _list(LeaveProvider p, List<LeaveRequest> items, {required bool actionable}) {
    if (p.loading && items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return EmptyState(
        icon: actionable ? Icons.task_alt : Icons.history,
        message: actionable ? 'No pending requests' : 'No history yet',
      );
    }
    return RefreshIndicator(
      onRefresh: p.loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: items
            .map((r) => LeaveRequestTile(
                  request: r,
                  showEmployee: true,
                  actions: actionable
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
                                  onPressed: () => _decide(r, false),
                                  icon: const Icon(Icons.close),
                                  label: const Text('Reject'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
                                  onPressed: () => _decide(r, true),
                                  icon: const Icon(Icons.check),
                                  label: const Text('Approve'),
                                ),
                              ),
                            ],
                          ),
                        )
                      : null,
                ))
            .toList(),
      ),
    );
  }
}
