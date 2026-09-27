import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/app_lock.dart';
import '../../core/push.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

final myRequestsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(apiProvider);
  final res = await dio.get<Map<String, dynamic>>('/api/requests');
  return ((res.data?['requests'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
});

/// More tab — module cards (same destinations, product skin instead of a settings list).
class MoreTab extends ConsumerWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final session = ref.watch(sessionStoreProvider);
    final user = session.user;
    final initial = (user?.name ?? '?').trim().isEmpty ? '?' : (user!.name.trim()[0]).toUpperCase();

    final modules = <_Mod>[
      _Mod(Icons.badge_outlined, T.s('My ID card', lang), T.s('Badge · gate QR', lang), () => context.push('/idcard')),
      _Mod(Icons.currency_rupee, T.s('My payslips', lang), T.s('Share / PDF', lang), () => context.push('/payslips')),
      _Mod(Icons.calendar_month_outlined, T.s('My Roster', lang), T.s('Week · swap', lang), () => context.push('/roster')),
      _Mod(Icons.celebration_outlined, T.s('Holidays', lang), T.s('Plant calendar', lang), () => context.push('/holidays')),
      _Mod(Icons.support_agent_outlined, T.s('Helpdesk', lang), T.s('Ticket · chat', lang), () => context.push('/helpdesk')),
      _Mod(Icons.description_outlined, T.s('My Letters', lang), T.s('Share / PDF', lang), () => context.push('/letters')),
      _Mod(Icons.history_edu, T.s('Attendance history', lang), T.s('Month · punch / OT', lang), () => context.push('/attendance')),
      _Mod(Icons.forum_outlined, T.s('Social Wall', lang), T.s('Wins · shout-outs', lang), () => context.push('/social')),
      _Mod(Icons.track_changes_outlined, T.s('My KRA', lang), T.s('Quarterly targets', lang), () => context.push('/kra')),
      _Mod(Icons.outbox_outlined, T.s('My requests', lang), T.s('Manual punch · OT', lang), () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
            builder: (_) => const _MyRequestsSheet(),
          )),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F8),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            decoration: BoxDecoration(color: HMC.ink, borderRadius: BorderRadius.circular(24)),
            child: Row(children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFF123044),
                child: Text(initial, style: const TextStyle(color: Color(0xFF6EE7B7), fontWeight: FontWeight.w900, fontSize: 20)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user?.name ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                  const SizedBox(height: 6),
                  if ((user?.role ?? '').isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFF065F46), borderRadius: BorderRadius.circular(20)),
                      child: Text(user!.role, style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 10, fontWeight: FontWeight.w900)),
                    ),
                  const SizedBox(height: 6),
                  Text(user?.email ?? '', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < modules.length; i += 2) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _ModCard(mod: modules[i])),
              const SizedBox(width: 12),
              Expanded(child: i + 1 < modules.length ? _ModCard(mod: modules[i + 1]) : const SizedBox()),
            ]),
            const SizedBox(height: 12),
          ],
          if (user?.isStaff == true) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
              child: Text(T.s('STAFF', lang), style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.2)),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _StaffPill(label: T.s('Employees', lang), onTap: () => context.push('/employees')),
              _StaffPill(label: T.s('Live Team', lang), onTap: () => context.push('/team')),
              _StaffPill(label: T.s('Duty Roster', lang), onTap: () => context.push('/duty-roster')),
              if (user?.role == 'ADMIN')
                _StaffPill(label: T.s('Employee permissions', lang), onTap: () => context.push('/permissions')),
            ]),
            const SizedBox(height: 16),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Row(children: [
              Expanded(
                child: InkWell(
                  onTap: () => saveLang(ref, lang == 'pa' ? 'en' : 'pa'),
                  child: Text(
                    '${T.s('Language', lang)}  ·  ${lang == 'pa' ? 'ਪੰਜਾਬੀ' : 'English'}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: HMC.ink),
                  ),
                ),
              ),
              InkWell(
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(T.s('Log out?', lang)),
                      content: Text(T.s('Your token on this phone will be removed.', lang)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(T.s('Cancel', lang))),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: HMC.danger),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(T.s('Log out', lang)),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  await ref.read(pushServiceProvider).stop();
                  await ref.read(sessionStoreProvider).clear();
                },
                child: Text(T.s('Log out', lang), style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          const _BiometricTile(),
          _Tile(
            icon: Icons.lock_reset,
            title: T.s('Change password', lang),
            subtitle: T.s('Set a fresh secret for this device', lang),
            onTap: () => context.push('/set-password'),
          ),
          const SizedBox(height: 8),
          Center(child: Text('HRMate · v0.9.2', style: TextStyle(color: Colors.grey.shade400, fontSize: 11))),
        ]),
      ),
    );
  }
}

class _Mod {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _Mod(this.icon, this.title, this.subtitle, this.onTap);
}

class _ModCard extends StatelessWidget {
  final _Mod mod;
  const _ModCard({required this.mod});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: mod.onTap,
        child: Container(
          height: 108,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(12)),
              child: Icon(mod.icon, color: const Color(0xFF059669), size: 20),
            ),
            const Spacer(),
            Text(mod.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: HMC.ink, fontSize: 14)),
            Text(mod.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}

class _StaffPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _StaffPill({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: HMC.ink, borderRadius: BorderRadius.circular(22)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(children: [
            CircleAvatar(
              backgroundColor: HMC.primary.withValues(alpha: 0.1),
              child: Icon(icon, color: HMC.primaryDark, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: HMC.ink)),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ]),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade300),
          ]),
        ),
      ),
    );
  }
}

String _reqLabel(String? type, String lang) => switch (type) {
      'MANUAL_IN' => T.s('Manual in', lang),
      'MANUAL_OUT' => T.s('Manual out', lang),
      'OT' => T.s('Overtime', lang),
      _ => type ?? '',
    };

class _MyRequestsSheet extends ConsumerWidget {
  const _MyRequestsSheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final reqs = ref.watch(myRequestsProvider);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(T.s('My requests', lang), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: HMC.ink)),
          const SizedBox(height: 10),
          Flexible(
            child: reqs.when(
              loading: () => const Center(child: CircularProgressIndicator(color: HMC.primary)),
              error: (e, _) => Text(apiErrorMessage(e)),
              data: (rows) => rows.isEmpty
                  ? Text(T.s('No requests yet', lang), style: TextStyle(color: Colors.grey.shade500))
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 14),
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        final status = r['status'] as String? ?? 'PENDING';
                        final tone = status == 'APPROVED'
                            ? HMC.emeraldDeep
                            : status == 'REJECTED'
                                ? HMC.danger
                                : HMC.amber;
                        final date = DateTime.tryParse('${r['date']}')?.toLocal();
                        return Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${_reqLabel(r['type'] as String?, lang)} · ${date?.day}/${date?.month}', style: const TextStyle(fontWeight: FontWeight.w800, color: HMC.ink, fontSize: 13)),
                              Text(
                                r['type'] == 'OT' ? '${r['hours']}h · ${r['reason']}' : '${r['time']} · ${r['reason']}',
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ]),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(color: tone.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: tone)),
                          ),
                        ]);
                      },
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// P6 — biometric quick-unlock switch (hidden when the phone has no sensor
/// and no screen lock).
class _BiometricTile extends ConsumerStatefulWidget {
  const _BiometricTile();

  @override
  ConsumerState<_BiometricTile> createState() => _BiometricTileState();
}

class _BiometricTileState extends ConsumerState<_BiometricTile> {
  bool? _available;

  @override
  void initState() {
    super.initState();
    ref.read(appLockProvider).available().then((v) {
      if (mounted) setState(() => _available = v);
    });
  }

  Future<void> _toggle(bool on) async {
    final lang = ref.read(langProvider);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(appLockProvider).setEnabled(on, T.s('Confirm it is you', lang));
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(T.s('Fingerprint not confirmed — unlock stays off', lang))));
      return;
    }
    messenger.showSnackBar(SnackBar(
      content: Text(on ? T.s('Fingerprint unlock is ON ✓', lang) : T.s('Fingerprint unlock is OFF', lang)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_available != true) return const SizedBox.shrink();
    final lang = ref.watch(langProvider);
    final lock = ref.watch(appLockProvider);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: HMC.primary.withValues(alpha: 0.1),
            child: const Icon(Icons.fingerprint, color: HMC.primaryDark, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(T.s('Fingerprint unlock', lang), style: const TextStyle(fontWeight: FontWeight.w800, color: HMC.ink)),
              Text(T.s('Open HRMate with your fingerprint or screen lock', lang),
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            ]),
          ),
          Switch(
            value: lock.enabled,
            activeTrackColor: HMC.primaryDark,
            onChanged: lock.busy ? null : _toggle,
          ),
        ]),
      ),
    );
  }
}
