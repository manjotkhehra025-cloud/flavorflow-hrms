import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/brand_config.dart';
import '../../core/json_helpers.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../admin/audit_screen.dart';
import '../admin/roles_screen.dart';
import '../admin/users_screen.dart';
import '../attendance/attendance_screen.dart';
import '../attendance/shift_roster_screen.dart';
import '../attendance/output_logs_screen.dart';
import '../calendar/calendar_screen.dart';
import '../community/social_wall_screen.dart';
import '../helpdesk/helpdesk_screen.dart';
import '../recognition/recognition_screen.dart';
import '../notifications/notification_center.dart';
import '../attendance/shift_swaps_screen.dart';
import '../approvals/approvals_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../employees/employees_screen.dart';
import '../id_card/id_card_screen.dart';
import '../team/team_screen.dart';
import '../leave/leave_policy_screen.dart';
import '../leave/leave_screen.dart';
import '../locations/locations_screen.dart';
import '../reports/reports_screen.dart';
import '../kyc/kyc_letters_screen.dart';
import '../kra/kra_goals_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String? _selectedId;

  List<_NavItem> _itemsFor(SessionUser user) {
    final items = <_NavItem>[];
    if (user.can('dashboard.read')) items.add(const _NavItem('dashboard', 'Home', Icons.home_rounded));
    if (user.canAny(const ['employees.read', 'employees.read.team', 'employees.read.self'])) items.add(const _NavItem('employees', 'Employees', Icons.groups_2_outlined));
    if (user.can('team.read')) items.add(const _NavItem('team', 'Team', Icons.groups_rounded));
    if (user.canAny(const ['idcard.read', 'idcard.read.team', 'idcard.read.self', 'idcard.update', 'gatepass.read', 'gatepass.read.team', 'gatepass.read.self', 'gatepass.create', 'gatepass.manage'])) items.add(const _NavItem('id_card', 'ID Card & Pass', Icons.badge_outlined));
    if (user.canAny(const ['kyc.read', 'kyc.read.self', 'kyc.create.self', 'kyc.manage'])) items.add(const _NavItem('kyc', 'KYC & Letters', Icons.folder_shared_outlined));
    if (user.canAny(const ['attendance.punch', 'attendance.read', 'attendance.read.team', 'attendance.read.self', 'attendance.manage', 'attendance.request', 'attendance.approve'])) items.add(const _NavItem('attendance', 'Attendance', Icons.schedule_rounded));
    if (user.canAny(const ['kra.read', 'kra.read.team', 'kra.read.self', 'kra.manage'])) items.add(const _NavItem('kra', 'KRA & Goals', Icons.track_changes_rounded));
    if (user.canAny(const ['output.read', 'output.read.team', 'output.read.self', 'output.create.self', 'output.manage'])) items.add(const _NavItem('output_logs', 'Output Logs', Icons.inventory_2_outlined));
    if (user.canAny(const ['shifts.read', 'shifts.read.team', 'shifts.read.self', 'shifts.manage'])) items.add(const _NavItem('shifts', 'Shift Roster', Icons.view_timeline_outlined));
    if (user.can('locations.read')) items.add(const _NavItem('locations', 'Work locations', Icons.location_on_outlined));
    if (user.can('calendar.read')) items.add(const _NavItem('calendar', 'Calendar', Icons.calendar_month_rounded));
    if (user.canAny(const ['leave.read', 'leave.read.self', 'leave.read.team', 'leave.create', 'leave.manage'])) items.add(const _NavItem('leave', 'Leaves', Icons.event_note_outlined));
    if (user.can('leave.policy.manage')) items.add(const _NavItem('leave_policy', 'Leave policy', Icons.tune_rounded));
    if (user.canAny(const ['social.read', 'social.create'])) items.add(const _NavItem('social', 'Social Wall', Icons.forum_outlined));
    if (user.canAny(const ['helpdesk.create', 'helpdesk.read.self', 'helpdesk.manage'])) items.add(const _NavItem('helpdesk', 'Helpdesk', Icons.support_agent_rounded));
    if (user.canAny(const ['recognition.read', 'recognition.manage'])) items.add(const _NavItem('recognition', 'Star Workers', Icons.workspace_premium_outlined));
    if (user.canAny(const ['shifts.swap.request', 'shifts.swap.approve'])) items.add(const _NavItem('shift_swaps', 'Shift swaps', Icons.swap_horiz_rounded));
    if (user.canAny(const ['leave.approve', 'attendance.approve', 'attendance.manage', 'gatepass.approve', 'gatepass.manage', 'shifts.swap.approve'])) items.add(const _NavItem('approvals', 'Approvals', Icons.fact_check_outlined, badge: true));
    if (user.can('users.read')) items.add(const _NavItem('users', 'User accounts', Icons.manage_accounts_outlined));
    if (user.can('rbac.read')) items.add(const _NavItem('roles', 'Roles & permissions', Icons.admin_panel_settings_outlined));
    if (user.can('audit.read')) items.add(const _NavItem('audit', 'Audit log', Icons.history_rounded));
    if (user.can('reports.read')) items.add(const _NavItem('reports', 'Reports', Icons.analytics_outlined));
    items.add(const _NavItem('settings', 'Settings', Icons.settings_outlined));
    return items;
  }

  Widget _pageFor(String id) => switch (id) {
        'dashboard' => DashboardScreen(
            onOpenAttendance: () => _select('attendance'),
            onOpenLeave: () => _select('leave'),
            onOpenEmployees: () => _select('employees'),
            onOpenCalendar: () => _select('calendar'),
            onOpenShifts: () => _select('shifts'),
          ),
        'employees' => const EmployeesScreen(),
        'team' => const TeamScreen(),
        'id_card' => const IdCardScreen(),
        'kyc' => const KycLettersScreen(),
        'attendance' => const AttendanceScreen(),
        'kra' => const KraGoalsScreen(),
        'output_logs' => const OutputLogsScreen(),
        'shifts' => const ShiftRosterScreen(),
        'locations' => const LocationsScreen(),
        'calendar' => const CalendarScreen(),
        'leave' => const LeaveScreen(),
        'leave_policy' => const LeavePolicyScreen(),
        'social' => const SocialWallScreen(),
        'helpdesk' => const HelpdeskScreen(),
        'recognition' => const RecognitionScreen(),
        'shift_swaps' => const ShiftSwapsScreen(),
        'approvals' => const UnifiedApprovalsScreen(),
        'users' => const UsersScreen(),
        'roles' => const RolesScreen(),
        'audit' => const AuditScreen(),
        'reports' => const ReportsScreen(),
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
        Padding(padding: const EdgeInsets.fromLTRB(22, 25, 18, 24), child: Row(children: [Container(width: 39, height: 39, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: const LinearGradient(colors: [AppColors.blue, AppColors.teal])), child: const Icon(Icons.bubble_chart_rounded, color: Colors.white, size: 22)), const SizedBox(width: 11), const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(BrandConfig.appName, style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)), Text('PEOPLE PLATFORM', style: TextStyle(color: Color(0xFF91A7BB), fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1.2))])])),
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
          const Text(BrandConfig.appName, style: TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w800)),
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
        if (user.can('notifications.read')) const NotificationBell(),
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

  _NavItem? _find(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const primaryIds = {'dashboard', 'leave', 'attendance', 'team'};
    final extra = items.where((item) => !primaryIds.contains(item.id)).toList();
    final moreSelected = !primaryIds.contains(selectedId);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 71,
          child: Row(
            children: [
              _MobileNavButton(item: _find('dashboard'), selected: selectedId == 'dashboard', onSelect: onSelect),
              _MobileNavButton(item: _find('leave'), selected: selectedId == 'leave', onSelect: onSelect),
              _MobilePunchButton(
                item: _find('attendance'),
                selected: selectedId == 'attendance',
                onPressed: _find('attendance') == null ? null : () => onSelect('attendance'),
              ),
              _MobileNavButton(item: _find('team'), selected: selectedId == 'team', onSelect: onSelect),
              Expanded(
                child: InkWell(
                  onTap: () => _showMore(context, extra),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.apps_rounded, size: 21, color: moreSelected ? AppColors.blue : AppColors.muted),
                      const SizedBox(height: 3),
                      Text(
                        'More',
                        style: TextStyle(
                          color: moreSelected ? AppColors.blue : AppColors.muted,
                          fontSize: 9,
                          fontWeight: moreSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMore(BuildContext context, List<_NavItem> extra) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final maxHeight = MediaQuery.sizeOf(context).height * 0.86;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(8)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(19, 15, 19, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('More', style: TextStyle(color: AppColors.ink, fontSize: 17, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 3),
                              Text('${extra.length} workspace modules', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                            ],
                          ),
                        ),
                        IconButton(onPressed: () => Navigator.pop(context), tooltip: 'Close menu', icon: const Icon(Icons.close_rounded)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: extra.isEmpty
                        ? const Center(child: Text('No other modules are available.', style: TextStyle(color: AppColors.muted, fontSize: 12)))
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                            itemCount: extra.length,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 11,
                              mainAxisSpacing: 11,
                              childAspectRatio: 0.96,
                            ),
                            itemBuilder: (context, index) => _MoreMenuTile(
                              item: extra[index],
                              onTap: () {
                                Navigator.pop(context);
                                onSelect(extra[index].id);
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MobileNavButton extends StatelessWidget {
  const _MobileNavButton({required this.item, required this.selected, required this.onSelect});

  final _NavItem? item;
  final bool selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (item == null) return const Expanded(child: SizedBox.shrink());
    return Expanded(
      child: InkWell(
        onTap: () => onSelect(item!.id),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item!.icon, size: 21, color: selected ? AppColors.blue : AppColors.muted),
            const SizedBox(height: 3),
            Text(
              item!.id == 'dashboard' ? 'Home' : item!.id == 'leave' ? 'Leaves' : 'Team',
              style: TextStyle(color: selected ? AppColors.blue : AppColors.muted, fontSize: 9, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobilePunchButton extends StatelessWidget {
  const _MobilePunchButton({required this.item, required this.selected, required this.onPressed});

  final _NavItem? item;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (item == null) return const Expanded(child: SizedBox.shrink());
    return Expanded(
      child: InkWell(
        onTap: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: AppColors.blue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [BoxShadow(color: Color(0x221E6FE0), blurRadius: 9, offset: Offset(0, 3))],
              ),
              child: const Icon(Icons.fingerprint_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 1),
            Text('Punch', style: TextStyle(color: selected ? AppColors.blue : AppColors.ink, fontSize: 9, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _MoreMenuTile extends StatelessWidget {
  const _MoreMenuTile({required this.item, required this.onTap});

  final _NavItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFF9FBFE),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 39,
                  height: 39,
                  decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(13)),
                  child: Icon(item.icon, color: AppColors.blue, size: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.ink, fontSize: 10, height: 1.2, fontWeight: FontWeight.w700),
                ),
                if (item.badge) ...[
                  const SizedBox(height: 4),
                  const Icon(Icons.circle, color: AppColors.success, size: 6),
                ],
              ],
            ),
          ),
        ),
      );
}

class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen();

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  bool? _biometricsAvailable;
  bool _sendingTest = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = AppScope.of(context);
      final available = await controller.canUseBiometricsOnDevice();
      if (mounted) setState(() => _biometricsAvailable = available);
    });
  }

  Future<void> _sendNotificationTest() async {
    setState(() => _sendingTest = true);
    try {
      final response = await AppScope.of(context).api.post('notifications/test');
      if (!mounted) return;
      final notice = asJsonMap(response);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(stringValue(notice['body'], fallback: 'In-app test notification saved.'))),
      );
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _sendingTest = false);
    }
  }

  Future<void> _setTimeout(int? minutes) async {
    if (minutes == null) return;
    try {
      await AppScope.of(context).setInactivityTimeoutMinutes(minutes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Automatic sign-out set to $minutes minutes.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the session preference on this device.')),
        );
      }
    }
  }

  Future<void> _setTextScale(double? factor) async {
    if (factor == null) return;
    try {
      await AppScope.of(context).setTextScaleFactor(factor);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Text size preference saved on this device.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the display preference on this device.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final user = controller.user!;
    final biometricStatus = _biometricsAvailable == null
        ? 'Checking this device…'
        : !_biometricsAvailable!
            ? 'No biometric capability is currently available on this device.'
            : controller.hasBiometricLoginSession
                ? 'Biometric sign-in is set up for this device. The existing sign-in flow is unchanged.'
                : 'This device supports biometrics. Set it up from the sign-in screen with Remember me.';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 930),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Settings', style: TextStyle(color: AppColors.ink, fontSize: 25, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Your profile, security, and workspace preferences.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 20),
            AppPanel(child: Row(children: [PersonAvatar(name: user.fullName, size: 53), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(user.fullName, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 15)), const SizedBox(height: 4), Text(user.email, style: const TextStyle(color: AppColors.muted, fontSize: 12)), const SizedBox(height: 6), Text(user.roleNames.join(' · '), style: const TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w700))]))])),
            const SizedBox(height: 15),
            AppPanel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Display preferences', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 7),
                const Text('Choose a comfortable app text size. Device accessibility scaling is retained.', style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
                const SizedBox(height: 12),
                DropdownButtonFormField<double>(
                  value: controller.textScaleFactor,
                  decoration: const InputDecoration(labelText: 'Text size', prefixIcon: Icon(Icons.text_fields_rounded)),
                  items: const [
                    DropdownMenuItem(value: 0.9, child: Text('Compact')),
                    DropdownMenuItem(value: 1.0, child: Text('Standard')),
                    DropdownMenuItem(value: 1.1, child: Text('Large')),
                    DropdownMenuItem(value: 1.2, child: Text('Extra large')),
                  ],
                  onChanged: _setTextScale,
                ),
              ]),
            ),
            const SizedBox(height: 15),
            AppPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Attendance permissions', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 14)), const SizedBox(height: 8), const Text('The app requests native location access only when you punch in or out. The API verifies reported coordinates against the selected work location geofence.', style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5)), const SizedBox(height: 12), Row(children: [const Icon(Icons.gps_fixed_rounded, color: AppColors.blue, size: 18), const SizedBox(width: 8), Text(user.can('attendance.punch') ? 'GPS attendance is enabled for your role.' : 'Your role does not have punch permissions.', style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w600))])])),
            const SizedBox(height: 15),
            AppPanel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Session & security', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 7),
                const Text('Automatic sign-out protects an unattended device. Your current 15-minute default is preserved until you choose another option.', style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: controller.inactivityTimeoutMinutes,
                  decoration: const InputDecoration(labelText: 'Automatic sign-out after', prefixIcon: Icon(Icons.timer_outlined)),
                  items: const [
                    DropdownMenuItem(value: 5, child: Text('5 minutes')),
                    DropdownMenuItem(value: 10, child: Text('10 minutes')),
                    DropdownMenuItem(value: 15, child: Text('15 minutes (default)')),
                    DropdownMenuItem(value: 30, child: Text('30 minutes')),
                    DropdownMenuItem(value: 60, child: Text('60 minutes')),
                  ],
                  onChanged: _setTimeout,
                ),
                const Divider(height: 26),
                _SettingLine(icon: Icons.fingerprint_rounded, title: 'Biometric sign-in', subtitle: biometricStatus),
                const SizedBox(height: 12),
                _SettingLine(icon: Icons.lock_outline_rounded, title: 'Session token', subtitle: 'Stored using native secure storage.'),
                const Divider(height: 23),
                const _SettingLine(icon: Icons.admin_panel_settings_outlined, title: 'Access control', subtitle: 'Role grants are managed by your HRMS administrator and enforced by the API.'),
              ]),
            ),
            const SizedBox(height: 15),
            AppPanel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Notifications', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 7),
                const Text('FlavorFlow saves notification events in the in-app center. A push provider is not configured, so this test does not send an OS push.', style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.45)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: !user.can('notifications.test') || _sendingTest ? null : _sendNotificationTest,
                  icon: _sendingTest ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.notifications_active_outlined, size: 18),
                  label: Text(_sendingTest ? 'Saving test…' : 'Send in-app attendance test'),
                ),
                const SizedBox(height: 5),
                const Text('Open the bell in the top bar to review it.', style: TextStyle(color: AppColors.muted, fontSize: 10)),
              ]),
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
