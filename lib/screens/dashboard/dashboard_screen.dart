import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/content_provider.dart';
import '../../providers/leave_provider.dart';
import '../../providers/payslip_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/leave_balance_card.dart';
import '../../widgets/punch_card.dart';
import '../admin/attendance_report_screen.dart';
import '../admin/employee_list_screen.dart';
import '../admin/leave_approvals_screen.dart';
import '../announcements/announcements_screen.dart';
import '../holidays/holidays_screen.dart';
import '../home/home_shell.dart';
import '../leave/apply_leave_screen.dart';
import '../profile/profile_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    if (user == null) return const SizedBox.shrink();
    final leave = context.watch<LeaveProvider>();
    final content = context.watch<ContentProvider>();
    final payslip = context.watch<PayslipProvider>().latest;

    final tiles = <_Tile>[
      _Tile('Apply Leave', Icons.edit_calendar, AppTheme.warning, () => pushScreen(context, const ApplyLeaveScreen())),
      _Tile('Attendance', Icons.calendar_month, AppTheme.success, () => HomeShell.of(context)?.goTo(HomeShellState.tabAttendance)),
      _Tile('Payslips', Icons.receipt_long, AppTheme.primary, () => HomeShell.of(context)?.goTo(HomeShellState.tabPayslip)),
      _Tile('Holidays', Icons.beach_access, Colors.purple, () => pushScreen(context, const HolidaysScreen())),
      _Tile('Announcements', Icons.campaign, AppTheme.info, () => pushScreen(context, const AnnouncementsScreen())),
      _Tile('My Profile', Icons.person, Colors.teal, () => pushScreen(context, const ProfileScreen())),
      if (user.isAdmin) ...[
        _Tile('Employees', Icons.groups, Colors.indigo, () => pushScreen(context, const EmployeeListScreen())),
        _Tile('Approvals', Icons.fact_check, Colors.deepOrange, () => pushScreen(context, const LeaveApprovalsScreen())),
        _Tile('Att. Report', Icons.analytics, Colors.blueGrey, () => pushScreen(context, const AttendanceReportScreen())),
      ],
    ];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(user.initials, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_greeting()},', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  Text(user.firstName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Announcements',
            icon: const Icon(Icons.notifications_none),
            onPressed: () => pushScreen(context, const AnnouncementsScreen()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => HomeShell.of(context)?.refreshAll(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const PunchCard(),
            const SectionHeader('Quick actions'),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.05,
              children: tiles.map((t) => _TileView(tile: t)).toList(),
            ),
            if (user.isAdmin && leave.pendingApprovals.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                color: AppTheme.warning.withValues(alpha: 0.08),
                child: ListTile(
                  leading: const Icon(Icons.pending_actions, color: AppTheme.warning),
                  title: Text('${leave.pendingApprovals.length} leave request(s) waiting for approval'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => pushScreen(context, const LeaveApprovalsScreen()),
                ),
              ),
            ],
            SectionHeader('Leave balance', action: 'View all', onAction: () => HomeShell.of(context)?.goTo(HomeShellState.tabLeave)),
            SizedBox(
              height: 128,
              child: leave.balances.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: leave.balances.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => LeaveBalanceCard(balance: leave.balances[i]),
                    ),
            ),
            if (payslip != null) ...[
              const SectionHeader('Last salary'),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.currency_rupee)),
                  title: Text(Fmt.inr(payslip.netPay), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  subtitle: Text('Net pay for ${Fmt.month(payslip.month)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => HomeShell.of(context)?.goTo(HomeShellState.tabPayslip),
                ),
              ),
            ],
            if (content.nextHoliday != null) ...[
              const SectionHeader('Upcoming holiday'),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Color(0xFFF3E5F5), child: Icon(Icons.celebration, color: Colors.purple)),
                  title: Text(content.nextHoliday!.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${Fmt.date(content.nextHoliday!.date)} (${Fmt.weekday(content.nextHoliday!.date)})'),
                  onTap: () => pushScreen(context, const HolidaysScreen()),
                ),
              ),
            ],
            if (content.announcements.isNotEmpty) ...[
              SectionHeader('Announcements', action: 'See all', onAction: () => pushScreen(context, const AnnouncementsScreen())),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.campaign)),
                  title: Text(content.announcements.first.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(content.announcements.first.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => pushScreen(context, const AnnouncementsScreen()),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Tile {
  const _Tile(this.label, this.icon, this.color, this.onTap);
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _TileView extends StatelessWidget {
  const _TileView({required this.tile});
  final _Tile tile;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: tile.onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: tile.color.withValues(alpha: 0.12),
                child: Icon(tile.icon, color: tile.color),
              ),
              const SizedBox(height: 8),
              Text(tile.label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
