import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

final holidayYearProvider = StateProvider.autoDispose<int>((ref) => DateTime.now().year);

final holidaysProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, year) async {
  final res = await ref.read(apiProvider).get<Map<String, dynamic>>('/api/holidays', queryParameters: {'year': year});
  return res.data ?? const <String, dynamic>{};
});

/// Company holidays (mockup p5-holidays): month groups of date-tile cards,
/// year switcher, amber "Next holiday in N days" pill. HR/admin get an add
/// FAB and long-press delete (same effect as the web calendar).
class HolidaysScreen extends ConsumerWidget {
  const HolidaysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final year = ref.watch(holidayYearProvider);
    final data = ref.watch(holidaysProvider(year));
    final canEdit = data.valueOrNull?['canEdit'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(title: Text(T.s('Holidays', lang))),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              backgroundColor: HMC.primary,
              foregroundColor: HMC.ink,
              onPressed: () async {
                final added = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _AddHolidaySheet(year: year),
                );
                if (added == true) ref.invalidate(holidaysProvider(year));
              },
              icon: const Icon(Icons.add),
              label: Text(T.s('Add holiday', lang), style: const TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: RefreshIndicator(
        color: HMC.primary,
        onRefresh: () async => ref.invalidate(holidaysProvider(year)),
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator(color: HMC.primary)),
          error: (e, _) => ListView(children: [
            HmMessage(
              icon: Icons.wifi_off_rounded,
              text: apiErrorMessage(e),
              onRetry: () => ref.invalidate(holidaysProvider(year)),
              retryLabel: T.s('Retry', lang),
            ),
          ]),
          data: (j) => _body(context, ref, j, year, lang, canEdit),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, Map<String, dynamic> j, int year, String lang, bool canEdit) {
    final rows = asMaps(j['holidays']);
    final today = '${j['today'] ?? ''}';
    final next = j['next'] is Map ? Map<String, dynamic>.from(j['next'] as Map) : null;

    // group by month (API already sorts ascending)
    final byMonth = <int, List<Map<String, dynamic>>>{};
    for (final h in rows) {
      final d = DateTime.tryParse('${h['date']}');
      if (d == null) continue;
      byMonth.putIfAbsent(d.month, () => []).add(h);
    }

    return ListView(padding: const EdgeInsets.fromLTRB(18, 10, 18, 110), children: [
      Row(children: [
        Expanded(
          child: Text(
            '${T.s('Company holidays', lang)} $year',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: HMC.ink),
          ),
        ),
        IconButton(
          tooltip: '${year - 1}',
          onPressed: () => ref.read(holidayYearProvider.notifier).state = year - 1,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: '${year + 1}',
          onPressed: () => ref.read(holidayYearProvider.notifier).state = year + 1,
          icon: const Icon(Icons.chevron_right),
        ),
      ]),
      if (next != null) ...[
        const SizedBox(height: 8),
        _NextPill(next: next, lang: lang),
      ],
      if (rows.isEmpty)
        HmMessage(
          icon: Icons.event_busy_outlined,
          text: T.s('No holidays added for this year', lang),
          hint: canEdit ? T.s('Tap “Add holiday” to build the calendar.', lang) : null,
        ),
      for (final entry in byMonth.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(kMonthsLong[entry.key - 1],
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: HMC.ink)),
        ),
        for (final h in entry.value)
          _HolidayCard(
            h: h,
            isToday: h['date'] == today,
            isNext: next != null && next['id'] == h['id'],
            lang: lang,
            onLongPress: canEdit ? () => _confirmDelete(context, ref, h, year, lang) : null,
          ),
      ],
    ]);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Map<String, dynamic> h, int year, String lang) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${T.s('Delete', lang)} “${h['name']}”?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(T.s('Cancel', lang))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HMC.danger, minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(T.s('Delete', lang)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).delete('/api/holidays', queryParameters: {'id': h['id']});
      ref.invalidate(holidaysProvider(year));
    } catch (e) {
      if (context.mounted) hmToast(context, apiErrorMessage(e));
    }
  }
}

class _NextPill extends StatelessWidget {
  final Map<String, dynamic> next;
  final String lang;
  const _NextPill({required this.next, required this.lang});

  @override
  Widget build(BuildContext context) {
    final days = (next['daysLeft'] as num?)?.toInt() ?? 0;
    final when = days == 0
        ? T.s('today', lang)
        : days == 1
            ? T.s('tomorrow', lang)
            : lang == 'pa'
                ? '$days ਦਿਨਾਂ ਵਿੱਚ'
                : 'in $days days';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Row(children: [
        const Icon(Icons.celebration_outlined, color: Color(0xFF92400E), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '${T.s('Next holiday', lang)}: ', style: const TextStyle(color: Color(0xFF92400E))),
            TextSpan(
              text: '${next['name']} $when',
              style: const TextStyle(color: Color(0xFF78350F), fontWeight: FontWeight.w800),
            ),
          ])),
        ),
      ]),
    );
  }
}

class _HolidayCard extends StatelessWidget {
  final Map<String, dynamic> h;
  final bool isToday;
  final bool isNext;
  final String lang;
  final VoidCallback? onLongPress;
  const _HolidayCard({required this.h, required this.isToday, required this.isNext, required this.lang, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final d = DateTime.tryParse('${h['date']}');
    final past = h['past'] == true && !isToday;
    final dow = d == null ? '' : kDowShort[d.weekday - 1];
    return Opacity(
      opacity: past ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: isToday ? Border.all(color: HMC.primary, width: 2) : null,
          boxShadow: const [BoxShadow(color: Color(0x0F0A1628), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 52,
                height: 56,
                decoration: BoxDecoration(
                  color: isToday ? HMC.primary : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('${d?.day ?? ''}',
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: HMC.ink, height: 1.1)),
                  Text(d == null ? '' : kMonthsShort[d.month - 1].toUpperCase(),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: HMC.ink)),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text('${h['name']}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: HMC.ink),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (isToday || isNext) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(color: HMC.primary, borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          isToday ? T.s('Today', lang) : T.s('Next', lang),
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: HMC.ink),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    past ? '$dow · ${T.s('passed', lang)}' : dow,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _AddHolidaySheet extends ConsumerStatefulWidget {
  final int year;
  const _AddHolidaySheet({required this.year});

  @override
  ConsumerState<_AddHolidaySheet> createState() => _AddHolidaySheetState();
}

class _AddHolidaySheetState extends ConsumerState<_AddHolidaySheet> {
  final _name = TextEditingController();
  late DateTime _date;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = now.year == widget.year ? now : DateTime(widget.year, 1, 1);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _iso =>
      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = T.s('Holiday name is required', ref.read(langProvider)));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).post('/api/holidays', data: {'name': _name.text.trim(), 'date': _iso});
      if (mounted) Navigator.of(context).pop(true);
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
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(T.s('Add holiday', lang), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: HMC.ink)),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: T.s('Holiday name', lang)),
        ),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              firstDate: DateTime(widget.year - 1, 1, 1),
              lastDate: DateTime(widget.year + 1, 12, 31),
              initialDate: _date,
            );
            if (d != null) setState(() => _date = d);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Icon(Icons.calendar_month_outlined, size: 18, color: HMC.ink),
              const SizedBox(width: 10),
              Text(_iso, style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          T.s('Absent-without-punch rows on that day become HOLIDAY automatically.', lang),
          style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: HMC.danger, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 14),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: HMC.emeraldDeep),
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(T.s('Save holiday', lang)),
        ),
      ]),
    );
  }
}
