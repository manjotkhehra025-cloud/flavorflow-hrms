import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic> _data = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await AppScope.of(context).api.get('dashboard');
      if (!mounted) return;
      setState(() => _data = asJsonMap(response));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user!;
    final stats = asJsonMap(_data['stats']);
    final attendance = asJsonList(_data['recent_attendance']);
    final pending = asJsonList(_data['pending_requests']);
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeading(
                  title: 'Overview',
                  subtitle: 'Your people operations, at a glance.',
                  trailing: IconButton.filledTonal(
                    onPressed: _load,
                    tooltip: 'Refresh dashboard',
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(23),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.navy, Color(0xFF104269), Color(0xFF0B7775)],
                    ),
                    boxShadow: const [BoxShadow(color: Color(0x1B12344D), blurRadius: 24, offset: Offset(0, 12))],
                  ),
                  child: Stack(
                    children: [
                      Positioned(right: 0, top: -40, child: Icon(Icons.hub_rounded, size: 170, color: Colors.white.withValues(alpha: 0.06))),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(greeting, style: const TextStyle(color: Color(0xFFB7D8E2), fontWeight: FontWeight.w600, fontSize: 13)),
                                const SizedBox(height: 8),
                                Text(user.fullName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 9),
                                const Text('Keep your team moving with one clear view of today.', style: TextStyle(color: Color(0xFFD3E3EC), fontSize: 13, height: 1.4)),
                                const SizedBox(height: 18),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF84E1CC)),
                                    const SizedBox(width: 8),
                                    Text(_todayLabel(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 18),
                          if (MediaQuery.sizeOf(context).width >= 720)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
                              child: Row(
                                children: [
                                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF43D99C), shape: BoxShape.circle)),
                                  const SizedBox(width: 9),
                                  const Text('Workspace active', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                if (_loading && _data.isEmpty)
                  const SizedBox(height: 145, child: LoadingView(label: 'Loading your overview…'))
                else if (_error != null && _data.isEmpty)
                  ErrorNotice(message: _error!, onRetry: _load)
                else ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final count = constraints.maxWidth >= 1000 ? 4 : constraints.maxWidth >= 560 ? 2 : 1;
                      const gap = 14.0;
                      final width = (constraints.maxWidth - gap * (count - 1)) / count;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          SizedBox(width: width, child: StatCard(title: 'Active employees', value: stringValue(stats['active_employees'], fallback: '0'), footnote: 'People on your roster', icon: Icons.groups_2_outlined, tint: AppColors.blue)),
                          SizedBox(width: width, child: StatCard(title: 'Present today', value: stringValue(stats['present_today'], fallback: '0'), footnote: 'Checked in so far', icon: Icons.how_to_reg_rounded, tint: AppColors.success)),
                          SizedBox(width: width, child: StatCard(title: 'Leave requests', value: stringValue(stats['pending_leave'], fallback: '0'), footnote: 'Waiting for a decision', icon: Icons.event_note_rounded, tint: const Color(0xFFE3A23E))),
                          SizedBox(width: width, child: StatCard(title: 'Work locations', value: stringValue(stats['active_locations'], fallback: '0'), footnote: 'Active geofenced sites', icon: Icons.location_on_outlined, tint: AppColors.teal)),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 23),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final twoColumns = constraints.maxWidth >= 930;
                      final left = _RecentAttendance(items: attendance);
                      final right = _PendingRequests(items: pending);
                      if (!twoColumns) {
                        return Column(children: [left, const SizedBox(height: 18), right]);
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: left),
                          const SizedBox(width: 18),
                          Expanded(flex: 5, child: right),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentAttendance extends StatelessWidget {
  const _RecentAttendance({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.fromLTRB(19, 19, 19, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'Recent attendance', subtitle: 'Latest team check-ins'),
          const SizedBox(height: 13),
          if (items.isEmpty)
            const EmptyNotice(title: 'No check-ins yet', subtitle: 'Punch activity will appear here as your team arrives.', icon: Icons.schedule_rounded)
          else
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      PersonAvatar(name: stringValue(item['employee_name'], fallback: 'Team member'), size: 38),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(stringValue(item['employee_name'], fallback: 'Team member'), style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 13)),
                            const SizedBox(height: 3),
                            Text('${stringValue(item['location_name'], fallback: 'Work site')} · ${formatDateTime(item['punch_in_at'])}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                          ],
                        ),
                      ),
                      StatusBadge(status: item['punch_out_at'] == null ? 'present' : 'complete'),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

class _PendingRequests extends StatelessWidget {
  const _PendingRequests({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.fromLTRB(19, 19, 19, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'Needs attention', subtitle: 'Leave requests awaiting review'),
          const SizedBox(height: 13),
          if (items.isEmpty)
            const EmptyNotice(title: 'All caught up', subtitle: 'There are no pending leave requests right now.', icon: Icons.task_alt_rounded)
          else
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.softAmber, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.event_busy_rounded, color: Color(0xFFAE751C), size: 19)),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(stringValue(item['employee_name'], fallback: 'Team member'), style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 13)),
                            const SizedBox(height: 3),
                            Text('${stringValue(item['leave_type'], fallback: 'Leave')} · ${formatDate(item['start_date'])}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                          ],
                        ),
                      ),
                      const StatusBadge(status: 'pending'),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 15)), const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12))]);
}

String _todayLabel() {
  const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  final now = DateTime.now();
  return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
}
