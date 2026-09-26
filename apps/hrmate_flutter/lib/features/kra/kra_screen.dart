import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// My KRA (web parity: /kra) — navy hero with auto-score ring, goal cards
/// with weight pills + progress bars, self-update while OPEN, past quarters.
final kraProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await ref.read(apiProvider).get<Map<String, dynamic>>('/api/kra');
  return res.data ?? const {};
});

const _qtrs = ['', 'Jan–Mar', 'Apr–Jun', 'Jul–Sep', 'Oct–Dec'];

String _trim(num v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

class KraScreen extends ConsumerWidget {
  const KraScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final data = ref.watch(kraProvider);

    return Scaffold(
      backgroundColor: HMC.bg,
      appBar: AppBar(title: Text(T.s('My KRA', lang))),
      body: RefreshIndicator(
        color: HMC.primary,
        onRefresh: () async => ref.invalidate(kraProvider),
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator(color: HMC.primary)),
          error: (e, _) => ListView(children: [
            HmMessage(icon: Icons.wifi_off_rounded, text: apiErrorMessage(e), onRetry: () => ref.invalidate(kraProvider), retryLabel: T.s('Retry', lang)),
          ]),
          data: (j) {
            if (j['linked'] == false) {
              return ListView(children: [
                HmMessage(
                  icon: Icons.link_off,
                  text: T.s('Account not linked', lang),
                  hint: T.s('Link your login to an employee profile first — then your KRA will show up here.', lang),
                ),
              ]);
            }
            final cycles = asMaps(j['cycles']);
            if (cycles.isEmpty) {
              return ListView(children: [
                HmMessage(
                  icon: Icons.track_changes_outlined,
                  text: T.s('No KRA assigned yet', lang),
                  hint: T.s('Once HR publishes the quarter cycle, your goals will appear here', lang),
                ),
              ]);
            }
            Map<String, dynamic>? active;
            for (final c in cycles) {
              if (c['status'] == 'OPEN' || c['status'] == 'SCORING') {
                active = c;
                break;
              }
            }
            final history = cycles.where((c) => c['status'] == 'CLOSED').toList();
            return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
              if (active != null) ...[
                _Hero(cycle: active, lang: lang),
                const SizedBox(height: 12),
                _GoalsCard(cycle: active, lang: lang),
              ],
              if (history.isNotEmpty) ...[
                const SizedBox(height: 12),
                _HistoryCard(history: history, lang: lang),
              ],
            ]);
          },
        ),
      ),
    );
  }
}

/// Navy hero: quarter label + status badge + auto-score ring (web KraView).
class _Hero extends StatelessWidget {
  final Map<String, dynamic> cycle;
  final String lang;
  const _Hero({required this.cycle, required this.lang});

  @override
  Widget build(BuildContext context) {
    final status = '${cycle['status']}';
    final score = Map<String, dynamic>.from((cycle['score'] as Map?) ?? const {});
    final pct = (score['pct'] as num?)?.toDouble() ?? 0;
    final frac = (pct / 100).clamp(0.0, 1.0);
    final scoring = status == 'SCORING';
    final tone = scoring ? HMC.amber : HMC.primary;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
      decoration: BoxDecoration(
        color: HMC.ink,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 22, offset: Offset(0, 10))],
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(
            'Q${cycle['quarter']} ${cycle['year']} · ${_qtrs[(cycle['quarter'] as num?)?.toInt() ?? 1]}'.toUpperCase(),
            style: const TextStyle(color: HMC.primary, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: 2.2),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: tone.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
            child: Text(
              scoring ? T.s('HR SCORING', lang) : status,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: tone, letterSpacing: 0.8),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              startAngle: -math.pi / 2,
              endAngle: -math.pi / 2 + math.pi * 2,
              colors: [HMC.primary, HMC.primary, Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.08)],
              stops: [0.0, frac, frac, 1.0],
            ),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 86,
            height: 86,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: HMC.ink),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${_trim(pct)}%', style: const TextStyle(color: HMC.primary, fontWeight: FontWeight.w900, fontSize: 22)),
              Text(T.s('auto score', lang).toUpperCase(),
                  style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          scoring
              ? T.s('HR review in progress — edits are frozen', lang)
              : T.s('Update your progress — HR finalizes the score at quarter end', lang),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 11.5),
        ),
      ]),
    );
  }
}

/// Goal cards: title + target/achieved + WT pill + bar + pts + self-update.
class _GoalsCard extends ConsumerWidget {
  final Map<String, dynamic> cycle;
  final String lang;
  const _GoalsCard({required this.cycle, required this.lang});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = asMaps(cycle['goals']);
    final canEdit = cycle['status'] == 'OPEN';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x140A1628), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(children: [for (final g in goals) _GoalTile(goal: g, lang: lang, canEdit: canEdit)]),
    );
  }
}

class _GoalTile extends ConsumerStatefulWidget {
  final Map<String, dynamic> goal;
  final String lang;
  final bool canEdit;
  const _GoalTile({required this.goal, required this.lang, required this.canEdit});

  @override
  ConsumerState<_GoalTile> createState() => _GoalTileState();
}

class _GoalTileState extends ConsumerState<_GoalTile> {
  final _ctl = TextEditingController();
  bool _busy = false;
  bool _seeded = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = double.tryParse(_ctl.text.trim());
    if (v == null || v < 0) {
      hmToast(context, T.s('Please enter a valid number (0 or more).', widget.lang));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).patch('/api/kra', data: {'goalId': '${widget.goal['id']}', 'achieved': v});
      ref.invalidate(kraProvider);
      if (mounted) hmToast(context, T.s('Progress update ✓', widget.lang), ok: true);
    } catch (e) {
      if (mounted) hmToast(context, apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.goal;
    final lang = widget.lang;
    final pct = (g['pct'] as num?)?.toDouble() ?? 0;
    final weight = (g['weight'] as num?)?.toInt() ?? 0;
    final pts = ((((pct.clamp(0, 100)) * weight) / 100) * 10).round() / 10;
    final unit = (g['unit'] as String?) ?? '';
    final bar = pct >= 75 ? HMC.primary : pct >= 50 ? HMC.amber : HMC.danger;
    if (!_seeded) {
      _ctl.text = '${(g['achieved'] as num?) ?? 0}';
      _seeded = true;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${g['title']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: HMC.ink)),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${T.s('Target', lang)}: ', style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5)),
                  TextSpan(
                      text: '${_trim((g['target'] as num?) ?? 0)}${unit.isEmpty ? '' : ' $unit'}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: HMC.ink)),
                  TextSpan(text: ' · ${T.s('Achieved', lang)}: ', style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5)),
                  TextSpan(
                      text: '${_trim((g['achieved'] as num?) ?? 0)}${unit.isEmpty ? '' : ' $unit'}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: HMC.emeraldDeep)),
                ]),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: HMC.primaryFade,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: HMC.primary.withValues(alpha: 0.35)),
            ),
            child: Text('$weight% WT',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: HMC.primaryDark)),
          ),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: const Color(0xFFF1F5F9),
            valueColor: AlwaysStoppedAnimation(bar),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text('${_trim(pct)}% ${T.s('complete', lang)}', style: TextStyle(color: Colors.grey.shade400, fontSize: 10.5, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('${_trim(pts)}/$weight ${T.s('pts', lang)}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 10.5, fontWeight: FontWeight.w600)),
        ]),
        if (widget.canEdit) ...[
          const SizedBox(height: 10),
          Container(height: 1, color: const Color(0xFFF1F5F9)),
          const SizedBox(height: 10),
          Row(children: [
            SizedBox(
              width: 96,
              child: TextField(
                controller: _ctl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: HMC.bg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(unit, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: HMC.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('✎ ${T.s('Update', lang)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
            ),
          ]),
        ],
      ]),
    );
  }
}

/// Past quarters: quarter label + pct + verdict badge (web history card).
class _HistoryCard extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final String lang;
  const _HistoryCard({required this.history, required this.lang});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x140A1628), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(T.s('Past quarters 🏁', lang),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: HMC.ink)),
        const SizedBox(height: 6),
        for (final c in history) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: 'Q${c['quarter']} ${c['year']} ',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: HMC.ink)),
                  TextSpan(
                      text: '(${_qtrs[(c['quarter'] as num?)?.toInt() ?? 1]})',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 11.5)),
                ])),
              ),
              Builder(builder: (_) {
                final pct = ((c['score'] as Map?)?['pct'] as num?)?.toDouble() ?? 0;
                final tone = pct >= 75 ? HMC.emeraldDeep : pct >= 50 ? HMC.amber : HMC.danger;
                final verdict = pct >= 75
                    ? T.s('Excellent', lang)
                    : pct >= 50
                        ? T.s('Good', lang)
                        : T.s('Needs work', lang);
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${_trim(pct)}%', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: tone)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: Text(verdict, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: tone)),
                  ),
                ]);
              }),
            ]),
          ),
        ],
      ]),
    );
  }
}
