import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/app_nav.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Bell feed — same source as the web bell (`/api/alerts`): routed pending
/// approvals for SM/AGM/admin + decisions on my own requests (7 days).
final alertsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.read(apiProvider).get<Map<String, dynamic>>('/api/alerts');
  return asMaps(res.data?['items']);
});

/// Header bell with unread badge (Home greeting row).
class AlertsBell extends ConsumerWidget {
  const AlertsBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(alertsProvider).maybeWhen(data: (l) => l.length, orElse: () => 0);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showAlertsSheet(context),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.notifications_none_rounded, color: HMC.ink, size: 22),
          ),
          if (count > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFF43F5E),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: HMC.bg, width: 2),
                ),
                child: Text(
                  count > 9 ? '9+' : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

Future<void> showAlertsSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => const _AlertsSheet(),
  );
}

class _AlertsSheet extends ConsumerWidget {
  const _AlertsSheet();

  static IconData _icon(String? kind) => switch (kind) {
        'leaf' => Icons.eco_outlined,
        'clock' => Icons.schedule,
        'badge' => Icons.badge_outlined,
        'calendar' => Icons.swap_horiz,
        'check' => Icons.check_circle_outline,
        'x' => Icons.cancel_outlined,
        _ => Icons.notifications_none,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final alerts = ref.watch(alertsProvider);
    final canApprove = ref.watch(sessionStoreProvider).user?.canApprove ?? false;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
            child: Row(children: [
              Expanded(
                child: Text(T.s('Notifications', lang),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: HMC.ink)),
              ),
              IconButton(
                tooltip: T.s('Refresh', lang),
                icon: const Icon(Icons.refresh, color: HMC.ink),
                onPressed: () => ref.invalidate(alertsProvider),
              ),
            ]),
          ),
          Flexible(
            child: alerts.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: HMC.primary)),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(28),
                child: Text(apiErrorMessage(e), textAlign: TextAlign.center, style: const TextStyle(color: HMC.danger)),
              ),
              data: (items) => items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
                      child: Column(children: [
                        Icon(Icons.notifications_off_outlined, size: 40, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(T.s('All clear — nothing pending', lang), style: TextStyle(color: Colors.grey.shade600)),
                      ]),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                      itemBuilder: (_, i) {
                        final a = items[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(color: HMC.ink, borderRadius: BorderRadius.circular(11)),
                            child: Icon(_icon(a['kind'] as String?), color: HMC.emerald, size: 20),
                          ),
                          title: Text('${a['title'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: HMC.ink)),
                          subtitle: Text(
                            [a['body'], shortStamp(a['at'])].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
                          onTap: () {
                            Navigator.of(context).pop();
                            openAppPath(ref, a['appPath'] as String?, canApprove: canApprove);
                          },
                        );
                      },
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}
