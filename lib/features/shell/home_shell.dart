import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../admin/audit_screen.dart';
import '../admin/roles_screen.dart';
import '../admin/users_screen.dart';
import '../attendance/attendance_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../employees/employees_screen.dart';
import '../leave/approvals_screen.dart';
import '../leave/leave_screen.dart';
import '../locations/locations_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String? _selectedId;

  List<_NavItem> _itemsFor(SessionUser user) {
    final items = <_NavItem>[];
    if (user.can('dashboard.read')) items.add(const _NavItem('dashboard', 'Overview', Icons.grid_view_rounded));
    if (user.canAny(const ['employees.read', 'employees.read.team', 'employees.read.self'])) items.add(const _NavItem('employees', 'Employees', Icons.groups_2_outlined));
    if (user.canAny(const ['attendance.punch', 'attendance.read', 'attendance.read.team', 'attendance.read.self', 'attendance.manage'])) items.add(const _NavItem('attendance', 'Attendance', Icons.schedule_rounded));
    if (user.can('locations.read')) items.add(const _NavItem('locations', 'Work locations', Icons.location_on_outlined));
    if (user.canAny(const ['leave.read', 'leave.read.self', 'leave.read.team', 'leave.create', 'leave.manage'])) items.add(const _NavItem('leave', 'Leave', Icons.event_note_outlined));
    if (user.can('leave.approve')) items.add(const _NavItem('approvals', 'Approvals', Icons.fact_check_outlined, badge: true));
    if (user.can('users.read')) items.add(const _NavItem('users', 'User accounts', Icons.manage_accounts_outlined));
    if (user.can('rbac.read')) items.add(const _NavItem('roles', 'Roles & permissions', Icons.admin_panel_settings_outlined));
    if (user.can('audit.read')) items.add(const _NavItem('audit', 'Audit log', Icons.history_rounded));
    items.add(const _NavItem('settings', 'Settings', Icons.settings_outlined));
    return items;
  }

  Widget _pageFor(String id) => switch (id) {
        'dashboard' => DashboardScreen(
            onOpenAttendance: () => _select('attendance'),
            onOpenLeave: () => _select('leave'),
            onOpenEmployees: () => _select('employees'),
          ),
        'employees' => const EmployeesScreen(),
        'attendance' => const AttendanceScreen(),
        'locations' => const LocationsScreen(),
        'leave' => const LeaveScreen(),
        'approvals' => const ApprovalsScreen(),
        'users' => const UsersScreen(),
        'roles' => const RolesScreen(),
        'audit' => const AuditScreen(),
        _ => const _SettingsScreen(),
      };

  void _select(String id) => setState(() => _selectedId = id);

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final user = controller.user!;
    final items = _itemsFor(user);
    if (items.isEmpty) return const _NoAccessScreen();
    if (!items.any((item) => item.id == _selectedId)) _selectedId = items.first.id;
    final selected = items.firstWhere((item) => item.id == _selectedId);
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Row(
          children: [
            if (wide) _Sidebar(items: items, selectedId: selected.id, user: user, onSelect: _select, onSignOut: controller.signOut),
            Expanded(
              child: Column(
                children: [
                  _TopBar(item: selected, user: user, wide: wide, onSignOut: controller.signOut),
                  Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 180), child: KeyedSubtree(key: ValueKey(selected.id), child: _pageFor(selected.id)))),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide ? null : _MobileNavigation(items: items, selectedId: selected.id, onSelect: _select),
    );
  }
}

class _NavItem {
  const _NavItem(this.id, this.title, this.icon, {this.badge = false});
  final String id;
  final String title;
  final IconData icon;
  final bool badge;
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.items, required this.selectedId, required this.user, required this.onSelect, required this.onSignOut});
  final List<_NavItem> items;
  final String selectedId;
  final SessionUser user;
  final ValueChanged<String> onSelect;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 258,
      color: AppColors.navy,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(22, 25, 18, 24), child: Row(children: [Container(width: 39, height: 39, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: const LinearGradient(colors: [AppColors.blue, AppColors.teal])), child: const Icon(Icons.bubble_chart_rounded, color: Colors.white, size: 22)), const SizedBox(width: 11), const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('FlavorFlow', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)), Text('PEOPLE PLATFORM', style: TextStyle(color: Color(0xFF91A7BB), fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1.2))])])),
        const Padding(padding: EdgeInsets.fromLTRB(23, 0, 18, 11), child: Text('WORKSPACE', style: TextStyle(color: Color(0xFF7F97AB), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.1))),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final item = items[index];
              final active = item.id == selectedId;
              return _SidebarItem(item: item, active: active, onTap: () => onSelect(item.id));
            },
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.07))),
          child: Row(children: [PersonAvatar(name: user.fullName, size: 36), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(user.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text(user.primaryRole, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF9BAFC0), fontSize: 10))])), IconButton(onPressed: onSignOut, tooltip: 'Sign out', icon: const Icon(Icons.logout_rounded, color: Color(0xFF9BAFC0), size: 18))]),
        ),
      ]),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.item, required this.active, required this.onTap});
  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11), child: Row(children: [Icon(item.icon, size: 19, color: active ? const Color(0xFF6CDCC8) : const Color(0xFF9CB0C1)), const SizedBox(width: 12), Expanded(child: Text(item.title, style: TextStyle(color: active ? Colors.white : const Color(0xFFC0CED9), fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w500))), if (item.badge) Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle))])),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.item, required this.user, required this.wide, required this.onSignOut});
  final _NavItem item;
  final SessionUser user;
  final bool wide;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 74,
      padding: EdgeInsets.symmetric(horizontal: wide ? 30 : 19),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(children: [
        if (!wide) ...[
          Container(width: 34, height: 34, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: const LinearGradient(colors: [AppColors.blue, AppColors.teal])), child: const Icon(Icons.bubble_chart_rounded, color: Colors.white, size: 20)),
          const SizedBox(width: 10),
          const Text('FlavorFlow', style: TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
          Container(width: 1, height: 24, color: AppColors.line),
          const SizedBox(width: 12),
        ],
        if (wide) ...[
          Text(item.title, style: const TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(width: 9),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 17),
        ],
        Expanded(child: Text(wide ? 'People operations' : item.title, style: TextStyle(color: wide ? AppColors.muted : AppColors.ink, fontSize: wide ? 11 : 12, fontWeight: wide ? FontWeight.w500 : FontWeight.w700), overflow: TextOverflow.ellipsis)),
        if (wide)
          Padding(padding: const EdgeInsets.only(right: 11), child: Text(user.primaryRole, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600))),
        PersonAvatar(name: user.fullName, size: 37),
        PopupMenuButton<String>(
          tooltip: 'Account menu',
          icon: const Icon(Icons.more_vert_rounded, color: AppColors.muted),
          onSelected: (value) { if (value == 'signout') onSignOut(); },
          itemBuilder: (context) => [PopupMenuItem(value: 'profile', enabled: false, child: Text(user.email, style: const TextStyle(fontSize: 11))), const PopupMenuDivider(), const PopupMenuItem(value: 'signout', child: Row(children: [Icon(Icons.logout_rounded, size: 17), SizedBox(width: 9), Text('Sign out')]))],
        ),
      ]),
    );
  }
}

class _MobileNavigation extends StatelessWidget {
  const _MobileNavigation({required this.items, required this.selectedId, required this.onSelect});
  final List<_NavItem> items;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final hasMore = items.length > 4;
    final visible = hasMore ? items.take(3).toList() : items;
    final currentVisible = visible.indexWhere((item) => item.id == selectedId);
    final selectedIndex = currentVisible >= 0 ? currentVisible : (hasMore ? visible.length : 0);
    final destinations = <NavigationDestination>[
      ...visible.map((item) => NavigationDestination(icon: Icon(item.icon), selectedIcon: Icon(item.icon, color: AppColors.blue), label: item.title)),
      if (hasMore) const NavigationDestination(icon: Icon(Icons.more_horiz_rounded), selectedIcon: Icon(Icons.more_horiz_rounded, color: AppColors.blue), label: 'More'),
    ];
    return NavigationBar(
      height: 72,
      selectedIndex: selectedIndex,
      backgroundColor: Colors.white,
      indicatorColor: AppColors.softBlue,
      onDestinationSelected: (index) {
        if (index < visible.length) {
          onSelect(visible[index].id);
        } else {
          _showMore(context, items.skip(3).toList());
        }
      },
      destinations: destinations,
    );
  }

  void _showMore(BuildContext context, List<_NavItem> extra) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.line,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      'Workspace',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...extra.map(
                      (item) => ListTile(
                        leading: Icon(item.icon, color: AppColors.blue),
                        title: Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          onSelect(item.id);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen();

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 930),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Settings', style: TextStyle(color: AppColors.ink, fontSize: 25, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Your profile and workspace preferences.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 20),
            AppPanel(child: Row(children: [PersonAvatar(name: user.fullName, size: 53), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(user.fullName, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 15)), const SizedBox(height: 4), Text(user.email, style: const TextStyle(color: AppColors.muted, fontSize: 12)), const SizedBox(height: 6), Text(user.roleNames.join(' · '), style: const TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w700))]))])),
            const SizedBox(height: 15),
            AppPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Attendance permissions', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 14)), const SizedBox(height: 8), const Text('FlavorFlow requests native location access only when you punch in or out. The API verifies reported coordinates against the selected work location geofence.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5)), const SizedBox(height: 12), Row(children: [const Icon(Icons.gps_fixed_rounded, color: AppColors.blue, size: 18), const SizedBox(width: 8), Text(user.can('attendance.punch') ? 'GPS attendance is enabled for your role.' : 'Your role does not have punch permissions.', style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w600))])])),
            const SizedBox(height: 15),
            const AppPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Security', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 14)),
                  SizedBox(height: 10),
                  _SettingLine(icon: Icons.lock_outline_rounded, title: 'Session token', subtitle: 'Stored using native secure storage.'),
                  Divider(height: 23),
                  _SettingLine(icon: Icons.admin_panel_settings_outlined, title: 'Access control', subtitle: 'Role grants are managed by your HRMS administrator and enforced by the API.'),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SettingLine extends StatelessWidget {
  const _SettingLine({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 35, height: 35, decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: AppColors.blue, size: 18)), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4))]))]);
}

class _NoAccessScreen extends StatelessWidget {
  const _NoAccessScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(backgroundColor: AppColors.canvas, body: Center(child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.lock_outline_rounded, size: 38, color: AppColors.blue), SizedBox(height: 14), Text('No modules are available', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 18)), SizedBox(height: 7), Text('Ask your administrator to assign access to this account.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13))]))));
}
