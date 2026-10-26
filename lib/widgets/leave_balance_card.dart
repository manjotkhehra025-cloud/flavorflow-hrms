import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/leave.dart';

class LeaveBalanceCard extends StatelessWidget {
  const LeaveBalanceCard({super.key, required this.balance});
  final LeaveBalance balance;

  Color get _color {
    switch (balance.type) {
      case LeaveType.casual:
        return AppTheme.primary;
      case LeaveType.sick:
        return AppTheme.danger;
      case LeaveType.earned:
        return AppTheme.success;
      case LeaveType.unpaid:
        return AppTheme.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = balance.total == 0 ? 0.0 : balance.used / balance.total;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(balance.type.label, style: const TextStyle(fontSize: 12, color: AppTheme.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(balance.available.toStringAsFixed(0), style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _color)),
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 4),
                child: Text('/ ${balance.total.toStringAsFixed(0)}', style: const TextStyle(color: AppTheme.muted)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            color: _color,
            backgroundColor: _color.withValues(alpha: 0.12),
            minHeight: 5,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 6),
          Text(
            balance.pending > 0 ? '${balance.pending.toStringAsFixed(0)} pending' : '${balance.used.toStringAsFixed(0)} used',
            style: const TextStyle(fontSize: 11, color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}
