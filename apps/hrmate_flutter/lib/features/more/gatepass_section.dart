import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// My gate passes (web parity: GatePassForm on /idcard) — dashed request form
/// (date / exit / return / reason) + status list with ENTRY VERIFIED chips.
/// Lives under the badge on the ID-card screen. POST → /api/gate-passes,
/// approve/reject happens in the Approvals tab (kind=gate), same as web.
final gatePassesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.read(apiProvider).get<Map<String, dynamic>>('/api/gate-passes');
  return asMaps(res.data?['passes']);
});

class GatePassCard extends ConsumerStatefulWidget {
  const GatePassCard({super.key});

  @override
  ConsumerState<GatePassCard> createState() => _GatePassCardState();
}

class _GatePassCardState extends ConsumerState<GatePassCard> {
  DateTime _date = DateTime.now();
  TimeOfDay _exit = const TimeOfDay(hour: 14, minute: 0);
  TimeOfDay? _ret;
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _submit(String lang) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post('/api/gate-passes', data: {
        'date': _iso(_date),
        'exitAt': _hhmm(_exit),
        if (_ret != null) 'returnAt': _hhmm(_ret!),
        if (_reason.text.trim().isNotEmpty) 'reason': _reason.text.trim(),
      });
      ref.invalidate(gatePassesProvider);
      if (!mounted) return;
      _reason.clear();
      setState(() => _ret = null);
      hmToast(context, T.s('Gate pass requested ✓ Manager will review it.', lang), ok: true);
    } catch (e) {
      if (mounted) hmToast(context, apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final canGate = ref.watch(sessionStoreProvider).user?.perms['canGatePass'] ?? true;
    final passes = ref.watch(gatePassesProvider);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x140A1628), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(T.s('Digital Gate Passes', lang),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: HMC.ink)),
              Text(T.s('Exit permissions & factory duty passes', lang),
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5)),
            ]),
          ),
          passes.maybeWhen(
            data: (rows) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: HMC.primaryFade, borderRadius: BorderRadius.circular(999)),
              child: Text('${rows.length}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: HMC.primaryDark)),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ]),
        const SizedBox(height: 12),
        if (!canGate)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300, width: 1.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              Text(T.s('Gate passes are turned off for you', lang),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: HMC.ink)),
              const SizedBox(height: 4),
              Text(T.s('Ask the super admin to allow this feature.', lang),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            ]),
          )
        else ...[
          // ── request form (web: dashed emerald box) ──
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: HMC.primaryFade.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: HMC.primary.withValues(alpha: 0.45)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: _pickTile(icon: Icons.calendar_month_outlined, label: _iso(_date), onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (d != null) setState(() => _date = d);
                })),
                const SizedBox(width: 8),
                Expanded(child: _pickTile(icon: Icons.logout, label: _hhmm(_exit), onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: _exit);
                  if (t != null) setState(() => _exit = t);
                })),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _pickTile(icon: Icons.login, label: _ret == null ? T.s('Return time (optional)', lang) : _hhmm(_ret!), dim: _ret == null, onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: _ret ?? const TimeOfDay(hour: 16, minute: 0));
                  if (t != null) setState(() => _ret = t);
                })),
                if (_ret != null)
                  IconButton(
                    tooltip: T.s('Clear', lang),
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _ret = null),
                  ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: _reason,
                maxLines: 1,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: T.s('Reason (e.g. urgent work at home)', lang),
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: HMC.ink,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _busy ? null : () => _submit(lang),
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.meeting_room_outlined, size: 20),
                label: Text(T.s('+ Request Gate Pass', lang), style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          // ── passes list (web: slate tiles + status badge + verified chip) ──
          passes.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(color: HMC.primary)),
            ),
            error: (e, _) => Text(apiErrorMessage(e), style: const TextStyle(color: HMC.danger, fontSize: 12.5)),
            data: (rows) => rows.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(color: HMC.bg, borderRadius: BorderRadius.circular(14)),
                    child: Text(T.s('No gate passes yet', lang),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5)),
                  )
                : Column(children: [for (final g in rows) _passTile(g, lang)]),
          ),
        ],
      ]),
    );
  }

  Widget _pickTile({required IconData icon, required String label, required VoidCallback onTap, bool dim = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, size: 17, color: dim ? Colors.grey.shade400 : HMC.ink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12.5, color: dim ? Colors.grey.shade500 : HMC.ink)),
          ),
        ]),
      ),
    );
  }

  Widget _passTile(Map<String, dynamic> g, String lang) {
    final status = '${g['status'] ?? 'PENDING'}';
    final tone = status == 'APPROVED'
        ? HMC.emeraldDeep
        : status == 'REJECTED'
            ? HMC.danger
            : HMC.amber;
    final d = DateTime.tryParse('${g['date']}')?.toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = d == null ? '' : '${d.day} ${months[d.month - 1]}';
    final ret = g['returnAt'];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: HMC.bg, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.meeting_room_outlined, size: 16, color: Colors.grey.shade400),
          const SizedBox(width: 6),
          Expanded(
            child: Text(T.s('Personal Gate Pass', lang),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: HMC.ink)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(status, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: tone)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          '${T.s('Exit', lang)}: ${g['exitAt']}${ret != null ? ' | ${T.s('Return', lang)}: $ret' : ''} · $dateStr'
          '${g['reason'] != null && '${g['reason']}'.isNotEmpty ? ' • "${g['reason']}"' : ''}',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        if (g['verified'] == true) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: HMC.primaryFade, borderRadius: BorderRadius.circular(8)),
            child: Text('✓ ${T.s('ENTRY VERIFIED', lang)}',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: HMC.primaryDark)),
          ),
        ],
      ]),
    );
  }
}
