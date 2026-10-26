import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/employee.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) return const Scaffold();
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                EmployeeAvatar(initials: user.initials, radius: 44),
                const SizedBox(height: 12),
                Text(user.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Text('${user.designation}  \u2022  ${user.department}', style: const TextStyle(color: AppTheme.muted)),
                const SizedBox(height: 8),
                StatusChip(user.role.label, user.isAdmin ? AppTheme.warning : AppTheme.primary),
              ],
            ),
          ),
          const SectionHeader('Work'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  InfoRow(icon: Icons.badge, label: 'Employee ID', value: user.id),
                  InfoRow(icon: Icons.event, label: 'Date of joining', value: Fmt.date(user.joiningDate)),
                  InfoRow(icon: Icons.supervisor_account, label: 'Reporting manager', value: user.managerName ?? '-'),
                ],
              ),
            ),
          ),
          const SectionHeader('Personal'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  InfoRow(icon: Icons.email_outlined, label: 'Email', value: user.email),
                  InfoRow(icon: Icons.phone_outlined, label: 'Phone', value: user.phone),
                  InfoRow(icon: Icons.home_outlined, label: 'Address', value: user.address ?? '-'),
                  InfoRow(icon: Icons.bloodtype_outlined, label: 'Blood group', value: user.bloodGroup ?? '-'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _changePassword(context),
            icon: const Icon(Icons.lock_reset),
            label: const Text('Change password'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
            onPressed: () => logout(context),
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: oldCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
            const SizedBox(height: 12),
            TextField(controller: newCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'New password (min 6)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final error = await context.read<AuthProvider>().changePassword(oldCtrl.text, newCtrl.text);
      if (context.mounted) showSnack(context, error ?? 'Password changed', error: error != null);
    }
    oldCtrl.dispose();
    newCtrl.dispose();
  }
}

/// Logs out and returns to the login screen.
Future<void> logout(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Logout?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Logout')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  context.read<AttendanceProvider>().clear();
  await context.read<AuthProvider>().logout();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (route) => false,
  );
}
