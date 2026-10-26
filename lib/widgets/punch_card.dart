import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/attendance.dart';
import '../providers/attendance_provider.dart';
import 'common.dart';

/// Today's punch in / punch out card with a live clock.
class PunchCard extends StatefulWidget {
  const PunchCard({super.key});

  @override
  State<PunchCard> createState() => _PunchCardState();
}

class _PunchCardState extends State<PunchCard> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _punch() async {
    final provider = context.read<AttendanceProvider>();
    final wasIn = provider.today?.hasPunchedIn ?? false;
    final error = await provider.punch();
    if (!mounted) return;
    if (error != null) {
      showSnack(context, error, error: true);
    } else {
      showSnack(context, wasIn ? 'Punched out at ${Fmt.time(DateTime.now())}' : 'Punched in at ${Fmt.time(DateTime.now())}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AttendanceProvider>();
    final today = provider.today;
    final isOff = today != null &&
        (today.status == AttendanceStatus.holiday ||
            today.status == AttendanceStatus.weekend ||
            today.status == AttendanceStatus.leave) &&
        !today.hasPunchedIn;
    final done = today?.hasPunchedOut ?? false;
    final working = today?.isWorking ?? false;

    String statusText;
    if (today == null) {
      statusText = 'Loading...';
    } else if (done) {
      statusText = 'Day complete';
    } else if (working) {
      statusText = 'You are punched in';
    } else if (isOff) {
      statusText = today.note ?? today.status.label;
    } else {
      statusText = 'Not punched in yet';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primary, AppTheme.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Fmt.fullDay(_now), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(Fmt.time(_now), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(statusText, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _timeBox('Punch In', Fmt.time(today?.punchIn)),
              const SizedBox(width: 10),
              _timeBox('Punch Out', Fmt.time(today?.punchOut)),
              const SizedBox(width: 10),
              _timeBox('Worked', today?.hasPunchedIn == true ? Fmt.duration(today!.workedDuration) : '--'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: working ? AppTheme.danger : AppTheme.primary,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.4),
              ),
              onPressed: (today == null || done || provider.punching) ? null : _punch,
              icon: provider.punching
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(working ? Icons.logout : Icons.fingerprint),
              label: Text(
                done ? 'Attendance marked' : (working ? 'Punch Out' : 'Punch In'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeBox(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }
}
