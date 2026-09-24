import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

final myRequestsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(apiProvider);
  final res = await dio.get<Map<String, dynamic>>('/api/requests');
  return ((res.data?['requests'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
});

/// More tab: user card, language switch, attendance history, my requests,
/// logout — every entry is live (no placeholders).
class MoreTab extends ConsumerWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final session = ref.watch(sessionStoreProvider);
    final user = session.user;

    return Scaffold(
      backgroundColor: HMC.bg,
      appBar: AppBar(title: Text(T.s('More', lang)), centerTitle: false),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: HMC.ink,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              child: Text(
                (user?.name ?? '?').trim().isEmpty ? '?' : (user!.name.trim()[0]).toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.name ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                Text(user?.email ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: HMC.primaryFade, borderRadius: BorderRadius.circular(10)),
              child: Text(user?.role ?? '', style: const TextStyle(color: HMC.primary, fontSize: 10.5, fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        _Tile(
          icon: Icons.history_edu,
          title: T.s('Attendance history', lang),
          subtitle: T.s('Month view · manual punch / OT', lang),
          onTap: () => context.push('/attendance'),
        ),
        _Tile(
          icon: Icons.badge_outlined,
          title: T.s('My ID card', lang),
          subtitle: T.s('Digital badge · gate QR · share', lang),
          onTap: () => context.push('/idcard'),
        ),
        _Tile(
          icon: Icons.calendar_month_outlined,
          title: T.s('My Roster', lang),
          subtitle: T.s('Week shifts · swap requests', lang),
          onTap: () => context.push('/roster'),
        ),
        _Tile(
          icon: Icons.outbox_outlined,
          title: T.s('My requests', lang),
          subtitle: T.s('Manual punches & overtime status', lang),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
            builder: (_) => const _MyRequestsSheet(),
          ),
        ),
        _Tile(
          icon: Icons.translate,
          title: T.s('Language', lang),
          subtitle: lang == 'pa' ? 'ਪੰਜਾਬੀ' : 'English',
          onTap: () async => saveLang(ref, lang == 'pa' ? 'en' : 'pa'),
        ),
        _Tile(
          icon: Icons.lock_reset,
          title: T.s('Change password', lang),
          subtitle: T.s('Set a fresh secret for this device', lang),
          onTap: () => context.push('/set-password'),
        ),
        const SizedBox(height: 8),
        _Tile(
          icon: Icons.logout,
          danger: true,
          title: T.s('Log out', lang),
          subtitle: T.s('Sign out from this phone', lang),
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
            if (ok == true) await ref.read(sessionStoreProvider).clear();
          },
        ),
        const SizedBox(height: 20),
        Center(child: Text('HRMate · v0.2.0 · Phase 2', style: TextStyle(color: Colors.grey.shade400, fontSize: 11))),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;
  const _Tile({required this.icon, required this.title, required this.subtitle, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final c = danger ? HMC.danger : HMC.ink;
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
              backgroundColor: (danger ? HMC.danger : HMC.primary).withValues(alpha: 0.1),
              child: Icon(icon, color: danger ? HMC.danger : HMC.primaryDark, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: c)),
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
                              Text('${r['type']} · ${date?.day}/${date?.month}', style: const TextStyle(fontWeight: FontWeight.w800, color: HMC.ink, fontSize: 13)),
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
