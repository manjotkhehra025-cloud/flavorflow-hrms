import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../alerts/alerts_sheet.dart';
import 'home_data.dart';
import 'punch_queue.dart';

/// V4 Home — approved mockup: mockups/v4-home-more.png (Home frame).
/// Punch / timer / checkout behaviour is unchanged.
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
      if (mounted) setState(() {});
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
    final initial = first.isEmpty ? '?' : first[0];
    final canPunch = session.user?.perms['canPunch'] ?? true;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      body: SafeArea(
        child: RefreshIndicator(
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
            data: (b) {
              final shift = _shiftHours(b);
              final todayLabel = b.checkOutAt != null
                  ? T.s('DONE', lang)
                  : b.checkInAt != null
                      ? '${T.s('In', lang)} ${_hm(b.checkInAt!)}'
                      : T.s('Not in yet', lang);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                children: [
                  _HeroCard(
                    initial: initial,
                    greeting: '${T.s('ਸਤਿ ਸ੍ਰੀ ਅਕਾਲ', lang)}, $first',
                    subtitle: [
                      if ((b.shift['name'] as String?)?.trim().isNotEmpty == true) b.shift['name'] as String,
                      shift,
                      if (b.isWeeklyOff) T.s('Weekly-off day', lang),
                    ].join(' · '),
                    lang: lang,
                    onLang: () => saveLang(ref, lang == 'pa' ? 'en' : 'pa'),
                  ),
                  if (queue.pending != null) ...[
                    const SizedBox(height: 14),
                    _QueueBanner(queued: queue.pending!.queuedAtMs, busy: queue.syncBusy),
                  ],
                  const SizedBox(height: 28),
                  Center(
                    child: b.checkOutAt != null
                        ? _PunchChrome(
                            child: _PunchCore(
                              icon: Icons.check_circle_outline,
                              label: T.s('DONE', lang),
                            ),
                          )
                        : b.checkInAt == null
                            ? _PunchChrome(
                                onTap: !canPunch ? null : () => context.push('/punch', extra: 'checkin'),
                                dim: !canPunch,
                                child: _PunchCore(
                                  icon: Icons.fingerprint,
                                  label: canPunch ? T.s('CHECK IN', lang) : T.s('PUNCH OFF', lang),
                                ),
                              )
                            : _PunchChrome(
                                progress: _elapsedFrac(b.checkInAt!, (b.shift['durationH'] as num?)?.toDouble() ?? 9),
                                onTap: () => context.push('/punch', extra: 'checkout'),
                                child: _LiveCore(start: b.checkInAt!, lang: lang),
                              ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      !canPunch
                          ? T.s('Self punch is turned OFF — ask super admin', lang)
                          : b.checkOutAt != null
                              ? T.s('You are done for today ✓', lang)
                              : b.checkInAt != null
                                  ? '${T.s('check-in at', lang)} ${_hm(b.checkInAt!)}'
                                  : '${T.s('GPS + selfie required', lang)}${b.geofenceEnabled ? ' · ${T.s('fence on', lang)}' : ''}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: !canPunch ? HMC.warn : const Color(0xFF64748B),
                        fontSize: 12.5,
                        fontWeight: !canPunch ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(children: [
                    Expanded(
                      child: _StatCard(
                        key: const ValueKey('home-stat-shift'),
                        dark: true,
                        label: T.s('Shift', lang),
                        value: shift,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        key: const ValueKey('home-stat-today'),
                        dark: false,
                        label: T.s('Today', lang),
                        value: todayLabel,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                    if ((b.chips['pendingOT'] ?? 0) > 0)
                      _Chip(icon: Icons.schedule, text: T.s('OT pending approval', lang)),
                    if ((b.chips['pendingPunch'] ?? 0) > 0)
                      _Chip(icon: Icons.fact_check_outlined, text: T.s('Manual punch pending', lang)),
                  ]),
                  if (b.checkInAt != null && b.checkOutAt == null) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: OutlinedButton(
                        onPressed: () => context.push('/punch', extra: 'checkout'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
                          shape: const StadiumBorder(),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          foregroundColor: HMC.ink,
                        ),
                        child: Text(
                          '${T.s('Check out', lang)} · shift ${(b.shift['durationH'] as num).toStringAsFixed(1)}h',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _shiftHours(AttendanceBlock b) {
    final start = (b.shift['startTime'] as String?) ?? '08:00';
    final durH = (b.shift['durationH'] as num?)?.toDouble() ?? 9;
    final parts = start.split(':');
    final totalMin = (int.tryParse(parts[0]) ?? 8) * 60 + (parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0) + (durH * 60).round();
    final end = '${((totalMin ~/ 60) % 24).toString().padLeft(2, '0')}:${(totalMin % 60).toString().padLeft(2, '0')}';
    return '$start–$end';
  }

  double _elapsedFrac(DateTime start, double durationH) {
    return (DateTime.now().difference(start.toLocal()).inSeconds / (durationH * 3600)).clamp(0.0, 1.0);
  }

  String _hm(DateTime d) {
    final local = d.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _HeroCard extends StatelessWidget {
  final String initial, greeting, subtitle, lang;
  final VoidCallback onLang;
  const _HeroCard({
    required this.initial, required this.greeting, required this.subtitle,
    required this.lang, required this.onLang,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('home-hero'),
      padding: const EdgeInsets.fromLTRB(14, 16, 10, 16),
      decoration: BoxDecoration(
        color: HMC.ink,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: const Color(0xFF123044),
          child: Text(initial, style: const TextStyle(color: Color(0xFF6EE7B7), fontWeight: FontWeight.w800, fontSize: 20)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(greeting, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
        const AlertsBell(onNavy: true),
        const SizedBox(width: 4),
        InkWell(
          key: const ValueKey('home-lang'),
          borderRadius: BorderRadius.circular(16),
          onTap: onLang,
          child: Container(
            width: 32, height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Color(0xFF0F2138), shape: BoxShape.circle),
            child: Text(lang == 'pa' ? 'ਪੰ' : 'EN',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 9)),
          ),
        ),
      ]),
    );
  }
}

class _PunchChrome extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool dim;
  final double? progress;
  const _PunchChrome({required this.child, this.onTap, this.dim = false, this.progress});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('home-punch'),
      onTap: onTap,
      child: SizedBox(
        width: 248, height: 248,
        child: Stack(alignment: Alignment.center, children: [
          Container(
            width: 248, height: 248,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: const Color(0xFF10B981).withValues(alpha: dim ? 0.08 : 0.28), blurRadius: 36, spreadRadius: 4)],
            ),
          ),
          Container(
            width: 236, height: 236,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFD1FAE5), width: 14),
            ),
          ),
          SizedBox(
            width: 208, height: 208,
            child: CircularProgressIndicator(
              value: progress == null ? 1 : progress,
              strokeWidth: 8,
              backgroundColor: const Color(0xFFD1FAE5),
              valueColor: AlwaysStoppedAnimation(dim ? Colors.grey.shade400 : const Color(0xFF10B981)),
              strokeCap: StrokeCap.round,
            ),
          ),
          Container(
            width: 172, height: 172,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dim ? Colors.grey.shade400 : HMC.ink),
            child: child,
          ),
        ]),
      ),
    );
  }
}

class _PunchCore extends StatelessWidget {
  final IconData icon;
  final String label;
  const _PunchCore({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 40, color: const Color(0xFF6EE7B7)),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
    ]);
  }
}

class _LiveCore extends StatelessWidget {
  final DateTime start;
  final String lang;
  const _LiveCore({required this.start, required this.lang});

  @override
  Widget build(BuildContext context) {
    final secs = DateTime.now().difference(start.toLocal()).inSeconds;
    final h = secs ~/ 3600, m = (secs % 3600) ~/ 60, s = secs % 60;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(
        '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w200),
      ),
      Text(T.s('Elapsed Time', lang), style: const TextStyle(color: Colors.white54, fontSize: 12)),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  final bool dark;
  final String label, value;
  const _StatCard({super.key, required this.dark, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: dark ? HMC.ink : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: dark ? null : Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
        const SizedBox(height: 4),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: dark ? Colors.white : HMC.ink)),
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
