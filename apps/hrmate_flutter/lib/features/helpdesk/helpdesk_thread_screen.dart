import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'helpdesk_screen.dart';

/// Ticket chat thread: bubbles (mine right / theirs left), reply bar, and a
/// status menu for ADMIN/HR (Open → In progress → Resolved → Closed).
class HelpdeskThreadScreen extends ConsumerStatefulWidget {
  final String id;
  const HelpdeskThreadScreen({super.key, required this.id});

  @override
  ConsumerState<HelpdeskThreadScreen> createState() => _HelpdeskThreadScreenState();
}

class _HelpdeskThreadScreenState extends ConsumerState<HelpdeskThreadScreen> {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  Map<String, dynamic>? _ticket;
  List<Map<String, dynamic>> _replies = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(apiProvider).get<Map<String, dynamic>>('/api/helpdesk/${widget.id}');
      final t = res.data?['ticket'];
      if (!mounted) return;
      if (t is Map) {
        final m = Map<String, dynamic>.from(t);
        setState(() {
          _ticket = m;
          _replies = asMaps(m['replies']);
          _error = null;
        });
        _jumpToEnd();
      }
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _ctl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final res = await ref.read(apiProvider).post<Map<String, dynamic>>(
            '/api/helpdesk/${widget.id}',
            data: {'body': text},
          );
      final r = res.data?['reply'];
      if (!mounted) return;
      setState(() {
        if (r is Map) _replies.add(Map<String, dynamic>.from(r));
        _ctl.clear();
        final t = _ticket;
        // first staff reply flips OPEN → IN_PROGRESS server-side; mirror it
        if (t != null && t['canSetStatus'] == true && t['status'] == 'OPEN') t['status'] = 'IN_PROGRESS';
      });
      _jumpToEnd();
    } catch (e) {
      if (mounted) hmToast(context, apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _setStatus(String status) async {
    final lang = ref.read(langProvider);
    try {
      await ref.read(apiProvider).patch('/api/helpdesk/${widget.id}', data: {'status': status});
      if (!mounted) return;
      setState(() {
        final t = _ticket;
        if (t != null) {
          t['status'] = status;
          t['canReply'] = status != 'CLOSED';
        }
      });
      hmToast(context, '${T.s('Status', lang)}: ${T.s(kTicketStatusLabel[status] ?? status, lang)} ✔', ok: true);
    } catch (e) {
      if (mounted) hmToast(context, apiErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final t = _ticket;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(t == null ? T.s('Ticket', lang) : '${t['subject']}', overflow: TextOverflow.ellipsis),
        actions: [
          if (t != null && t['canSetStatus'] == true)
            PopupMenuButton<String>(
              tooltip: T.s('Change status', lang),
              icon: const Icon(Icons.flag_outlined),
              onSelected: _setStatus,
              itemBuilder: (_) => [
                for (final s in kTicketStatusLabel.keys)
                  CheckedPopupMenuItem(
                    value: s,
                    checked: t['status'] == s,
                    child: Text(T.s(kTicketStatusLabel[s] ?? s, lang)),
                  ),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: HMC.primary))
          : t == null
              ? ListView(children: [
                  HmMessage(
                    icon: Icons.error_outline,
                    text: _error ?? T.s('Ticket not found.', lang),
                    onRetry: () {
                      setState(() => _loading = true);
                      _load();
                    },
                    retryLabel: T.s('Retry', lang),
                  ),
                ])
              : Column(children: [
                  _header(t, lang),
                  Expanded(
                    child: RefreshIndicator(
                      color: HMC.primary,
                      onRefresh: _load,
                      child: ListView.builder(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        itemCount: _replies.length,
                        itemBuilder: (_, i) => _bubble(_replies[i], t['staffSide'] == true),
                      ),
                    ),
                  ),
                  _composer(t, lang),
                ]),
    );
  }

  Widget _header(Map<String, dynamic> t, String lang) {
    final cat = kTicketCategories['${t['category']}'] ?? ('❔', '${t['category']}');
    final status = '${t['status']}';
    final tone = ticketTone(status);
    final emp = t['employee'] is Map ? Map<String, dynamic>.from(t['employee'] as Map) : const <String, dynamic>{};
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(children: [
        Text(cat.$1, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${T.s(cat.$2, lang)} · ${emp['name'] ?? ''} (${emp['code'] ?? ''})',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
          child: Text(T.s(kTicketStatusLabel[status] ?? status, lang),
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: tone)),
        ),
      ]),
    );
  }

  Widget _bubble(Map<String, dynamic> r, bool staffSide) {
    final fromStaff = r['isStaff'] == true;
    final mine = fromStaff == staffSide;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
          decoration: BoxDecoration(
            color: mine ? HMC.ink : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${fromStaff ? '🛡️ ' : ''}${r['author'] ?? ''}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: mine ? HMC.primary : HMC.emeraldDeep,
              ),
            ),
            const SizedBox(height: 2),
            Text('${r['body'] ?? ''}', style: TextStyle(fontSize: 14.5, color: mine ? Colors.white : HMC.ink, height: 1.35)),
            const SizedBox(height: 3),
            Text(
              shortStamp(r['at']),
              style: TextStyle(fontSize: 10, color: mine ? Colors.white54 : Colors.grey.shade500),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _composer(Map<String, dynamic> t, String lang) {
    if (t['canReply'] != true) {
      return Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          top: false,
          child: Text(
            T.s('This ticket is closed.', lang),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ctl,
              minLines: 1,
              maxLines: 4,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: T.s('Write a reply…', lang),
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: HMC.emeraldDeep, foregroundColor: Colors.white),
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.send_rounded),
          ),
        ]),
      ),
    );
  }
}
