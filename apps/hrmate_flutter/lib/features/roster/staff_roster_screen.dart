import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'staff_roster_models.dart';

/// P2 slice 3 — approved mockup: mockups/p2-s3-staff-roster.png.
class StaffRosterScreen extends ConsumerStatefulWidget {
  const StaffRosterScreen({super.key});

  @override
  ConsumerState<StaffRosterScreen> createState() => _StaffRosterScreenState();
}

class _StaffRosterScreenState extends ConsumerState<StaffRosterScreen> {
  RosterSnapshot? _data;
  String _week = '';
  String _department = '';
  bool _swapsTab = false;
  bool _loading = false;
  bool _saving = false;
  final _deciding = <String>{};
  String? _error;
  int _request = 0;
  CancelToken? _cancel;
  final _edits = <String, RosterCell>{};

  bool get _staff => ref.read(sessionStoreProvider).user?.isStaff ?? false;
  int get _dirtyCount => _edits.length;

  String _key(String employeeId, String date) => '$employeeId|$date';

  RosterCell _cell(RosterEmployee employee, String date) =>
      _edits[_key(employee.id, date)] ?? employee.cells[date] ?? const RosterCell();

  @override
  void initState() {
    super.initState();
    if (_staff) _fetch();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  String _weekTitle(List<String> days, String lang) {
    if (days.length < 7) return days.join('–');
    final last = DateTime.tryParse(days[6]);
    final month = last == null ? '' : ' ${T.s(rosterMonths[last.month - 1], lang)}';
    return '${days[0].substring(8)}–${days[6].substring(8)}$month';
  }

  Future<void> _fetch({String? week}) async {
    if (!_staff || _saving) return;
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    final request = ++_request;
    setState(() {
      _week = week ?? _week;
      _loading = true;
      _error = null;
    });
    try {
      final response = await ref.read(apiProvider).get<Map<String, dynamic>>(
        '/api/roster/staff',
        queryParameters: { if (_week.isNotEmpty) 'w': _week },
        cancelToken: cancel,
      );
      if (!mounted || request != _request) return;
      final data = RosterSnapshot.fromJson(response.data!);
      setState(() {
        _data = data;
        _week = data.weekStart;
        _loading = false;
        _edits.removeWhere((key, value) {
          final parts = key.split('|');
          if (parts.length != 2) return true;
          RosterEmployee? employee;
          for (final e in data.employees) {
            if (e.id == parts[0]) { employee = e; break; }
          }
          final base = employee?.cells[parts[1]] ?? const RosterCell();
          return value.same(base);
        });
      });
    } catch (error) {
      if (!mounted || request != _request || (error is DioException && CancelToken.isCancel(error))) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(error, fallback: 'Could not load the duty roster. Try again.');
        _data = null;
      });
    }
  }

  Future<void> _save() async {
    if (!_staff || _saving || _edits.isEmpty || _data == null) return;
    setState(() => _saving = true);
    final lang = ref.read(langProvider);
    final entries = _edits.entries.map((e) {
      final parts = e.key.split('|');
      return e.value.toJson(parts[0], parts[1]);
    }).toList();
    try {
      final response = await ref.read(apiProvider).patch<Map<String, dynamic>>(
        '/api/roster/staff', data: { 'entries': entries },
      );
      final saved = (response.data?['saved'] as num?)?.toInt();
      if (saved == null) throw const FormatException('Invalid save');
      if (!mounted) return;
      setState(() {
        _edits.clear();
        _saving = false;
      });
      hmToast(context, T.s('Roster saved for {n} cells ✔', lang).replaceAll('{n}', '$saved'), ok: true);
      await _fetch();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      hmToast(context, T.s(apiErrorMessage(error, fallback: 'Could not save the roster. Try again.'), lang));
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  Future<void> _pick(RosterEmployee employee, String date) async {
    if (_saving) return;
    final lang = ref.read(langProvider);
    final data = _data;
    if (data == null) return;
    final current = _cell(employee, date);
    final selected = await showModalBottomSheet<RosterCell>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        Widget option({required RosterCell value, required String title, String? subtitle}) {
          final on = value.same(current);
          return ListTile(
            key: ValueKey('roster-option-${value.isOff ? 'off' : value.shiftId}'),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: subtitle == null ? null : Text(subtitle),
            trailing: on ? const Icon(Icons.check, color: HMC.emeraldDeep) : null,
            onTap: () => Navigator.pop(ctx, value),
          );
        }
        return SafeArea(child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('${employee.name} · $date', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: HMC.ink)),
          ),
          option(value: const RosterCell(), title: T.s('Default', lang), subtitle: [employee.defShift, employee.defStart].whereType<String>().join(' ')),
          for (final shift in data.shifts)
            option(value: RosterCell(shiftId: shift.id), title: shift.name, subtitle: shift.startTime),
          option(value: const RosterCell(isOff: true), title: T.s('OFF', lang)),
        ]));
      },
    );
    if (selected == null || !mounted) return;
    final base = employee.cells[date] ?? const RosterCell();
    setState(() {
      final key = _key(employee.id, date);
      if (selected.same(base)) {
        _edits.remove(key);
      } else {
        _edits[key] = selected;
      }
    });
  }

  Future<void> _decide(RosterSwap swap, bool approve) async {
    if (_saving || _deciding.contains(swap.id)) return;
    setState(() => _deciding.add(swap.id));
    final lang = ref.read(langProvider);
    try {
      await ref.read(apiProvider).post('/api/approvals/decide', data: {
        'kind': 'swap', 'id': swap.id, 'action': approve ? 'approve' : 'reject',
      });
      if (!mounted || _data == null) return;
      setState(() {
        _data = _data!.withSwaps(_data!.swaps.map((s) => s.id == swap.id
          ? RosterSwap(id: s.id, requester: s.requester, peer: s.peer, date: s.date, note: s.note, mine: s.mine, status: approve ? 'APPROVED' : 'REJECTED')
          : s).toList());
      });
    } catch (error) {
      if (!mounted) return;
      hmToast(context, T.s(apiErrorMessage(error, fallback: 'Something went wrong. Try again.'), lang));
    } finally {
      if (mounted) setState(() => _deciding.remove(swap.id));
    }
  }

  Future<void> _requestSwap({required String peerId, required String date, String? note}) async {
    final lang = ref.read(langProvider);
    try {
      await ref.read(apiProvider).post('/api/roster', data: {
        'peerId': peerId, 'date': date, if (note != null && note.isNotEmpty) 'note': note,
      });
      if (!mounted) return;
      hmToast(context, T.s('Swap request sent ✔', lang), ok: true);
      await _fetch();
    } catch (error) {
      if (!mounted) return;
      hmToast(context, T.s(apiErrorMessage(error, fallback: 'Something went wrong. Try again.'), lang));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final allowed = ref.watch(sessionStoreProvider).user?.isStaff ?? false;
    final data = _data;
    final employees = (data?.employees ?? const <RosterEmployee>[]).where((e) => _department.isEmpty || e.deptId == _department).toList();

    Widget message() {
      if (_error != null) {
        return HmMessage(
          icon: Icons.cloud_off_outlined, text: T.s(_error!, lang),
          onRetry: _fetch, retryLabel: T.s('Retry', lang),
        );
      }
      return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: HMC.bg,
      appBar: AppBar(
        title: Text(T.s('Duty Roster', lang), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            key: const ValueKey('roster-refresh'),
            tooltip: T.s('Refresh', lang),
            onPressed: allowed && !_loading && !_saving ? _fetch : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: !allowed || _dirtyCount == 0 ? null : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            key: const ValueKey('roster-save'),
            style: FilledButton.styleFrom(backgroundColor: HMC.ink, foregroundColor: const Color(0xFF6EE7B7), minimumSize: const Size.fromHeight(52)),
            onPressed: _saving ? null : _save,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(T.s('Save roster · {n} cells', lang).replaceAll('{n}', '$_dirtyCount'), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(T.s('Unsaved edits stay on this week', lang), style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      ),
      body: !allowed
        ? HmMessage(icon: Icons.lock_outline, text: T.s('Only HR / admin can edit the duty roster.', lang))
        : RefreshIndicator(
            onRefresh: () => _fetch(),
            child: ListView(
              key: const PageStorageKey('duty-roster'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 16, 16, 28 + MediaQuery.paddingOf(context).bottom),
              children: [
                Text(
                  _swapsTab ? T.s('HR must approve every swap', lang) : T.s('Assign weekly shifts & offs', lang),
                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: const Color(0xFFE9EDF2), borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    Expanded(child: _TabButton(
                      key: const ValueKey('roster-tab-grid'),
                      label: T.s('Roster Grid', lang), selected: !_swapsTab,
                      onTap: () => setState(() => _swapsTab = false),
                    )),
                    Expanded(child: _TabButton(
                      key: const ValueKey('roster-tab-swaps'),
                      label: T.s('Shift Swaps', lang), selected: _swapsTab,
                      count: data?.pendingSwapCount,
                      onTap: () => setState(() => _swapsTab = true),
                    )),
                  ]),
                ),
                if (_loading && data != null) ...[const SizedBox(height: 10), const LinearProgressIndicator(minHeight: 2)],
                const SizedBox(height: 16),
                if (data == null) message()
                else if (_swapsTab) _SwapsTab(
                  data: data, lang: lang, deciding: _deciding,
                  onDecide: _decide, onRequest: _requestSwap,
                )
                else ...[
                  _WeekNav(
                    title: _weekTitle(data.days, lang),
                    onPrev: _saving || data.prevW.isEmpty ? null : () => _fetch(week: data.prevW),
                    onNext: _saving || data.nextW.isEmpty ? null : () => _fetch(week: data.nextW),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    key: const PageStorageKey('roster-depts'),
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final dept in [RosterDepartment('', T.s('All Departments', lang)), ...data.departments])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            key: ValueKey('roster-dept-${dept.id}'),
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
                            onSelected: _saving ? null : (_) => setState(() => _department = dept.id),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  if (data.days.length == 7)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(children: [
                        for (final day in data.days)
                          Expanded(child: _DayHead(date: day, today: data.today == day, lang: lang)),
                      ]),
                    ),
                  const SizedBox(height: 8),
                  if (employees.isEmpty)
                    HmMessage(icon: Icons.groups_outlined, text: T.s('No employees in this filter.', lang))
                  else
                    for (final employee in employees) ...[
                      _EmployeeCard(
                        employee: employee, days: data.days, today: data.today,
                        shifts: data.shifts, lang: lang,
                        cellFor: (date) => _cell(employee, date),
                        onPick: (date) => _pick(employee, date),
                      ),
                      const SizedBox(height: 10),
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
  const _TabButton({super.key, required this.label, required this.selected, required this.onTap, this.count});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: selected ? HMC.ink : const Color(0xFF64748B)))),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
                child: Text('$count', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFB45309))),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _WeekNav extends StatelessWidget {
  final String title;
  final VoidCallback? onPrev, onNext;
  const _WeekNav({required this.title, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(children: [
        IconButton(key: const ValueKey('roster-week-prev'), onPressed: onPrev, icon: const Icon(Icons.chevron_left, color: HMC.ink)),
        Expanded(child: Text(title, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: HMC.ink))),
        IconButton(key: const ValueKey('roster-week-next'), onPressed: onNext, icon: const Icon(Icons.chevron_right, color: HMC.ink)),
      ]),
    );
  }
}

class _DayHead extends StatelessWidget {
  final String date, lang;
  final bool today;
  const _DayHead({required this.date, required this.today, required this.lang});

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(date);
    final dow = parsed == null ? '' : T.s(rosterDow[parsed.weekday - 1], lang);
    final day = date.length >= 10 ? date.substring(8) : date;
    final color = today ? HMC.emeraldDeep : const Color(0xFF475569);
    return Column(children: [
      Text(dow, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: today ? HMC.emeraldDeep : const Color(0xFF94A3B8))),
      Text(day, style: TextStyle(fontSize: 11, fontWeight: today ? FontWeight.w900 : FontWeight.w700, color: color)),
    ]);
  }
}

class _EmployeeCard extends StatelessWidget {
  final RosterEmployee employee;
  final List<String> days;
  final String today, lang;
  final List<RosterShift> shifts;
  final RosterCell Function(String date) cellFor;
  final void Function(String date) onPick;
  const _EmployeeCard({
    required this.employee, required this.days, required this.today, required this.lang,
    required this.shifts, required this.cellFor, required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final defLabel = [employee.defShift, employee.defStart].whereType<String>().join(' ');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(employee.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF1E293B))),
        Text(
          '${employee.code} · ${employee.dept} · ${T.s('default', lang)} ${defLabel.isEmpty ? '—' : defLabel}',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          for (final date in days)
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _CellChip(
                key: ValueKey('roster-cell-${employee.id}-$date'),
                cell: cellFor(date),
                date: date,
                today: date == today,
                defStart: employee.defStart,
                shifts: shifts,
                lang: lang,
                onTap: () => onPick(date),
              ),
            )),
        ]),
      ]),
    );
  }
}

class _CellChip extends StatelessWidget {
  final RosterCell cell;
  final String date, lang;
  final bool today;
  final String? defStart;
  final List<RosterShift> shifts;
  final VoidCallback onTap;
  const _CellChip({
    super.key, required this.cell, required this.date, required this.today,
    required this.defStart, required this.shifts, required this.lang, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    RosterShift? shift;
    for (final s in shifts) {
      if (s.id == cell.shiftId) { shift = s; break; }
    }
    final off = cell.isOff;
    final override = !off && cell.shiftId.isNotEmpty;
    final parsed = DateTime.tryParse(date);
    final label = off ? T.s('OFF', lang) : override ? (shift?.short ?? '—') : T.s('Def', lang);
    final sub = off
      ? (parsed?.weekday == DateTime.sunday ? T.s('Sun', lang) : '—')
      : override ? (shift?.startTime ?? '') : (defStart ?? '—');
    final bg = off ? const Color(0xFFFFF1F2) : override ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC);
    final border = off ? const Color(0xFFFECDD3) : override ? const Color(0xFF6EE7B7) : today ? HMC.emeraldDeep : const Color(0xFFE2E8F0);
    final fg = off ? const Color(0xFFE11D48) : override ? const Color(0xFF047857) : const Color(0xFF94A3B8);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          height: 50,
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg)),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 8, color: fg.withValues(alpha: 0.85))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwapsTab extends StatefulWidget {
  final RosterSnapshot data;
  final String lang;
  final Set<String> deciding;
  final Future<void> Function(RosterSwap, bool) onDecide;
  final Future<void> Function({required String peerId, required String date, String? note}) onRequest;
  const _SwapsTab({required this.data, required this.lang, required this.deciding, required this.onDecide, required this.onRequest});

  @override
  State<_SwapsTab> createState() => _SwapsTabState();
}

class _SwapsTabState extends State<_SwapsTab> {
  String? _peerId;
  late DateTime _date;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now().add(const Duration(days: 1));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final pending = widget.data.swaps.where((s) => s.status == 'PENDING').toList();
    final history = widget.data.swaps.where((s) => s.status != 'PENDING').toList();
    final showForm = widget.data.myEmployeeId != null;

    return Column(children: [
      if (showForm) Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(T.s('Request a shift swap', lang), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF1E293B))),
          const SizedBox(height: 2),
          Text(T.s('Swap your duty with a teammate for one day', lang), style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: InkWell(
              key: const ValueKey('roster-swap-date'),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context, firstDate: DateTime.now().add(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 60)), initialDate: _date,
                );
                if (picked != null) setState(() => _date = picked);
              },
              child: _Field(text: rosterShortDate(_iso(_date))),
            )),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: DropdownButtonFormField<String>(
              key: const ValueKey('roster-swap-peer'),
              value: _peerId,
              isExpanded: true,
              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              hint: Text(T.s('Coworker', lang), overflow: TextOverflow.ellipsis),
              items: [
                for (final p in widget.data.peers)
                  DropdownMenuItem(value: p.id, child: Text('${p.name} · ${p.department ?? '—'}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _peerId = v),
            )),
          ]),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('roster-swap-send'),
            style: FilledButton.styleFrom(backgroundColor: HMC.ink, foregroundColor: const Color(0xFF6EE7B7), minimumSize: const Size.fromHeight(40)),
            onPressed: _busy ? null : () async {
              if (_peerId == null) {
                hmToast(context, T.s('Pick a coworker first.', lang));
                return;
              }
              setState(() => _busy = true);
              await widget.onRequest(peerId: _peerId!, date: _iso(_date), note: _note.text.trim());
              if (mounted) setState(() => _busy = false);
            },
            child: FittedBox(child: Text(T.s('Send request', lang), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
          ),
        ]),
      ),
      if (showForm) const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(T.s('Pending swaps', lang), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
            if (pending.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(11)),
                child: Text('${pending.length}', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFB45309), fontSize: 11)),
              ),
          ]),
          const SizedBox(height: 8),
          if (pending.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text(T.s('No pending swap requests', lang), style: const TextStyle(color: Color(0xFF94A3B8)))),
            )
          else
            for (final swap in pending) ...[
              Text('${swap.requester}  ↔  ${swap.peer}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF1E293B))),
              Text(
                '${rosterShortDate(swap.date)}${swap.note == null || swap.note!.isEmpty ? '' : ' · ${swap.note}'}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: FilledButton(
                  key: ValueKey('roster-approve-${swap.id}'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981), minimumSize: const Size.fromHeight(36)),
                  onPressed: widget.deciding.contains(swap.id) ? null : () => widget.onDecide(swap, true),
                  child: FittedBox(child: Text(T.s('Approve', lang), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                )),
                const SizedBox(width: 8),
                Expanded(child: FilledButton(
                  key: ValueKey('roster-reject-${swap.id}'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFE4E6), foregroundColor: const Color(0xFFE11D48), minimumSize: const Size.fromHeight(36)),
                  onPressed: widget.deciding.contains(swap.id) ? null : () => widget.onDecide(swap, false),
                  child: FittedBox(child: Text(T.s('Reject', lang), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                )),
              ]),
              const SizedBox(height: 14),
            ],
        ]),
      ),
      if (history.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(T.s('History', lang), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 8),
            for (final swap in history)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${swap.requester}  ↔  ${swap.peer}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF334155))),
                    Text(rosterShortDate(swap.date), style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: swap.status == 'APPROVED' ? const Color(0xFFD1FAE5) : const Color(0xFFFFE4E6),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(swap.status, style: TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w800,
                      color: swap.status == 'APPROVED' ? const Color(0xFF047857) : const Color(0xFFE11D48),
                    )),
                  ),
                ]),
              ),
          ]),
        ),
      ],
    ]);
  }
}

class _Field extends StatelessWidget {
  final String text;
  const _Field({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Text(text, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Color(0xFF475569))),
    );
  }
}
