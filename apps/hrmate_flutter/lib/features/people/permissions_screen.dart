import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// The six super-admin feature switches — same keys as the web profile card.
const kPermRows = <(String, IconData, String)>[
  ('canPunch', Icons.schedule, 'Self punch'),
  ('canApplyLeave', Icons.event_available_outlined, 'Apply leave'),
  ('canGatePass', Icons.meeting_room_outlined, 'Gate pass'),
  ('canSwapShift', Icons.swap_horiz, 'Shift swap'),
  ('canSocialPost', Icons.add_photo_alternate_outlined, 'Social post'),
  ('canViewPayslip', Icons.request_quote_outlined, 'View payslip'),
];

/// Super admin: employee picker (search by name / code) → toggles screen.
class PermissionsPickerScreen extends ConsumerStatefulWidget {
  const PermissionsPickerScreen({super.key});

  @override
  ConsumerState<PermissionsPickerScreen> createState() => _PermissionsPickerScreenState();
}

class _PermissionsPickerScreenState extends ConsumerState<PermissionsPickerScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final q = _search.text.trim();
      final res = await ref.read(apiProvider).get<Map<String, dynamic>>(
            '/api/permissions',
            queryParameters: q.isEmpty ? null : {'q': q},
          );
      if (!mounted) return;
      setState(() {
        _rows = asMaps(res.data?['employees']);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _fetch);
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(T.s('Employee permissions', lang)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              style: const TextStyle(color: Colors.white),
              cursorColor: HMC.primary,
              decoration: InputDecoration(
                hintText: T.s('Search name or code', lang),
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: HMC.inkSoft,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: const BorderSide(color: HMC.primary),
                ),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: HMC.primary,
        onRefresh: _fetch,
        child: _loading && _rows.isEmpty
            ? const Center(child: CircularProgressIndicator(color: HMC.primary))
            : _error != null
                ? ListView(children: [
                    HmMessage(icon: Icons.lock_outline, text: _error!, onRetry: _fetch, retryLabel: T.s('Retry', lang)),
                  ])
                : _rows.isEmpty
                    ? ListView(children: [
                        HmMessage(icon: Icons.person_search_outlined, text: T.s('No employees match', lang)),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final e = _rows[i];
                          final off = (e['offCount'] as num?)?.toInt() ?? 0;
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            child: ListTile(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              leading: HmAvatar(name: '${e['name']}', photo: e['photo'] as String?),
                              title: Text('${e['code']} · ${e['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                              subtitle: Text('${e['dept'] ?? '—'}'),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                if (off > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: HMC.warnFade,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text('$off ${T.s('off', lang)}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF92400E))),
                                  ),
                                const Icon(Icons.chevron_right),
                              ]),
                              onTap: () async {
                                await context.push('/permissions/${e['id']}');
                                if (mounted) _fetch();
                              },
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

/// Toggle card for one employee (mockup p5-toggles). Each flip is saved
/// instantly (optimistic, rolls back on failure).
class PermissionsScreen extends ConsumerStatefulWidget {
  final String employeeId;
  const PermissionsScreen({super.key, required this.employeeId});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  Map<String, dynamic>? _emp;
  Map<String, bool> _perms = {};
  final Set<String> _saving = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _apply(Map<String, dynamic>? d) {
    if (d == null) return;
    final emp = d['employee'];
    final perms = d['perms'];
    _emp = emp is Map ? Map<String, dynamic>.from(emp) : _emp;
    if (perms is Map) _perms = perms.map((k, v) => MapEntry('$k', v == true));
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(apiProvider).get<Map<String, dynamic>>('/api/permissions/${widget.employeeId}');
      if (!mounted) return;
      setState(() {
        _apply(res.data);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _flip(String key, bool allowed) async {
    final before = _perms[key] ?? true;
    setState(() {
      _perms[key] = allowed;
      _saving.add(key);
    });
    try {
      final res = await ref.read(apiProvider).put<Map<String, dynamic>>(
            '/api/permissions/${widget.employeeId}',
            data: {'key': key, 'allowed': allowed},
          );
      if (!mounted) return;
      setState(() => _apply(res.data));
    } catch (e) {
      if (!mounted) return;
      setState(() => _perms[key] = before);
      hmToast(context, apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final emp = _emp;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(T.s('Employee permissions', lang)),
        bottom: emp == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(62),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                  decoration: BoxDecoration(color: HMC.inkSoft, borderRadius: BorderRadius.circular(28)),
                  child: Row(children: [
                    const Icon(Icons.person_outline, color: Colors.white70, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${emp['code']} · ${emp['name']}',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    HmAvatar(name: '${emp['name']}', photo: emp['photo'] as String?, radius: 18),
                  ]),
                ),
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: HMC.primary))
          : _error != null && emp == null
              ? ListView(children: [
                  HmMessage(
                    icon: Icons.lock_outline,
                    text: _error!,
                    onRetry: () {
                      setState(() => _loading = true);
                      _load();
                    },
                    retryLabel: T.s('Retry', lang),
                  ),
                ])
              : ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 24), children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Color(0x140A1628), blurRadius: 16, offset: Offset(0, 6))],
                    ),
                    child: Column(children: [
                      for (var i = 0; i < kPermRows.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                        _toggleRow(kPermRows[i], lang),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFCD34D)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline, color: HMC.amber, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          T.s('Changes apply immediately on their phone.', lang),
                          style: const TextStyle(color: Color(0xFF78350F), fontSize: 13),
                        ),
                      ),
                    ]),
                  ),
                ]),
    );
  }

  Widget _toggleRow((String, IconData, String) row, String lang) {
    final (key, icon, label) = row;
    final on = _perms[key] ?? true;
    final saving = _saving.contains(key);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Icon(icon, color: HMC.primary, size: 26),
        const SizedBox(width: 16),
        Expanded(child: Text(T.s(label, lang), style: const TextStyle(fontSize: 16.5, color: HMC.ink))),
        if (saving)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: HMC.primary)),
          ),
        Switch(
          value: on,
          activeTrackColor: HMC.primary,
          thumbColor: const WidgetStatePropertyAll(Colors.white),
          onChanged: saving ? null : (v) => _flip(key, v),
        ),
      ]),
    );
  }
}
