import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.onOpenAttendance,
    this.onOpenLeave,
    this.onOpenEmployees,
    this.onOpenCalendar,
    this.onOpenShifts,
  });

  final VoidCallback? onOpenAttendance;
  final VoidCallback? onOpenLeave;
  final VoidCallback? onOpenEmployees;
  final VoidCallback? onOpenCalendar;
  final VoidCallback? onOpenShifts;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic> _data = const {};
  Map<String, dynamic>? _myAttendance;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await AppScope.of(context).api.get('dashboard');
      if (!mounted) return;
      final data = asJsonMap(response);
      final active = data['my_attendance'];
      setState(() {
        _data = data;
        _myAttendance = active == null ? null : asJsonMap(active);
      });
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
    final leaveBalances = asJsonList(_data['my_leave_balances']);
    final leaveBalancePeriod = asJsonMap(_data['leave_balance_period']);
    final leaveBalanceLabel = stringValue(
      leaveBalancePeriod['label'],
      fallback: stringValue(_data['leave_balance_year']),
    );
    final leavePolicySummary = stringValue(
      leaveBalancePeriod['policy_summary'],
      fallback: 'weekends included · no new-hire proration · no carry-over',
    );
    final canSeeEmployees = user.canAny(const [
      'employees.read',
      'employees.read.team',
      'employees.read.self',
    ]);
    final canSeeAttendance = user.canAny(const [
      'attendance.read',
      'attendance.read.team',
      'attendance.read.self',
      'attendance.punch',
      'attendance.manage',
    ]);
    final canSeePulse = canSeeEmployees && canSeeAttendance;
    final canSeeLeave = user.canAny(const [
      'leave.read',
      'leave.read.team',
      'leave.read.self',
      'leave.create',
      'leave.approve',
      'leave.manage',
    ]);
    final canSeeCalendar = user.can('calendar.read');
    final canSeeShifts = user.canAny(const [
      'shifts.read',
      'shifts.read.team',
      'shifts.read.self',
      'shifts.manage',
    ]);
    final canSeeMyShift = user.canAny(const [
      'shifts.read',
      'shifts.read.self',
      'shifts.manage',
    ]);
    final myShiftValue = _data['my_shift'];
    final myShift = myShiftValue == null ? null : asJsonMap(myShiftValue);
    final upcomingHolidayValue = _data['upcoming_holiday'];
    final upcomingHoliday = upcomingHolidayValue == null
        ? null
        : asJsonMap(upcomingHolidayValue);
    final canSeeMyAttendance = user.canAny(const [
      'attendance.read',
      'attendance.manage',
      'attendance.read.self',
      'attendance.punch',
    ]);
    final activeEmployees = int.tryParse(stringValue(stats['active_employees'])) ?? 0;
    final presentToday = int.tryParse(stringValue(stats['present_today'])) ?? 0;
    final onLeaveToday = int.tryParse(stringValue(stats['on_leave_today'])) ?? 0;
    final quickActions = <_DashboardAction>[];
    if (user.can('leave.create') && widget.onOpenLeave != null) {
      quickActions.add(_DashboardAction(
        label: 'Apply for leave',
        icon: Icons.event_available_rounded,
        onPressed: widget.onOpenLeave!,
      ));
    }
    if (canSeeEmployees && widget.onOpenEmployees != null) {
      quickActions.add(_DashboardAction(
        label: user.canAny(const ['employees.read', 'employees.read.team'])
            ? 'View team'
            : 'My profile',
        icon: Icons.groups_2_outlined,
        onPressed: widget.onOpenEmployees!,
      ));
    }
    if (canSeeCalendar && widget.onOpenCalendar != null) {
      quickActions.add(_DashboardAction(
        label: 'Open calendar',
        icon: Icons.calendar_month_rounded,
        onPressed: widget.onOpenCalendar!,
      ));
    }
    if (canSeeShifts && widget.onOpenShifts != null) {
      quickActions.add(_DashboardAction(
        label: 'Shift roster',
        icon: Icons.view_timeline_outlined,
        onPressed: widget.onOpenShifts!,
      ));
    }
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
                if (quickActions.isNotEmpty) ...[
                  _QuickActions(actions: quickActions),
                  const SizedBox(height: 18),
                ],
                if (_loading && _data.isEmpty)
                  const SizedBox(height: 145, child: LoadingView(label: 'Loading your overview…'))
                else if (_error != null && _data.isEmpty)
                  ErrorNotice(message: _error!, onRetry: _load)
                else ...[
                  if (canSeeMyAttendance) ...[
                    _MyAttendanceCard(
                      active: _myAttendance,
                      canPunch: user.can('attendance.punch'),
                      onOpen: widget.onOpenAttendance,
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (canSeeMyShift) ...[
                    _MyShiftCard(shift: myShift, onOpen: widget.onOpenShifts),
                    const SizedBox(height: 18),
                  ],
                  if (canSeeLeave && leaveBalances.isNotEmpty) ...[
                    _LeaveBalancePanel(
                      items: leaveBalances,
                      periodLabel: leaveBalanceLabel,
                      policySummary: leavePolicySummary,
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (canSeePulse) ...[
                    _WorkforcePulse(
                      activeEmployees: activeEmployees,
                      presentToday: presentToday,
                      onLeaveToday: onLeaveToday,
                      canSeeLeave: canSeeLeave,
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (canSeeCalendar) ...[
                    _UpcomingHolidayCard(
                      holiday: upcomingHoliday,
                      onOpen: widget.onOpenCalendar,
                    ),
                    const SizedBox(height: 18),
                  ],
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final count = canSeePulse
                          ? (constraints.maxWidth >= 560 ? 2 : 1)
                          : constraints.maxWidth >= 1000
                              ? 4
                              : constraints.maxWidth >= 560
                                  ? 2
                                  : 1;
                      const gap = 14.0;
                      final width = (constraints.maxWidth - gap * (count - 1)) / count;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          if (!canSeePulse)
                            SizedBox(width: width, child: StatCard(title: 'Active employees', value: stringValue(stats['active_employees'], fallback: '0'), footnote: 'People on your roster', icon: Icons.groups_2_outlined, tint: AppColors.blue)),
                          if (!canSeePulse)
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

class _DashboardAction {
  const _DashboardAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.actions});

  final List<_DashboardAction> actions;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Quick actions',
            subtitle: 'Shortcuts to your everyday tasks',
          ),
          const SizedBox(height: 13),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth >= 520
                  ? 235.0
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: actions
                    .map(
                      (action) => SizedBox(
                        width: itemWidth,
                        child: OutlinedButton(
                          onPressed: action.onPressed,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(action.icon, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  action.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.left,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MyAttendanceCard extends StatelessWidget {
  const _MyAttendanceCard({
    required this.active,
    required this.canPunch,
    required this.onOpen,
  });

  final Map<String, dynamic>? active;
  final bool canPunch;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final checkedIn = active != null;
    final status = checkedIn ? 'Checked in' : 'Not checked in';
    final location = checkedIn
        ? stringValue(active!['location_name'], fallback: 'Work site')
        : '';
    final subtitle = checkedIn
        ? 'Started ${formatDateTime(active!['punch_in_at'])} · $location'
        : canPunch
            ? 'No active punch. Open attendance for GPS-verified check-in.'
            : 'No open attendance record is currently available.';
    final color = checkedIn ? AppColors.success : AppColors.blue;
    final action = onOpen == null
        ? null
        : OutlinedButton.icon(
            onPressed: onOpen,
            icon: Icon(canPunch ? Icons.fingerprint_rounded : Icons.open_in_new_rounded, size: 18),
            label: Text(canPunch ? 'Open punch controls' : 'View attendance'),
          );

    return AppPanel(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final details = Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  checkedIn ? Icons.check_circle_outline_rounded : Icons.schedule_rounded,
                  color: color,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'My attendance',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              StatusBadge(status: status),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                if (action != null) ...[
                  const SizedBox(height: 12),
                  action,
                ],
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              if (action != null) ...[
                const SizedBox(width: 14),
                action,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _WorkforcePulse extends StatelessWidget {
  const _WorkforcePulse({
    required this.activeEmployees,
    required this.presentToday,
    required this.onLeaveToday,
    required this.canSeeLeave,
  });

  final int activeEmployees;
  final int presentToday;
  final int onLeaveToday;
  final bool canSeeLeave;

  @override
  Widget build(BuildContext context) {
    final progress = activeEmployees > 0
        ? (presentToday / activeEmployees).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return AppPanel(
      padding: const EdgeInsets.all(19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Workforce pulse',
            subtitle: canSeeLeave
                ? 'Live check-ins and approved leave for your visible team'
                : 'Live check-ins across your visible team',
          ),
          const SizedBox(height: 17),
          Row(
            children: [
              Expanded(
                child: _PulseMetric(
                  label: 'Present today',
                  value: presentToday,
                  tint: AppColors.success,
                ),
              ),
              if (canSeeLeave) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _PulseMetric(
                    label: 'On leave today',
                    value: onLeaveToday,
                    tint: const Color(0xFFE3A23E),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              Expanded(
                child: _PulseMetric(
                  label: 'Active roster',
                  value: activeEmployees,
                  tint: AppColors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: AppColors.line,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.blue),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            activeEmployees == 0
                ? 'No active employees are currently on the roster.'
                : '${(progress * 100).round()}% of the active roster has checked in today.',
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _PulseMetric extends StatelessWidget {
  const _PulseMetric({
    required this.label,
    required this.value,
    required this.tint,
  });

  final String label;
  final int value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(color: tint, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MyShiftCard extends StatelessWidget {
  const _MyShiftCard({required this.shift, required this.onOpen});

  final Map<String, dynamic>? shift;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheduled = shift != null && shift!.isNotEmpty;
    final location = scheduled ? stringValue(shift!['location_name']) : '';
    final breakMinutes = scheduled ? stringValue(shift!['break_minutes'], fallback: '0') : '0';
    final locationText = location.isEmpty ? '' : ' · $location';
    final subtitle = scheduled
        ? '${stringValue(shift!['start_time'])}–${stringValue(shift!['end_time'])} · ${breakMinutes}m break$locationText'
        : 'No shift is scheduled for you today.';
    return AppPanel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.schedule_rounded, color: AppColors.teal, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scheduled ? stringValue(shift!['shift_name'], fallback: 'My shift') : 'My shift',
                  style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35)),
              ],
            ),
          ),
          if (scheduled) ...[
            const SizedBox(width: 10),
            const StatusBadge(status: 'scheduled'),
          ],
          if (onOpen != null) ...[
            const SizedBox(width: 6),
            IconButton(onPressed: onOpen, tooltip: 'Open shift roster',
                icon: const Icon(Icons.arrow_forward_rounded, size: 19)),
          ],
        ],
      ),
    );
  }
}

class _UpcomingHolidayCard extends StatelessWidget {
  const _UpcomingHolidayCard({required this.holiday, required this.onOpen});

  final Map<String, dynamic>? holiday;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final hasHoliday = holiday != null && holiday!.isNotEmpty;
    final days = hasHoliday ? int.tryParse(stringValue(holiday!['days_until'])) : null;
    final countdown = days == null
        ? ''
        : days == 0
            ? 'Today'
            : days == 1
                ? 'Tomorrow'
                : 'In $days days';
    final description = hasHoliday ? stringValue(holiday!['description']) : '';
    final subtitle = hasHoliday
        ? '${formatDate(holiday!['holiday_date'])} · $countdown${description.isEmpty ? '' : ' · $description'}'
        : 'No upcoming company holidays have been scheduled.';

    return AppPanel(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final details = Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.softAmber,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.event_available_rounded,
                  color: Color(0xFFAE751C),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasHoliday ? stringValue(holiday!['name'], fallback: 'Holiday') : 'Upcoming holiday',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          );
          final action = onOpen == null
              ? null
              : TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.calendar_month_rounded, size: 17),
                  label: const Text('Calendar'),
                );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                if (action != null) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: action),
                ],
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              if (action != null) ...[
                const SizedBox(width: 12),
                action,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _LeaveBalancePanel extends StatelessWidget {
  const _LeaveBalancePanel({required this.items, required this.periodLabel, required this.policySummary});

  final List<Map<String, dynamic>> items;
  final String periodLabel;
  final String policySummary;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.all(19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'My leave balance',
            subtitle: '$periodLabel · $policySummary',
          ),
          const SizedBox(height: 15),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 3
                  : constraints.maxWidth >= 540
                      ? 2
                      : 1;
              const gap = 11.0;
              final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: items
                    .map(
                      (item) => SizedBox(
                        width: width,
                        child: _LeaveBalanceTile(item: item),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LeaveBalanceTile extends StatelessWidget {
  const _LeaveBalanceTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final allowance = _leaveDayValue(item['allowance_days']);
    final used = _leaveDayValue(item['used_days']);
    final remaining = _leaveDayValue(item['remaining_days']);
    final carryover = _leaveDayValue(item['carryover_days']);
    final carryoverText = carryover > 0
        ? ' · ${_formatLeaveDays(carryover)} carried over'
        : '';
    final progress = allowance > 0
        ? (used / allowance).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final remainingText = remaining < 0
        ? '${_formatLeaveDays(remaining.abs())} over'
        : '${_formatLeaveDays(remaining)} left';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  stringValue(item['leave_type'], fallback: 'Leave'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: remaining < 0 ? AppColors.softRed : AppColors.softGreen,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  remainingText,
                  style: TextStyle(
                    color: remaining < 0 ? const Color(0xFFC94D54) : AppColors.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            '${_formatLeaveDays(used)} of ${_formatLeaveDays(allowance)} days used$carryoverText',
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          if (stringValue(item['accrual_method']) == 'monthly') ...[
            const SizedBox(height: 4),
            Text(
              '${_formatLeaveDays(_leaveDayValue(item['monthly_accrual_days']))} days accrue monthly',
              style: const TextStyle(color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation<Color>(
                remaining < 0 ? const Color(0xFFC94D54) : AppColors.teal,
              ),
            ),
          ),
        ],
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

double _leaveDayValue(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _formatLeaveDays(double value) {
  final fixed = value.toStringAsFixed(2);
  return fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
