import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/brand_config.dart';
import '../../core/json_helpers.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class MobileDashboardView extends StatelessWidget {
  const MobileDashboardView({
    super.key,
    required this.user,
    required this.greeting,
    required this.stats,
    required this.recentAttendance,
    required this.leaveBalances,
    required this.activeAttendance,
    required this.myShift,
    required this.upcomingHoliday,
    required this.canSeeLeave,
    required this.canSeePulse,
    required this.canSeeCalendar,
    required this.canSeeMyAttendance,
    required this.canSeeMyShift,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onOpenAttendance,
    required this.onOpenLeave,
    required this.onOpenModule,
  });

  final SessionUser user;
  final String greeting;
  final Map<String, dynamic> stats;
  final List<Map<String, dynamic>> recentAttendance;
  final List<Map<String, dynamic>> leaveBalances;
  final Map<String, dynamic>? activeAttendance;
  final Map<String, dynamic>? myShift;
  final Map<String, dynamic>? upcomingHoliday;
  final bool canSeeLeave;
  final bool canSeePulse;
  final bool canSeeCalendar;
  final bool canSeeMyAttendance;
  final bool canSeeMyShift;
  final bool loading;
  final String? error;
  final Future<void> Function() onRetry;
  final VoidCallback? onOpenAttendance;
  final VoidCallback? onOpenLeave;
  final ValueChanged<String>? onOpenModule;

  @override
  Widget build(BuildContext context) {
    final nameParts = user.fullName.trim().split(RegExp(r'\s+'));
    final firstName = nameParts.isEmpty || nameParts.first.isEmpty ? 'there' : nameParts.first;
    final activeEmployees = _intValue(stats['active_employees']);
    final presentToday = _intValue(stats['present_today']);
    final onLeaveToday = _intValue(stats['on_leave_today']);
    final todayRecord = _todaysAttendance(user, recentAttendance);
    final pending = <Widget>[];
    if (canSeeLeave && leaveBalances.isNotEmpty) {
      pending.add(_LeaveBalanceTile(item: _headlineLeaveBalance(leaveBalances)));
    }
    if (canSeePulse) {
      pending.add(_TeamWorkingTile(
        activeEmployees: activeEmployees,
        presentToday: presentToday,
        recentAttendance: recentAttendance,
      ));
    }
    if (canSeeCalendar) {
      pending.add(_UpcomingHolidayTile(holiday: upcomingHoliday));
    }
    if (canSeeMyAttendance) {
      pending.add(_MyAttendanceTile(attendance: activeAttendance, todayRecord: todayRecord));
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 27, 14, 112),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DashboardGreeting(greeting: greeting, firstName: firstName),
              const SizedBox(height: 18),
              _DashboardQuickActions(
                user: user,
                onOpenLeave: onOpenLeave,
                onOpenModule: onOpenModule,
              ),
              const SizedBox(height: 22),
              if (loading)
                const _DashboardLoadingCard()
              else if (error != null)
                ErrorNotice(message: error!, onRetry: () => unawaited(onRetry()))
              else ...[
                if (canSeeMyAttendance) ...[
                  _AttendanceHeroCard(
                    active: activeAttendance,
                    todayRecord: todayRecord,
                    shift: canSeeMyShift ? myShift : null,
                    canPunch: user.can('attendance.punch'),
                    onOpen: onOpenAttendance,
                  ),
                  const SizedBox(height: 18),
                ],
                _DashboardModuleGrid(
                  modules: _modulesFor(user),
                  onOpenModule: onOpenModule,
                ),
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SummaryGrid(children: pending),
                ],
                if (canSeePulse) ...[
                  const SizedBox(height: 17),
                  _WorkforcePulseCard(
                    activeEmployees: activeEmployees,
                    presentToday: presentToday,
                    onLeaveToday: onLeaveToday,
                    canSeeLeave: canSeeLeave,
                  ),
                ],
                if (recentAttendance.isNotEmpty || canSeeMyAttendance) ...[
                  const SizedBox(height: 17),
                  _RecentActivityCard(
                    items: recentAttendance,
                    onOpen: onOpenAttendance,
                  ),
                ],
              ],
              const SizedBox(height: 10),
              if (loading) const SizedBox(height: 1),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardGreeting extends StatelessWidget {
  const _DashboardGreeting({required this.greeting, required this.firstName});

  final String greeting;
  final String firstName;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$greeting, $firstName! 👋',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 22,
              height: 1.18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Welcome to ${BrandConfig.productName}',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
}

class _DashboardQuickActions extends StatelessWidget {
  const _DashboardQuickActions({
    required this.user,
    required this.onOpenLeave,
    required this.onOpenModule,
  });

  final SessionUser user;
  final VoidCallback? onOpenLeave;
  final ValueChanged<String>? onOpenModule;

  @override
  Widget build(BuildContext context) {
    final actions = <_QuickActionData>[];
    if (user.canAny(const [
          'idcard.read',
          'idcard.read.team',
          'idcard.read.self',
          'idcard.update',
          'gatepass.read',
          'gatepass.read.team',
          'gatepass.read.self',
          'gatepass.create',
          'gatepass.manage',
        ]) &&
        onOpenModule != null) {
      actions.add(_QuickActionData(
        label: 'ID Card & Pass',
        icon: Icons.badge_outlined,
        primary: false,
        onTap: () => onOpenModule!('id_card'),
      ));
    }
    if (user.can('leave.create') && onOpenLeave != null) {
      actions.add(_QuickActionData(
        label: 'Apply Leave',
        icon: Icons.send_rounded,
        primary: true,
        onTap: onOpenLeave!,
      ));
    }
    if (actions.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final width = actions.length == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: actions
              .map(
                (action) => SizedBox(
                  width: width,
                  height: 46,
                  child: _QuickActionButton(action: action),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _QuickActionData {
  const _QuickActionData({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({required this.action});

  final _QuickActionData action;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(25),
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(25),
          child: Ink(
            decoration: BoxDecoration(
              color: action.primary ? null : Colors.white,
              gradient: action.primary
                  ? const LinearGradient(
                      colors: [Color(0xFF0B9B70), Color(0xFF10B98B)],
                    )
                  : null,
              borderRadius: BorderRadius.circular(25),
              border: action.primary ? null : Border.all(color: AppColors.line),
              boxShadow: action.primary
                  ? const [
                      BoxShadow(
                        color: Color(0x2410A77B),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ]
                  : const [],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  action.icon,
                  size: 18,
                  color: action.primary ? Colors.white : AppColors.success,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: action.primary ? Colors.white : AppColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _AttendanceHeroCard extends StatelessWidget {
  const _AttendanceHeroCard({
    required this.active,
    required this.todayRecord,
    required this.shift,
    required this.canPunch,
    required this.onOpen,
  });

  final Map<String, dynamic>? active;
  final Map<String, dynamic>? todayRecord;
  final Map<String, dynamic>? shift;
  final bool canPunch;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final checkedIn = active != null;
    final recordedToday = todayRecord != null;
    final location = checkedIn
        ? stringValue(active!['location_name']).trim()
        : '';
    final manual = checkedIn && stringValue(active!['punch_source']) == 'manual';
    final badgeText = checkedIn
        ? manual
            ? 'Manager-approved manual punch'
            : location.isNotEmpty
                ? '$location · Geofence verified'
                : 'Attendance session active'
        : recordedToday
            ? 'Attendance recorded today'
            : canPunch
                ? 'Ready for GPS-verified attendance'
                : 'Attendance overview';
    final shiftName = stringValue(
      shift?['shift_name'],
      fallback: checkedIn ? 'Work session' : 'My shift',
    );
    final durationMinutes = _shiftDurationMinutes(shift);
    final shiftLabel = durationMinutes == null
        ? shiftName.toUpperCase()
        : '${shiftName.toUpperCase()} (${_formatTargetDuration(durationMinutes)})';
    final actionLabel = !canPunch
        ? 'View Attendance'
        : checkedIn
            ? 'Punch Out'
            : recordedToday
                ? 'Open Attendance'
                : 'Punch In';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(29),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF071329), Color(0xFF0B1E39), Color(0xFF082D32)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2415233A),
            blurRadius: 24,
            offset: Offset(0, 13),
          ),
        ],
      ),
      child: Column(
        children: [
          _AttendanceStatusBadge(
            label: badgeText,
            manual: manual,
            active: checkedIn,
          ),
          const SizedBox(height: 10),
          const Align(alignment: Alignment.centerLeft, child: _LiveClockPill()),
          const SizedBox(height: 23),
          Text(
            shiftLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFD6DEE9),
              fontSize: 13,
              letterSpacing: 1.05,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 19),
          _ElapsedShiftRing(active: active, shift: shift, hasTodayRecord: recordedToday),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0CA67E), Color(0xFF10C29B)],
                ),
                borderRadius: BorderRadius.circular(23),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4410C29B),
                    blurRadius: 17,
                    spreadRadius: 1,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(23),
                child: InkWell(
                  onTap: onOpen,
                  borderRadius: BorderRadius.circular(23),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        canPunch ? Icons.fingerprint_rounded : Icons.access_time_rounded,
                        color: Colors.white,
                        size: 23,
                      ),
                      const SizedBox(width: 9),
                      Text(
                        actionLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceStatusBadge extends StatelessWidget {
  const _AttendanceStatusBadge({
    required this.label,
    required this.manual,
    required this.active,
  });

  final String label;
  final bool manual;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tint = manual ? const Color(0xFFFFCF78) : const Color(0xFF42D9AE);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: active ? 0.12 : 0.09),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tint.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            manual
                ? Icons.verified_user_outlined
                : active
                    ? Icons.gps_fixed_rounded
                    : Icons.gps_not_fixed_rounded,
            color: tint,
            size: 16,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tint,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveClockPill extends StatefulWidget {
  const _LiveClockPill();

  @override
  State<_LiveClockPill> createState() => _LiveClockPillState();
}

class _LiveClockPillState extends State<_LiveClockPill> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF35425B).withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule_rounded, color: Color(0xFF45D9B4), size: 16),
            const SizedBox(width: 7),
            Text(
              _clockWithSeconds(_now),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _ElapsedShiftRing extends StatefulWidget {
  const _ElapsedShiftRing({required this.active, required this.shift, required this.hasTodayRecord});

  final Map<String, dynamic>? active;
  final Map<String, dynamic>? shift;
  final bool hasTodayRecord;

  @override
  State<_ElapsedShiftRing> createState() => _ElapsedShiftRingState();
}

class _ElapsedShiftRingState extends State<_ElapsedShiftRing> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _ElapsedShiftRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active?['punch_in_at'] != widget.active?['punch_in_at']) {
      _syncTimer();
    }
  }

  void _syncTimer() {
    _timer?.cancel();
    if (widget.active != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final punchIn = DateTime.tryParse(stringValue(widget.active?['punch_in_at']));
    final elapsed = punchIn == null
        ? null
        : _now.difference(punchIn.toLocal()).isNegative
            ? Duration.zero
            : _now.difference(punchIn.toLocal());
    final targetMinutes = _shiftDurationMinutes(widget.shift);
    final target = targetMinutes == null
        ? null
        : Duration(minutes: targetMinutes);
    final progress = elapsed == null || target == null || target.inSeconds <= 0
        ? 0.0
        : (elapsed.inSeconds / target.inSeconds).clamp(0.0, 1.0).toDouble();

    return Column(
      children: [
        Text(
          elapsed != null && target != null
              ? '${_elapsedHoursMinutes(elapsed)} / ${_formatTargetDuration(target.inMinutes)}'
              : elapsed != null
                  ? 'WORK SESSION IN PROGRESS'
                  : widget.hasTodayRecord
                      ? 'ATTENDANCE RECORDED TODAY'
                      : 'PUNCH STATUS',
          style: const TextStyle(
            color: Color(0xFF4ADBB5),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.35,
          ),
        ),
        const SizedBox(height: 11),
        SizedBox(
          width: 164,
          height: 164,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10C99A)),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    elapsed == null
                        ? widget.hasTodayRecord ? 'Done' : 'Ready'
                        : _elapsedClock(elapsed),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.65,
                    ),
                  ),
                  const SizedBox(height: 7),
                  if (elapsed != null && punchIn != null)
                    Text(
                      'Punched in: ${_clockWithoutSeconds(punchIn.toLocal())}',
                      style: const TextStyle(
                        color: Color(0xFFAAB7CB),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    Text(
                      widget.hasTodayRecord ? "Today's punches on file" : 'GPS attendance',
                      style: const TextStyle(
                        color: Color(0xFFAAB7CB),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardModuleGrid extends StatelessWidget {
  const _DashboardModuleGrid({
    required this.modules,
    required this.onOpenModule,
  });

  final List<_DashboardModule> modules;
  final ValueChanged<String>? onOpenModule;

  @override
  Widget build(BuildContext context) {
    if (modules.isEmpty || onOpenModule == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 9.0;
        final tileWidth = (constraints.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: modules
              .map(
                (module) => SizedBox(
                  width: tileWidth,
                  height: 83,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(21),
                    child: InkWell(
                      onTap: () => onOpenModule!(module.id),
                      borderRadius: BorderRadius.circular(21),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(21),
                          border: Border.all(color: AppColors.line),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 37,
                              height: 37,
                              decoration: BoxDecoration(
                                color: module.tint.withValues(alpha: 0.11),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(module.icon, color: module.tint, size: 21),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              module.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _DashboardModule {
  const _DashboardModule({
    required this.id,
    required this.label,
    required this.icon,
    required this.tint,
    required this.permissions,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color tint;
  final List<String> permissions;
}

List<_DashboardModule> _modulesFor(SessionUser user) {
  const candidates = <_DashboardModule>[
    _DashboardModule(
      id: 'kra',
      label: 'KRA & Goals',
      icon: Icons.track_changes_rounded,
      tint: Color(0xFF2F70D0),
      permissions: ['kra.read', 'kra.read.team', 'kra.read.self', 'kra.manage'],
    ),
    _DashboardModule(
      id: 'shifts',
      label: 'Shift Roster',
      icon: Icons.schedule_rounded,
      tint: Color(0xFF8B39D7),
      permissions: ['shifts.read', 'shifts.read.team', 'shifts.read.self', 'shifts.manage'],
    ),
    _DashboardModule(
      id: 'kyc',
      label: 'KYC & Letters',
      icon: Icons.folder_shared_outlined,
      tint: Color(0xFF008C68),
      permissions: ['kyc.read', 'kyc.read.self', 'kyc.create.self', 'kyc.manage'],
    ),
    _DashboardModule(
      id: 'recognition',
      label: 'Star Workers',
      icon: Icons.emoji_events_outlined,
      tint: Color(0xFFB77914),
      permissions: ['recognition.read', 'recognition.manage'],
    ),
    _DashboardModule(
      id: 'helpdesk',
      label: 'Helpdesk',
      icon: Icons.support_agent_rounded,
      tint: Color(0xFFD34F6B),
      permissions: ['helpdesk.create', 'helpdesk.read.self', 'helpdesk.manage'],
    ),
    _DashboardModule(
      id: 'calendar',
      label: 'Calendar',
      icon: Icons.calendar_month_rounded,
      tint: Color(0xFF6653D8),
      permissions: ['calendar.read'],
    ),
  ];
  return candidates
      .where((module) => user.canAny(module.permissions))
      .toList(growable: false);
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: children
              .map((child) => SizedBox(width: width, child: child))
              .toList(growable: false),
        );
      },
    );
  }
}

class _LeaveBalanceTile extends StatelessWidget {
  const _LeaveBalanceTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final allowance = _doubleValue(item['allowance_days']);
    final used = _doubleValue(item['used_days']);
    final remaining = _doubleValue(item['remaining_days']);
    final progress = allowance <= 0 ? 0.0 : (used / allowance).clamp(0.0, 1.0).toDouble();
    final type = stringValue(item['leave_type'], fallback: 'Leave');
    final quotaLabel = type.toLowerCase().contains('earned') ? 'EL' : type;

    return _SummaryCard(
      title: 'Leave Balance',
      icon: Icons.spa_outlined,
      tint: AppColors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  _numberText(remaining),
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 24,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              const Flexible(
                child: Text(
                  'days left',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_numberText(allowance)} $quotaLabel Allocated Quota',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFFE0E7EF),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.success),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamWorkingTile extends StatelessWidget {
  const _TeamWorkingTile({
    required this.activeEmployees,
    required this.presentToday,
    required this.recentAttendance,
  });

  final int activeEmployees;
  final int presentToday;
  final List<Map<String, dynamic>> recentAttendance;

  @override
  Widget build(BuildContext context) {
    final percent = activeEmployees <= 0
        ? 0
        : ((presentToday / activeEmployees) * 100).round().clamp(0, 100);
    final names = <String>{};
    for (final item in recentAttendance) {
      if (item['punch_out_at'] != null) continue;
      final name = stringValue(item['employee_name']).trim();
      if (name.isNotEmpty) names.add(name);
      if (names.length == 4) break;
    }

    return _SummaryCard(
      title: 'Team Working',
      icon: Icons.groups_2_outlined,
      tint: AppColors.blue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$presentToday',
                style: const TextStyle(color: AppColors.ink, fontSize: 24, height: 1, fontWeight: FontWeight.w800, letterSpacing: -0.8),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 5, bottom: 1),
                child: Text('/', style: TextStyle(color: AppColors.muted, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 5, bottom: 1),
                child: Text('$activeEmployees', style: const TextStyle(color: AppColors.muted, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$percent% checked in',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          SizedBox(
            height: 27,
            child: names.isEmpty
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Team status', style: TextStyle(color: AppColors.muted, fontSize: 10)),
                  )
                : Row(
                    children: names
                        .map(
                          (name) => Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: ClipOval(child: PersonAvatar(name: name, size: 25)),
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingHolidayTile extends StatelessWidget {
  const _UpcomingHolidayTile({required this.holiday});

  final Map<String, dynamic>? holiday;

  @override
  Widget build(BuildContext context) {
    final hasHoliday = holiday != null && holiday!.isNotEmpty;
    final name = hasHoliday ? stringValue(holiday!['name'], fallback: 'Upcoming holiday') : 'No upcoming holiday';
    final dateLabel = hasHoliday ? _displayDate(holiday!['holiday_date']) : 'Check the holiday calendar';
    final days = hasHoliday ? int.tryParse(stringValue(holiday!['days_until'])) : null;
    final countdown = days == null
        ? ''
        : days == 0
            ? 'Today'
            : days == 1
                ? 'Tomorrow'
                : 'in $days days';
    final description = hasHoliday ? stringValue(holiday!['description']).trim() : '';

    return _SummaryCard(
      title: 'Upcoming Holiday',
      icon: Icons.celebration_outlined,
      tint: const Color(0xFFB77914),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 13),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.ink, fontSize: 17, height: 1.05, fontWeight: FontWeight.w800, letterSpacing: -0.3),
          ),
          const SizedBox(height: 8),
          Text(
            [dateLabel, if (description.isNotEmpty) description].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 10, height: 1.3, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (countdown.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(color: AppColors.softAmber, borderRadius: BorderRadius.circular(20)),
                child: Text(countdown, style: const TextStyle(color: Color(0xFF9B6413), fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
    );
  }
}

class _MyAttendanceTile extends StatelessWidget {
  const _MyAttendanceTile({required this.attendance, required this.todayRecord});

  final Map<String, dynamic>? attendance;
  final Map<String, dynamic>? todayRecord;

  @override
  Widget build(BuildContext context) {
    final checkedIn = attendance != null;
    final punchIn = checkedIn ? DateTime.tryParse(stringValue(attendance!['punch_in_at'])) : null;
    final punchOut = !checkedIn && todayRecord?['punch_out_at'] != null
        ? DateTime.tryParse(stringValue(todayRecord?['punch_out_at']))
        : null;
    final subtitle = punchIn != null
        ? 'Punched in at ${_clockWithoutSeconds(punchIn.toLocal())}'
        : punchOut != null
            ? 'Punched out at ${_clockWithoutSeconds(punchOut.toLocal())}'
            : 'No open attendance record';
    final status = checkedIn
        ? 'In progress'
        : punchOut != null
            ? 'Completed today'
            : 'No active punch';

    return _SummaryCard(
      title: 'My Attendance',
      icon: Icons.insert_chart_outlined_rounded,
      tint: const Color(0xFF7A3ED1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 14),
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: checkedIn
                  ? const Color(0xFF7A3ED1)
                  : punchOut != null
                      ? AppColors.success
                      : AppColors.ink,
              fontSize: checkedIn ? 19 : 16,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 10, height: 1.3, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Row(
            children: [
              Icon(
                checkedIn
                    ? Icons.trending_up_rounded
                    : punchOut != null
                        ? Icons.check_circle_outline_rounded
                        : Icons.schedule_rounded,
                size: 14,
                color: checkedIn || punchOut != null ? AppColors.success : AppColors.muted,
              ),
              const SizedBox(width: 4),
              Text(
                checkedIn
                    ? 'Active shift'
                    : punchOut != null
                        ? "Today's punch saved"
                        : 'No active punch',
                style: TextStyle(color: checkedIn || punchOut != null ? AppColors.success : AppColors.muted, fontSize: 10, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.icon,
    required this.tint,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color tint;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        height: 172,
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: AppColors.line.withValues(alpha: 0.9)),
          boxShadow: const [
            BoxShadow(color: Color(0x0A13233A), blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  width: 33,
                  height: 33,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, size: 18, color: tint),
                ),
              ],
            ),
            Expanded(child: Align(alignment: Alignment.topLeft, child: child)),
          ],
        ),
      );
}

class _WorkforcePulseCard extends StatelessWidget {
  const _WorkforcePulseCard({
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
    final present = activeEmployees <= 0 ? 0 : presentToday.clamp(0, activeEmployees).toInt();
    final onLeave = canSeeLeave ? onLeaveToday.clamp(0, activeEmployees).toInt() : 0;
    final notCheckedIn = (activeEmployees - present - onLeave).clamp(0, activeEmployees).toInt();
    final progress = activeEmployees <= 0 ? 0.0 : present / activeEmployees;
    final metrics = <_PulseMetricData>[
      _PulseMetricData(label: 'Present', value: present, tint: AppColors.success, fill: const Color(0xFFF0FBF6)),
      _PulseMetricData(label: 'Not checked in', value: notCheckedIn, tint: const Color(0xFFAF4960), fill: const Color(0xFFFFF4F5)),
      if (canSeeLeave)
        _PulseMetricData(label: 'On leave', value: onLeave, tint: const Color(0xFFB77914), fill: const Color(0xFFFFFAEE)),
    ];

    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.9)),
        boxShadow: const [BoxShadow(color: Color(0x0A13233A), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Workforce Pulse', style: TextStyle(color: AppColors.ink, fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(color: AppColors.softGreen, borderRadius: BorderRadius.circular(20)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: AppColors.success, size: 7),
                    SizedBox(width: 5),
                    Text('Live', style: TextStyle(color: Color(0xFF13885D), fontSize: 10, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Live attendance summary for your team', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 11,
              backgroundColor: const Color(0xFFE6EBF1),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.success),
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: metrics
                .map(
                  (metric) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: metric == metrics.last ? 0 : 8),
                      child: _PulseMetricCard(metric: metric, total: activeEmployees),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _PulseMetricData {
  const _PulseMetricData({required this.label, required this.value, required this.tint, required this.fill});
  final String label;
  final int value;
  final Color tint;
  final Color fill;
}

class _PulseMetricCard extends StatelessWidget {
  const _PulseMetricCard({required this.metric, required this.total});

  final _PulseMetricData metric;
  final int total;

  @override
  Widget build(BuildContext context) {
    final percent = total <= 0 ? 0 : ((metric.value / total) * 100).round();
    return Container(
      constraints: const BoxConstraints(minHeight: 99),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
      decoration: BoxDecoration(
        color: metric.fill,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: metric.tint.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(metric.label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: metric.tint, fontSize: 10, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text('${metric.value}', style: TextStyle(color: metric.tint, fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text('$percent%', style: TextStyle(color: metric.tint, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.items, required this.onOpen});

  final List<Map<String, dynamic>> items;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(19, 19, 19, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: AppColors.line.withValues(alpha: 0.9)),
          boxShadow: const [BoxShadow(color: Color(0x0A13233A), blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Recent Activity', style: TextStyle(color: AppColors.ink, fontSize: 17, fontWeight: FontWeight.w800))),
                if (onOpen != null)
                  TextButton(
                    onPressed: onOpen,
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: const Text('View All', style: TextStyle(color: AppColors.blue, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            const Text('History and real-time status', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 13),
                child: Text('No recent attendance activity.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              )
            else
              ...items.take(4).toList().asMap().entries.map((entry) {
                final item = entry.value;
                final punchedOut = item['punch_out_at'] != null;
                final timestamp = punchedOut ? item['punch_out_at'] : item['punch_in_at'];
                final when = DateTime.tryParse(stringValue(timestamp));
                final timeLabel = when == null ? 'recently' : _relativeTime(when.toLocal());
                final activityLabel = punchedOut
                    ? 'Punched out at ${_clockWithoutSeconds(DateTime.tryParse(stringValue(item['punch_out_at']))?.toLocal())}'
                    : 'Punched in at ${_clockWithoutSeconds(DateTime.tryParse(stringValue(item['punch_in_at']))?.toLocal())}';
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          ClipOval(child: PersonAvatar(name: stringValue(item['employee_name'], fallback: 'Team member'), size: 39)),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(stringValue(item['employee_name'], fallback: 'Team member'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text(activityLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(timeLabel, style: const TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    if (entry.key < items.take(4).length - 1)
                      const Divider(height: 1, indent: 50),
                  ],
                );
              }),
          ],
        ),
      );
}

class _DashboardLoadingCard extends StatelessWidget {
  const _DashboardLoadingCard();

  @override
  Widget build(BuildContext context) => Container(
        height: 225,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: AppColors.line),
        ),
        child: const Center(child: LoadingView(label: 'Loading your dashboard…')),
      );
}

Map<String, dynamic> _headlineLeaveBalance(List<Map<String, dynamic>> balances) {
  for (final balance in balances) {
    final type = stringValue(balance['leave_type']).toLowerCase();
    if (type.contains('earned') || type == 'el') return balance;
  }
  return balances.first;
}

Map<String, dynamic>? _todaysAttendance(
  SessionUser user,
  List<Map<String, dynamic>> records,
) {
  final employeeId = user.employeeId;
  if (employeeId == null) return null;
  final todayUtc = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  for (final record in records) {
    if (_intValue(record['employee_id']) != employeeId) continue;
    if (stringValue(record['punch_in_at']).startsWith(todayUtc)) return record;
  }
  return null;
}

int _intValue(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _numberText(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

String _displayDate(Object? value) {
  final parsed = DateTime.tryParse(stringValue(value));
  if (parsed == null) return stringValue(value, fallback: 'Date not set');
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
}

int? _shiftDurationMinutes(Map<String, dynamic>? shift) {
  if (shift == null) return null;
  final start = _minutesOfDay(shift['start_time']);
  final end = _minutesOfDay(shift['end_time']);
  if (start == null || end == null) return null;
  final total = end > start ? end - start : end + 24 * 60 - start;
  final breakMinutes = _intValue(shift['break_minutes']);
  final duration = total - breakMinutes;
  return duration > 0 ? duration : null;
}

int? _minutesOfDay(Object? value) {
  final parts = value?.toString().split(':');
  if (parts == null || parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return hour * 60 + minute;
}

String _formatTargetDuration(int minutes) {
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (remainingMinutes == 0) return '$hours HOURS';
  return '$hours H ${remainingMinutes.toString().padLeft(2, '0')} M';
}

String _elapsedHoursMinutes(Duration duration) =>
    '${duration.inHours.toString().padLeft(2, '0')}h ${(duration.inMinutes % 60).toString().padLeft(2, '0')}m';

String _elapsedClock(Duration duration) =>
    '${duration.inHours.toString().padLeft(2, '0')}:${(duration.inMinutes % 60).toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

String _clockWithSeconds(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final period = value.hour >= 12 ? 'pm' : 'am';
  return '${hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')} $period';
}

String _clockWithoutSeconds(DateTime? value) {
  if (value == null) return '—';
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final period = value.hour >= 12 ? 'pm' : 'am';
  return '${hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')} $period';
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.isNegative || difference.inSeconds < 60) return 'Just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  final days = difference.inDays;
  return '${days}d ago';
}
