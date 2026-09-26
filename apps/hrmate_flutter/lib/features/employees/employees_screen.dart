import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Employees directory — staff only (web /employees parity, row 13).
/// Search by name/code/email, ACTIVE/INACTIVE filter, tap → detail.
class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});

  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _status = 'ACTIVE';
  int _count = 0;

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(apiProvider).get<Map<String, dynamic>>(
        '/api/employees',
        queryParameters: {
          'q': _search.text.trim(),
          'status': _status,
          'take': '120',
        },
      );
      if (!mounted) return;
      setState(() {
        _rows = asMaps(res.data?['employees']);
        _count = (res.data?['count'] as num?)?.toInt() ?? _rows.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 380), _fetch);
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);

    return Scaffold(
      backgroundColor: HMC.bg,
      appBar: AppBar(
        title: Text(T.s('Employees', lang)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: HMC.primary,
                  decoration: InputDecoration(
                    hintText: T.s('Search name, code or email…', lang),
                    hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: Colors.white70),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                            onPressed: () {
                              _search.clear();
                              _fetch();
                            },
                          ),
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    _StatusChip(
                      label: T.s('Active', lang),
                      active: _status == 'ACTIVE',
                      onTap: () {
                        if (_status != 'ACTIVE') {
                          setState(() => _status = 'ACTIVE');
                          _fetch();
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    _StatusChip(
                      label: T.s('Inactive', lang),
                      active: _status == 'INACTIVE',
                      onTap: () {
                        if (_status != 'INACTIVE') {
                          setState(() => _status = 'INACTIVE');
                          _fetch();
                        }
                      },
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                      child: Text('$_count ${T.s(_status == 'ACTIVE' ? 'active' : 'inactive', lang)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
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
                ? ListView(children: [HmMessage(icon: Icons.error_outline, text: _error!, onRetry: _fetch, retryLabel: T.s('Retry', lang))])
                : _rows.isEmpty
                    ? ListView(children: [HmMessage(icon: Icons.person_search_outlined, text: T.s('No employees found', lang), hint: T.s('Try a different search or switch to inactive.', lang))])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final e = _rows[i];
                          final name = '${e['name'] ?? ''}';
                          final code = '${e['code'] ?? ''}';
                          final dept = e['dept'] as String?;
                          final desig = e['designation'] as String?;
                          final status = '${e['status'] ?? 'ACTIVE'}';
                          final hasLogin = e['hasLogin'] == true;
                          final loginRole = e['loginRole'] as String?;
                          final email = e['email'] as String?;
                          final photo = e['photo'] as String?;
                          final category = '${e['category'] ?? ''}';

                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            elevation: 0,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => context.push('/employees/${e['id']}'),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    HmAvatar(name: name, photo: photo, radius: 24),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(name,
                                                    style: const TextStyle(fontWeight: FontWeight.w900, color: HMC.ink, fontSize: 14),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: status == 'ACTIVE' ? HMC.primaryFade : Colors.grey.shade200,
                                                  borderRadius: BorderRadius.circular(7),
                                                ),
                                                child: Text(status,
                                                    style: TextStyle(
                                                        fontSize: 9, fontWeight: FontWeight.w900, color: status == 'ACTIVE' ? HMC.primaryDark : Colors.grey.shade600)),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text('$code · ${dept ?? '—'}',
                                              style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5, fontWeight: FontWeight.w600),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                          if (desig != null && desig.isNotEmpty)
                                            Text(desig, style: TextStyle(color: Colors.grey.shade400, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          if (email != null && email.isNotEmpty)
                                            Text(email, style: TextStyle(color: Colors.grey.shade400, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              if (category == 'YELLOW_CARD')
                                                Container(
                                                  margin: const EdgeInsets.only(right: 6),
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                  decoration: BoxDecoration(color: HMC.warnFade, borderRadius: BorderRadius.circular(6)),
                                                  child: const Text('YELLOW', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF92400E))),
                                                ),
                                              if (hasLogin)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                  decoration: BoxDecoration(color: HMC.primaryFade, borderRadius: BorderRadius.circular(6)),
                                                  child: Text('✓ ${loginRole ?? 'Login'}',
                                                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: HMC.primaryDark)),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(Icons.chevron_right, color: Colors.grey.shade300, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _StatusChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? Colors.white : Colors.transparent),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: active ? HMC.ink : Colors.white70)),
      ),
    );
  }
}
