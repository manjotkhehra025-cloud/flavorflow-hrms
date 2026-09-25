import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'home_data.dart';
import 'punch_queue.dart';
import '../alerts/alerts_sheet.dart';

/// Dashboard: greeting + shift card + giant punch button (idle)
/// or live timer ring (clocked in), per approved mockups p2-home-*.png.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // live ring/digits
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final session = ref.watch(sessionStoreProvider);
    final block = ref.watch(attendanceProvider);
    final queue = ref.watch(punchQueueProvider);
    final name = (session.user?.name ?? '').split(' ').first;
    final first = name.isEmpty ? '' : name[0].toUpperCase() + name.substring(1).toLowerCase();

    return Scaffold(
      backgroundColor: HMC.bg,
      body: RefreshIndicator(
        color: HMC.primary,
        onRefresh: () async {
          ref.invalidate(attendanceProvider);
          ref.invalidate(alertsProvider);
        },
        child: block.when(
          loading: () => const Center(child: CircularProgressIndicator(color: HMC.primary)),
          error: (e, _) => ListView(children: [
            const SizedBox(height: 160),
            Icon(Icons.cloud_off, size: 44, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            Center(child: Text('${T.s('Could not load home', lang)} — pull to retry')),
          ]),
          data: (b) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
            children: [
              // Greeting + lang pill
              Row(children: [
                Expanded(
                  child: Text(
                    '${T.s('ਸਤਿ ਸ੍ਰੀ ਅਕਾਲ', lang)}, $first 👋',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: HMC.ink),
                  ),
                ),
                const SizedBox(width: 8),
                const AlertsBell(),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => saveLang(ref, lang == 'pa' ? 'en' : 'pa'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: HMC.ink,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      lang == 'pa' ? 'EN | ਪੰ' : 'EN | ਪੰ',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 14),

              // Shift card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  color: HMC.ink,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 18, offset: Offset(0, 8))],
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  const Icon(Icons.location_on_outlined, color: Colors.white70, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'KHD · ${_shiftLine(b, lang)}${b.isWeeklyOff ? ' · ${T.s('Weekly-off day', lang)}' : ''}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
              ),

              if (queue.pending != null) ...[
                const SizedBox(height: 14),
                _QueueBanner(queued: queue.pending!.queuedAtMs, busy: queue.syncBusy),
              ],

              const SizedBox(height: 44),
              Center(
                child: (b.checkInAt == null || b.checkOutAt != null)
                    ? _PunchIdleCircle(canPunch: ref.read(sessionStoreProvider).user?.perms['canPunch'] ?? true, lang: lang)
                    : _LiveRing(start: b.checkInAt!, durationH: (b.shift['durationH'] as num).toDouble(), lang: lang),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  (b.checkInAt == null)
                      ? '${T.s('GPS + selfie required', lang)}${b.geofenceEnabled ? ' · fence on' : ''}'
                      : (b.checkOutAt == null
                          ? '${T.s('check-in at', lang)} ${_hm(b.checkInAt!)}'
                          : T.s('You are done for today ✓', lang)),
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5),
                ),
              ),

              const SizedBox(height: 26),
              // amber chips from /api/attendance
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                if ((b.chips['pendingOT'] ?? 0) > 0)
                  _Chip(icon: Icons.schedule, text: T.s('OT pending approval', lang)),
                if ((b.chips['pendingPunch'] ?? 0) > 0)
                  _Chip(icon: Icons.fact_check_outlined, text: T.s('Manual punch pending', lang)),
              ]),
              const SizedBox(height: 14),
              if (b.checkInAt != null && b.checkOutAt == null)
                Center(
                  child: OutlinedButton(
                    onPressed: () => context.push('/punch', extra: 'checkout'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
                      shape: const StadiumBorder(),
                      side: BorderSide(color: Colors.grey.shade400),
                    ),
                    child: Text(
                      '${T.s('Check out', lang)} · shift ${(b.shift['durationH'] as num).toStringAsFixed(1)}h',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: HMC.ink),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _shiftLine(AttendanceBlock b, String lang) {
    final name = b.shift['name'] ?? 'General Day Shift';
    final start = b.shift['startTime'] ?? '08:00';
    final hrs = (b.shift['durationH'] as num).toStringAsFixed(1);
    return '$name · $start–${((int.tryParse(start.split(':')[0]) ?? 8) + (double.tryParse(hrs) ?? 9)).toInt()}:30 · $hrs h';
  }

  String _hm(DateTime d) {
    final h = d.toLocal().hour.toString().padLeft(2, '0');
    final m = d.toLocal().minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _PunchIdleCircle extends ConsumerWidget {
  final bool canPunch;
  final String lang;
  const _PunchIdleCircle({required this.canPunch, required this.lang});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(children: [
      GestureDetector(
        onTap: !canPunch ? null : () => context.push('/punch', extra: 'checkin'),
        child: Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 40, offset: Offset(0, 18))],
          ),
          child: Center(
            child: Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(shape: BoxShape.circle, color: canPunch ? HMC.ink : Colors.grey.shade300),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.fingerprint, size: 40, color: Colors.white),
                const SizedBox(height: 8),
                Text(
                  canPunch ? T.s('CHECK IN', lang) : T.s('PUNCH OFF', lang),
                  style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 1.4),
                ),
              ]),
            ),
          ),
        ),
      ),
      if (!canPunch) ...[
        const SizedBox(height: 10),
        Text(T.s('Self punch is turned OFF — ask super admin', lang), style: const TextStyle(color: HMC.warn, fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    ]);
  }
}

class _LiveRing extends StatelessWidget {
  final DateTime start;
  final double durationH;
  final String lang;
  const _LiveRing({required this.start, required this.durationH, required this.lang});
  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(start.toLocal());
    final secs = elapsed.inSeconds;
    final h = secs ~/ 3600, m = (secs % 3600) ~/ 60, s = secs % 60;
    final frac = (secs / (durationH * 3600)).clamp(0.0, 1.0);

    return SizedBox(
      width: 236,
      height: 236,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: 236,
          height: 236,
          child: CircularProgressIndicator(
            value: frac,
            strokeWidth: 14,
            backgroundColor: HMC.ink,
            valueColor: const AlwaysStoppedAnimation(HMC.primary),
            strokeCap: StrokeCap.round,
          ),
        ),
        Container(
          width: 192,
          height: 192,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: HMC.ink),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
              '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w200, fontFeatures: []),
            ),
            Text(T.s('Elapsed Time', lang), style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Chip({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: HMC.warnFade, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: HMC.warn),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: HMC.warn, fontWeight: FontWeight.w700, fontSize: 12.5)),
      ]),
    );
  }
}

class _QueueBanner extends ConsumerWidget {
  final int queued;
  final bool busy;
  const _QueueBanner({required this.queued, required this.busy});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final when = DateTime.fromMillisecondsSinceEpoch(queued).toLocal();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: HMC.warnFade, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        const Icon(Icons.sync_problem, color: HMC.warn),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${T.s('Punch saved offline', lang)} · ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(color: HMC.warn, fontWeight: FontWeight.w700),
          ),
        ),
        TextButton(
          onPressed: busy
              ? null
              : () async {
                  final err = await ref.read(punchQueueProvider).sync(ref);
                  ref.invalidate(attendanceProvider);
                  if (err != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  }
                },
          child: Text(busy ? '…' : T.s('Sync', lang), style: const TextStyle(fontWeight: FontWeight.w900, color: HMC.warn)),
        ),
      ]),
    );
  }
}
