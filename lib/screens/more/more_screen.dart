import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common.dart';
import '../admin/attendance_report_screen.dart';
import '../admin/employee_list_screen.dart';
import '../admin/leave_approvals_screen.dart';
import '../announcements/announcements_screen.dart';
import '../holidays/holidays_screen.dart';
import '../profile/profile_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: EmployeeAvatar(initials: user.initials, radius: 26),
              title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${user.id}  \u2022  ${user.designation}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => pushScreen(context, const ProfileScreen()),
            ),
          ),
          const SectionHeader('General'),
          _group([
            _item(context, Icons.beach_access, 'Holiday calendar', const HolidaysScreen()),
            _item(context, Icons.campaign, 'Announcements', const AnnouncementsScreen()),
            _item(context, Icons.person, 'My profile', const ProfileScreen()),
          ]),
          if (user.isAdmin) ...[
            const SectionHeader('Admin / HR'),
            _group([
              _item(context, Icons.groups, 'Employees', const EmployeeListScreen()),
              _item(context, Icons.fact_check, 'Leave approvals', const LeaveApprovalsScreen()),
              _item(context, Icons.analytics, 'Attendance report', const AttendanceReportScreen()),
            ]),
          ],
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppTheme.danger),
              title: const Text('Logout', style: TextStyle(color: AppTheme.danger)),
              onTap: () => logout(context),
            ),
          ),
          const SizedBox(height: 16),
          const Center(child: Text('iHRMS v1.0.0', style: TextStyle(color: AppTheme.muted, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _group(List<Widget> children) => Card(child: Column(children: children));

  Widget _item(BuildContext context, IconData icon, String title, Widget screen) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primary),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => pushScreen(context, screen),
    );
  }
}
