import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<Map<String, dynamic>> _records = const [];
  List<Map<String, dynamic>> _locations = const [];
  Map<String, dynamic>? _active;
  bool _loading = true;
  bool _punching = false;
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
      final api = AppScope.of(context).api;
      final responses = await Future.wait([
        api.get('attendance', query: const {'limit': '100'}),
        api.get('locations'),
      ]);
      if (!mounted) return;
      final attendance = asJsonMap(responses[0]);
      setState(() {
        _records = asJsonList(attendance['items']);
        _active = attendance['active'] == null ? null : asJsonMap(attendance['active']);
        _locations = asJsonList(asJsonMap(responses[1])['items']);
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Position> _currentPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) throw const ApiException('Turn on location services before punching in or out.');

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw const ApiException('Location permission is required for GPS-verified attendance.');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 25),
      ),
    );
  }

  Future<void> _punch() async {
    setState(() {
      _punching = true;
      _error = null;
    });
    try {
      final api = AppScope.of(context).api;
      final wasCheckedIn = _active != null;
      final position = await _currentPosition();
      final action = wasCheckedIn ? 'punch-out' : 'punch-in';
      await api.post('attendance/$action', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy_m': position.accuracy,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(wasCheckedIn ? 'You are punched out.' : 'You are punched in.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Unable to read your location. ${error.toString()}');
    } finally {
      if (mounted) setState(() => _punching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user!;
    final canPunch = user.can('attendance.punch');
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1250),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeading(
                  title: 'Attendance',
                  subtitle: 'Your time, verified at the right place.',
                  trailing: IconButton.filledTonal(onPressed: _load, tooltip: 'Refresh attendance', icon: const Icon(Icons.refresh_rounded)),
                ),
                if (_error != null) ...[
                  ErrorNotice(message: _error!, onRetry: _load),
                  const SizedBox(height: 14),
                ],
                LayoutBuilder(builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 850;
                  final punchCard = _PunchCard(active: _active, busy: _punching, canPunch: canPunch, locationCount: _locations.where((location) => location['is_active'] == true || location['is_active'] == 1).length, onPunch: _punch);
                  final todayCard = _TodaySummary(records: _records, active: _active, canViewSelf: user.canAny(const ['attendance.read.self', 'attendance.punch']));
                  if (!wide) return Column(children: [punchCard, const SizedBox(height: 16), todayCard]);
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 6, child: punchCard), const SizedBox(width: 16), Expanded(flex: 4, child: todayCard)]);
                }),
                const SizedBox(height: 22),
                PageHeading(title: 'Attendance history', subtitle: 'Recent shifts and recorded work sites.', trailing: Text('${_records.length} records', style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600))),
                if (_loading && _records.isEmpty)
                  const SizedBox(height: 150, child: LoadingView(label: 'Loading attendance history…'))
                else if (_error != null && _records.isEmpty)
                  ErrorNotice(message: _error!, onRetry: _load)
                else if (_records.isEmpty)
                  const AppPanel(child: EmptyNotice(title: 'No attendance yet', subtitle: 'Your verified punches will show here.', icon: Icons.schedule_rounded))
                else
                  AppPanel(
                    padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 9),
                    child: Column(children: _records.map((record) => _AttendanceRow(record: record, showEmployee: user.can('attendance.read') || user.can('attendance.manage') || user.can('attendance.read.team'))).toList()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PunchCard extends StatelessWidget {
  const _PunchCard({required this.active, required this.busy, required this.canPunch, required this.locationCount, required this.onPunch});

  final Map<String, dynamic>? active;
  final bool busy;
  final bool canPunch;
  final int locationCount;
  final VoidCallback onPunch;

  @override
  Widget build(BuildContext context) {
    final checkedIn = active != null;
    final location = checkedIn ? stringValue(active!['location_name'], fallback: 'Assigned work location') : 'GPS verified at punch time';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.navy, Color(0xFF123E64), Color(0xFF0B696E)]),
        boxShadow: const [BoxShadow(color: Color(0x17132A40), blurRadius: 20, offset: Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Container(width: 9, height: 9, decoration: BoxDecoration(color: checkedIn ? const Color(0xFF43D99C) : const Color(0xFFB8C6D4), shape: BoxShape.circle)), const SizedBox(width: 9), Text(checkedIn ? 'SHIFT IN PROGRESS' : 'READY FOR YOUR SHIFT', style: const TextStyle(color: Color(0xFFD3E5EE), fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.1))]),
          const SizedBox(height: 16),
          Text(checkedIn ? 'You’re checked in.' : 'Make today count.', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(checkedIn ? 'Started ${formatDateTime(active!['punch_in_at'])}' : 'Your location is checked against an active work geofence.', style: const TextStyle(color: Color(0xFFC4D5E0), fontSize: 13)),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(13), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: Color(0xFF82E2D1), size: 19),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(checkedIn ? 'CURRENT SITE' : 'ACTIVE LOCATIONS', style: const TextStyle(color: Color(0xFFAFC4D2), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                            const SizedBox(height: 4),
                            Text(checkedIn ? location : '$locationCount available', overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (canPunch)
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: busy ? null : onPunch,
                    style: FilledButton.styleFrom(backgroundColor: checkedIn ? AppColors.success : Colors.white, foregroundColor: checkedIn ? Colors.white : AppColors.navy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
                    icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue)) : Icon(checkedIn ? Icons.logout_rounded : Icons.login_rounded, size: 18),
                    label: Text(busy ? 'Checking…' : checkedIn ? 'Punch out' : 'Punch in', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                )
              else
                const Icon(Icons.verified_user_outlined, color: Color(0xFFAFC4D2), size: 24),
            ],
          ),
          if (!canPunch) ...[
            const SizedBox(height: 13),
            const Text('Your current role can view attendance but cannot punch in or out.', style: TextStyle(color: Color(0xFFC4D5E0), fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.records, required this.active, required this.canViewSelf});
  final List<Map<String, dynamic>> records;
  final Map<String, dynamic>? active;
  final bool canViewSelf;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final todaysRecords = records.where((record) => stringValue(record['punch_in_at']).startsWith(today)).toList();
    final last = todaysRecords.isEmpty ? null : todaysRecords.first;
    if (!canViewSelf) {
      final inProgress = todaysRecords.where((record) => record['punch_out_at'] == null).length;
      return AppPanel(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Team today', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 4),
          const Text('Attendance in your authorized view', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 15),
          _SummaryLine(icon: Icons.login_rounded, label: 'Check-ins today', value: '${todaysRecords.length}', color: AppColors.blue),
          const SizedBox(height: 12),
          _SummaryLine(icon: Icons.timelapse_rounded, label: 'Shifts in progress', value: '$inProgress', color: AppColors.success),
          const SizedBox(height: 12),
          _SummaryLine(icon: Icons.history_rounded, label: 'Records shown', value: '${records.length}', color: AppColors.teal),
        ]),
      );
    }
    return AppPanel(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Today', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 4),
        const Text('Your attendance snapshot', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 15),
        _SummaryLine(icon: Icons.login_rounded, label: 'First check-in', value: last == null ? '—' : formatDateTime(last['punch_in_at']), color: AppColors.blue),
        const SizedBox(height: 12),
        _SummaryLine(icon: Icons.logout_rounded, label: 'Check-out', value: last == null || last['punch_out_at'] == null ? '—' : formatDateTime(last['punch_out_at']), color: AppColors.success),
        const SizedBox(height: 12),
        _SummaryLine(icon: Icons.timelapse_rounded, label: 'Shift status', value: active == null ? 'Not punched in' : 'In progress', color: active == null ? AppColors.muted : AppColors.success),
      ]),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(children: [Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: color, size: 18)), const SizedBox(width: 10), Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12))), Text(value, style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w700))]);
}

class _AttendanceRow extends StatelessWidget {
  const _AttendanceRow({required this.record, required this.showEmployee});
  final Map<String, dynamic> record;
  final bool showEmployee;

  @override
  Widget build(BuildContext context) {
    final checkedOut = record['punch_out_at'] != null;
    final duration = _shiftDuration(record['punch_in_at'], record['punch_out_at']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth > 650;
        return Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.schedule_rounded, color: AppColors.blue, size: 20)),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(showEmployee ? stringValue(record['employee_name'], fallback: 'My shift') : 'My shift', style: const TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text('${formatDate(record['punch_in_at'])} · ${stringValue(record['location_name'], fallback: 'Work site')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11))])),
          if (wide) Expanded(child: Text('${formatDateTime(record['punch_in_at'])} – ${checkedOut ? formatDateTime(record['punch_out_at']) : 'Now'}', style: const TextStyle(color: AppColors.muted, fontSize: 11))),
          Text(duration, style: const TextStyle(color: AppColors.ink, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          StatusBadge(status: checkedOut ? 'complete' : 'present'),
        ]);
      }),
    );
  }
}

String _shiftDuration(Object? startValue, Object? endValue) {
  final start = DateTime.tryParse(stringValue(startValue));
  final end = DateTime.tryParse(stringValue(endValue)) ?? DateTime.now();
  if (start == null) return '—';
  final difference = end.difference(start);
  if (difference.isNegative) return '—';
  final hours = difference.inHours;
  final minutes = difference.inMinutes.remainder(60);
  return '${hours}h ${minutes}m';
}
