import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Ticket categories — same enum + emoji as the web helpdesk.
const kTicketCategories = <String, (String, String)>{
  'MACHINE': ('🔧', 'Machine'),
  'SALARY': ('💰', 'Salary'),
  'UNIFORM': ('👕', 'Uniform'),
  'CANTEEN': ('🍽️', 'Canteen'),
  'SAFETY': ('🦺', 'Safety'),
  'OTHER': ('➕', 'Other'),
};

const kTicketStatusLabel = <String, String>{
  'OPEN': 'Open',
  'IN_PROGRESS': 'In progress',
  'RESOLVED': 'Resolved',
  'CLOSED': 'Closed',
};

Color ticketTone(String status) => switch (status) {
      'OPEN' => const Color(0xFF2563EB),
      'IN_PROGRESS' => HMC.amber,
      'RESOLVED' => HMC.emeraldDeep,
      _ => Colors.blueGrey,
    };

/// (scope, status) → ticket list payload
typedef HelpdeskQuery = ({String scope, String status});

final helpdeskListProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, HelpdeskQuery>((ref, q) async {
  final res = await ref.read(apiProvider).get<Map<String, dynamic>>(
        '/api/helpdesk',
        queryParameters: {'scope': q.scope, if (q.scope == 'inbox') 'status': q.status},
      );
  return res.data ?? const <String, dynamic>{};
});

/// Helpdesk: my tickets (+ Team inbox with status filter for ADMIN/HR),
/// raise-ticket sheet, unread dots. Thread lives in HelpdeskThreadScreen.
class HelpdeskScreen extends ConsumerStatefulWidget {
  const HelpdeskScreen({super.key});

  @override
  ConsumerState<HelpdeskScreen> createState() => _HelpdeskScreenState();
}

class _HelpdeskScreenState extends ConsumerState<HelpdeskScreen> {
  String _scope = 'mine';
  String _status = 'OPEN';

  HelpdeskQuery get _q => (scope: _scope, status: _status);

  Future<void> _openThread(String id) async {
    await context.push('/helpdesk/$id');
    if (mounted) ref.invalidate(helpdeskListProvider(_q));
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final role = ref.watch(sessionStoreProvider).user?.role ?? 'EMPLOYEE';
    final staff = role != 'EMPLOYEE';
    final data = ref.watch(helpdeskListProvider(_q));

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(title: Text(T.s('Helpdesk', lang))),
      floatingActionButton: _scope == 'mine'
          ? FloatingActionButton.extended(
              backgroundColor: HMC.primary,
              foregroundColor: HMC.ink,
              onPressed: () async {
                final id = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const _NewTicketSheet(),
                );
                if (id != null && mounted) {
                  ref.invalidate(helpdeskListProvider(_q));
                  await _openThread(id);
                }
              },
              icon: const Icon(Icons.add_comment_outlined),
              label: Text(T.s('New ticket', lang), style: const TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: Column(children: [
        if (staff)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'mine', label: Text(T.s('My tickets', lang)), icon: const Icon(Icons.person_outline)),
                ButtonSegment(value: 'inbox', label: Text(T.s('Team inbox', lang)), icon: const Icon(Icons.inbox_outlined)),
              ],
              selected: {_scope},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _scope = s.first),
            ),
          ),
        if (staff && _scope == 'inbox')
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              children: [
                for (final s in const ['OPEN', 'IN_PROGRESS', 'RESOLVED', 'ALL'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_statusChipLabel(s, lang, data.valueOrNull)),
                      selected: _status == s,
                      showCheckmark: false,
                      selectedColor: HMC.ink,
                      labelStyle: TextStyle(
                        color: _status == s ? Colors.white : HMC.ink,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: (_) => setState(() => _status = s),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            color: HMC.primary,
            onRefresh: () async => ref.invalidate(helpdeskListProvider(_q)),
            child: data.when(
              loading: () => const Center(child: CircularProgressIndicator(color: HMC.primary)),
              error: (e, _) => ListView(children: [
                HmMessage(
                  icon: Icons.wifi_off_rounded,
                  text: apiErrorMessage(e),
                  onRetry: () => ref.invalidate(helpdeskListProvider(_q)),
                  retryLabel: T.s('Retry', lang),
                ),
              ]),
              data: (j) {
                if (j['linked'] == false) {
                  return ListView(children: [
                    HmMessage(
                      icon: Icons.link_off,
                      text: T.s('Account not linked', lang),
                      hint: T.s('Link your login to an employee profile first — then Helpdesk opens.', lang),
                    ),
                  ]);
                }
                final rows = asMaps(j['tickets']);
                if (rows.isEmpty) {
                  return ListView(children: [
                    HmMessage(
                      icon: Icons.support_agent_outlined,
                      text: T.s('No tickets here', lang),
                      hint: _scope == 'mine'
                          ? T.s('Machine, salary, uniform, canteen or safety — raise one with “New ticket”.', lang)
                          : null,
                    ),
                  ]);
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => _TicketTile(
                    t: rows[i],
                    lang: lang,
                    showEmployee: _scope == 'inbox',
                    onTap: () => _openThread('${rows[i]['id']}'),
                  ),
                );
              },
            ),
          ),
        ),
      ]),
    );
  }

  String _statusChipLabel(String s, String lang, Map<String, dynamic>? data) {
    final label = s == 'ALL' ? T.s('All', lang) : T.s(kTicketStatusLabel[s] ?? s, lang);
    final counts = data?['counts'];
    if (s != 'ALL' && counts is Map && counts[s] is num && (counts[s] as num) > 0) return '$label · ${counts[s]}';
    return label;
  }
}

class _TicketTile extends StatelessWidget {
  final Map<String, dynamic> t;
  final String lang;
  final bool showEmployee;
  final VoidCallback onTap;
  const _TicketTile({required this.t, required this.lang, required this.showEmployee, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cat = kTicketCategories['${t['category']}'] ?? ('❔', '${t['category']}');
    final status = '${t['status']}';
    final tone = ticketTone(status);
    final last = t['last'] is Map ? Map<String, dynamic>.from(t['last'] as Map) : null;
    final emp = t['employee'] is Map ? Map<String, dynamic>.from(t['employee'] as Map) : null;
    final unread = t['unread'] == true;

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
              child: Text(cat.$1, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      '${t['subject']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: unread ? FontWeight.w900 : FontWeight.w700, color: HMC.ink, fontSize: 15),
                    ),
                  ),
                  if (unread)
                    Container(
                      width: 9,
                      height: 9,
                      margin: const EdgeInsets.only(left: 6),
                      decoration: const BoxDecoration(color: HMC.primary, shape: BoxShape.circle),
                    ),
                ]),
                const SizedBox(height: 2),
                Text(
                  [
                    T.s(cat.$2, lang),
                    if (showEmployee && emp != null) '${emp['name']} (${emp['code']})',
                    shortStamp(t['updatedAt']),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
                if (last != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${last['isStaff'] == true ? '🛡️ ' : ''}${last['body']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text(
                T.s(kTicketStatusLabel[status] ?? status, lang),
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: tone),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Raise a ticket: category grid + subject + details. Pops with the new id.
class _NewTicketSheet extends ConsumerStatefulWidget {
  const _NewTicketSheet();

  @override
  ConsumerState<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends ConsumerState<_NewTicketSheet> {
  String? _category;
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final lang = ref.read(langProvider);
    if (_category == null) {
      setState(() => _error = T.s('Please pick a category.', lang));
      return;
    }
    if (_subject.text.trim().length < 4) {
      setState(() => _error = T.s('Subject needs 4+ characters.', lang));
      return;
    }
    if (_body.text.trim().isEmpty) {
      setState(() => _error = T.s('Please add details — HR needs the full context.', lang));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(apiProvider).post<Map<String, dynamic>>('/api/helpdesk', data: {
        'category': _category,
        'subject': _subject.text.trim(),
        'body': _body.text.trim(),
      });
      final t = res.data?['ticket'];
      if (!mounted) return;
      hmToast(context, T.s('Ticket sent to HR 📨', lang), ok: true);
      Navigator.of(context).pop(t is Map ? '${t['id']}' : null);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = apiErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 14),
          Text(T.s('New ticket', lang), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: HMC.ink)),
          const SizedBox(height: 4),
          Text(T.s('Complaints & suggestions — straight to HR', lang),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in kTicketCategories.entries)
              ChoiceChip(
                label: Text('${e.value.$1}  ${T.s(e.value.$2, lang)}'),
                selected: _category == e.key,
                showCheckmark: false,
                selectedColor: HMC.primaryFade,
                side: BorderSide(color: _category == e.key ? HMC.emeraldDeep : Colors.grey.shade300),
                onSelected: (_) => setState(() => _category = e.key),
              ),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _subject,
            maxLength: 140,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: T.s('Subject', lang)),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: T.s('Details', lang), alignLabelWithHint: true),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: HMC.danger, fontWeight: FontWeight.w600)),
            ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: HMC.emeraldDeep),
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.send_rounded),
            label: Text(T.s('Send to HR', lang)),
          ),
        ]),
      ),
    );
  }
}
