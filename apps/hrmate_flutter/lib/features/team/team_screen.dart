import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'team_models.dart';

/// P2 slice 2 — approved mockup: mockups/p2-s2-live-team.png.
/// Read-only presence/leave board; weekly off is the only mutation here.
class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> with WidgetsBindingObserver {
  TeamSnapshot? _data;
  List<TeamDepartment> _departments = [];
  String _department = '';
  bool _leavesTab = false;
  bool _loading = false;
  String? _error;
  int _request = 0;
  CancelToken? _cancel;
  final _saving = <String>{};

  bool get _staff => ref.read(sessionStoreProvider).user?.isStaff ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_staff) _fetch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancel?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted &&
        ModalRoute.of(context)?.isCurrent == true && !_loading) {
      _fetch();
    }
  }

  Future<void> _fetch({String? department}) async {
    // Don't let a read started before a weekly-off save overwrite its result.
    if (!_staff || _saving.isNotEmpty) return;
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    final request = ++_request;
    setState(() {
      _department = department ?? _department;
      _loading = true;
      _error = null;
    });
    try {
      final response = await ref.read(apiProvider).get<Map<String, dynamic>>(
        '/api/team', queryParameters: {'dept': _department}, cancelToken: cancel,
      );
      if (!mounted || request != _request) return;
      final data = TeamSnapshot.fromJson(response.data!);
      setState(() {
        _data = data;
        _departments = data.departments;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request || (error is DioException && CancelToken.isCancel(error))) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(error, fallback: 'Could not load Live Team. Try again.');
        // Hide old data on failure, rather than presenting it as a fresh board.
        _data = null;
        if (error is DioException && [401, 403].contains(error.response?.statusCode)) {
          _departments = [];
        }
      });
    }
  }

  Future<void> _saveOff(TeamMember member, int day) async {
    if (!_staff || _loading || _saving.contains(member.id) || member.weeklyOff == day) return;
    setState(() => _saving.add(member.id));
    final lang = ref.read(langProvider);
    try {
      final response = await ref.read(apiProvider).patch<Map<String, dynamic>>(
        '/api/team/weekly-off', data: {'employeeId': member.id, 'weeklyOff': day},
      );
      final saved = response.data?['weeklyOff'];
      if (saved is! int || saved < 0 || saved > 6) throw const FormatException('Invalid weekly off');
      if (!mounted) return;
      setState(() {
        if (_data != null) _data = TeamSnapshot.withWeeklyOff(_data!, member.id, saved);
      });
      hmToast(context, T.s('Weekly off updated ✔', lang), ok: true);
    } catch (error) {
      if (!mounted) return;
      // Pessimistic save: the old value stays selected until the API succeeds.
      hmToast(context, T.s(apiErrorMessage(error, fallback: 'Could not save weekly off. Try again.'), lang));
    } finally {
      if (mounted) setState(() => _saving.remove(member.id));
    }
  }

  Future<void> _profile(TeamMember member) async {
    await context.push('/employees/${Uri.encodeComponent(member.id)}');
    if (mounted) await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final user = ref.watch(sessionStoreProvider);
    final allowed = user.user?.isStaff ?? false;
    final data = _data;
    final board = data?.activeDept == _department ? data : null;
    final token = user.cachedToken;
    final headers = token == null ? null : {'Authorization': 'Bearer $token'};

    Widget message() {
      if (_error != null) {
        return HmMessage(
          icon: Icons.cloud_off_outlined, text: T.s(_error!, lang),
          onRetry: _fetch, retryLabel: T.s('Retry', lang),
        );
      }
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: HMC.bg,
      appBar: AppBar(
        title: Text(T.s('Live Team', lang), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            key: const ValueKey('team-refresh'),
            tooltip: T.s('Refresh', lang),
            onPressed: allowed && !_loading && _saving.isEmpty ? _fetch : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !allowed
          ? HmMessage(icon: Icons.lock_outline, text: T.s('Only HR / admin can view Live Team.', lang))
          : RefreshIndicator(
              onRefresh: _fetch,
              child: ListView(
                key: const PageStorageKey('live-team'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16, 16, 16, 28 + MediaQuery.paddingOf(context).bottom),
                children: [
                  Text(T.s("Who's on the floor right now", lang), style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: const Color(0xFFE9EDF2), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Expanded(flex: 2, child: _TabButton(
                        label: T.s('Board', lang), selected: !_leavesTab,
                        onTap: () => setState(() => _leavesTab = false),
                      )),
                      Expanded(flex: 3, child: _TabButton(
                        label: T.s('Upcoming Leaves', lang), selected: _leavesTab,
                        count: data?.leaves.length,
                        onTap: () => setState(() => _leavesTab = true),
                      )),
                    ]),
                  ),
                  if (_loading && data != null) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                  const SizedBox(height: 18),
                  if (!_leavesTab) ...[
                    if (board != null) ...[
                      _Counters(counts: board.counts, lang: lang),
                      const SizedBox(height: 12),
                    ],
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final dept in [TeamDepartment('', T.s('All Departments', lang)), ..._departments])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              key: ValueKey('team-dept-${dept.id}'),
                              label: Text(dept.name, style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700,
                                color: _department == dept.id ? const Color(0xFF6EE7B7) : const Color(0xFF475569),
                              )),
                              showCheckmark: false,
                              selected: _department == dept.id,
                              selectedColor: HMC.ink,
                              backgroundColor: const Color(0xFFE9EEF4),
                              side: BorderSide.none,
                              shape: const StadiumBorder(),
                              onSelected: _saving.isNotEmpty ? null : (_) => _fetch(department: dept.id),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    if (board == null) message()
                    else if (board.rows.isEmpty)
                      HmMessage(icon: Icons.people_outline, text: T.s('No employees in this filter.', lang))
                    else
                      _RowCard(children: [
                        for (final member in board.rows)
                          _MemberRow(
                            key: ValueKey('team-member-${member.id}'),
                            member: member, lang: lang, headers: headers,
                            saving: _saving.contains(member.id), disabled: _loading,
                            onProfile: () => _profile(member), onOff: (day) => _saveOff(member, day),
                          ),
                      ]),
                    if (board != null) ...[
                      const SizedBox(height: 20),
                      Text(T.s('Pull down to refresh', lang), textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                    ],
                  ] else ...[
                    Text(T.s('Approved · Next 14 days', lang), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF475569))),
                    const SizedBox(height: 16),
                    if (data == null) message()
                    else if (data.leaves.isEmpty)
                      HmMessage(icon: Icons.event_available, text: T.s('No approved leaves in the next 14 days', lang))
                    else ...[
                      _RowCard(children: [for (final leave in data.leaves) _LeaveRow(leave: leave, lang: lang)]),
                      const SizedBox(height: 24),
                      Text(T.s('Only approved leave is shown', lang), textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final int? count;
  final VoidCallback onTap;
  const _TabButton({required this.label, required this.selected, this.count, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(child: Text(label, textAlign: TextAlign.center, style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, color: selected ? HMC.ink : const Color(0xFF64748B),
            ))),
            if ((count ?? 0) > 0) ...[
              const SizedBox(width: 6),
              _Badge(label: '$count', ink: const Color(0xFFB45309), fill: const Color(0xFFFEF3C7)),
            ],
          ]),
        ),
      ),
    ),
  );
}

class _Counters extends StatelessWidget {
  final Map<String, int> counts;
  final String lang;
  const _Counters({required this.counts, required this.lang});

  @override
  Widget build(BuildContext context) {
    const tiles = [
      ('in', 'Punched In', Color(0xFF059669), Color(0xFFECFDF5)),
      ('out', 'Punched Out', Color(0xFF0284C7), Color(0xFFF0F9FF)),
      ('absent', 'Not in yet', Color(0xFF64748B), Color(0xFFF1F5F9)),
      ('done', 'Shift done', Color(0xFF9333EA), Color(0xFFFAF5FF)),
    ];
    return LayoutBuilder(builder: (context, box) {
      final columns = box.maxWidth < 320 || MediaQuery.textScalerOf(context).scale(1) > 1.4 ? 2 : 4;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final tile in tiles)
          SizedBox(
            width: (box.maxWidth - (columns - 1) * 8) / columns,
            child: Container(
              key: ValueKey('team-count-${tile.$1}'),
              constraints: const BoxConstraints(minHeight: 72),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(color: tile.$4, borderRadius: BorderRadius.circular(13), border: Border.all(color: tile.$3.withValues(alpha: 0.1))),
              child: Column(children: [
                Text('${counts[tile.$1] ?? 0}', style: TextStyle(fontSize: 24, color: tile.$3, fontWeight: FontWeight.w900)),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: lang == 'en' ? 40 * MediaQuery.textScalerOf(context).scale(1) : double.infinity),
                  child: Text(T.s(tile.$2, lang), textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
      ]);
    });
  }
}

class _RowCard extends StatelessWidget {
  final List<Widget> children;
  const _RowCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
    child: Column(children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFEEF2F6)),
        children[i],
      ],
    ]),
  );
}

class _MemberRow extends StatelessWidget {
  final TeamMember member;
  final String lang;
  final Map<String, String>? headers;
  final bool saving, disabled;
  final VoidCallback onProfile;
  final ValueChanged<int> onOff;
  const _MemberRow({super.key, required this.member, required this.lang, this.headers, required this.saving, required this.disabled, required this.onProfile, required this.onOff});

  @override
  Widget build(BuildContext context) {
    final r = member;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final ink = r.status == 'IN' ? const Color(0xFF047857) : r.status == 'OUT' ? const Color(0xFF0369A1) : const Color(0xFF64748B);
    final fill = r.status == 'IN' ? const Color(0xFFD1FAE5) : r.status == 'OUT' ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9);
    final status = Wrap(spacing: 4, runSpacing: 4, children: [
      _Badge(label: T.s(r.status == 'IN' ? 'In' : r.status == 'OUT' ? 'Out' : 'Not in yet', lang), ink: ink, fill: fill),
      if (r.completed) _Badge(label: '✓ ${T.s('Done', lang)}', ink: const Color(0xFF7E22CE), fill: const Color(0xFFF3E8FF)),
    ]);
    final times = [
      if (r.inAt != null) '${T.s('IN', lang)} ${r.inAt}',
      if (r.outAt != null) '${T.s('OUT', lang)} ${r.outAt}',
    ];
    final off = PopupMenuButton<int>(
      key: ValueKey('weekly-off-${r.id}'),
      enabled: !saving && !disabled,
      tooltip: '${T.s('Weekly Off', lang)} · ${r.name}',
      initialValue: r.weeklyOff,
      onSelected: onOff,
      itemBuilder: (_) => [for (var i = 0; i < 7; i++) PopupMenuItem(value: i, child: Text(T.s(teamDayNames[i], lang)))],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Center(widthFactor: 1, heightFactor: 1, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFDE68A))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (saving) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            else Flexible(child: Text(T.s(teamDayLabels[r.weeklyOff.clamp(0, 6).toInt()], lang), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFB45309)))),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFFB45309)),
          ]),
        )),
      ),
    );
    final timeText = Text(times.isEmpty ? T.s('No punch yet', lang) : times.join(' · '),
        style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)));

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: onProfile, borderRadius: BorderRadius.circular(8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(clipBehavior: Clip.none, children: [
              HmAvatar(name: r.name, photo: r.photo, radius: 19, headers: headers),
              Positioned(right: 0, bottom: 0, child: Container(width: 10, height: 10,
                  decoration: BoxDecoration(color: ink, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
            ]),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name, style: const TextStyle(fontWeight: FontWeight.w900, color: HMC.ink, fontSize: 14)),
              const SizedBox(height: 3),
              Text('${r.dept} · ${r.shift}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
              if (largeText) ...[const SizedBox(height: 6), status],
            ])),
            if (!largeText) ...[const SizedBox(width: 8), status],
          ]),
        ),
        if (largeText)
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [timeText, Align(alignment: Alignment.centerRight, child: off)])
        else
          Row(children: [Expanded(child: timeText), const SizedBox(width: 8), off]),
      ]),
    );
  }
}

class _LeaveRow extends StatelessWidget {
  final TeamLeave leave;
  final String lang;
  const _LeaveRow({required this.leave, required this.lang});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(leave.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: HMC.ink)),
          const SizedBox(height: 4),
          Text(leave.dept, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        ])),
        const SizedBox(width: 8),
        _Badge(label: '${leave.days % 1 == 0 ? leave.days.toInt() : leave.days}${T.s('d', lang)}', ink: const Color(0xFFB45309), fill: const Color(0xFFFEF3C7)),
      ]),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: Wrap(
        alignment: WrapAlignment.spaceBetween, spacing: 16, runSpacing: 8, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.calendar_today_outlined, size: 14, color: Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            Flexible(child: Text('${teamShortDate(leave.fromDate, lang)} → ${teamShortDate(leave.toDate, lang)}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF475569)))),
          ]),
          Text(T.s(leave.type, lang), style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        ],
      )),
    ]),
  );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color ink, fill;
  const _Badge({required this.label, required this.ink, required this.fill});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(color: ink, fontSize: 10, fontWeight: FontWeight.w800)),
  );
}
