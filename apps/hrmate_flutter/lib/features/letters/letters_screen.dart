import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// My Letters (web /letters parity): employees see their own letters, staff
/// see every letter of the company with the employee's name. Tap → letter
/// sheet view (same letterhead the web prints).
class LettersScreen extends ConsumerStatefulWidget {
  const LettersScreen({super.key});

  @override
  ConsumerState<LettersScreen> createState() => _LettersScreenState();
}

class _LettersScreenState extends ConsumerState<LettersScreen> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  bool _linked = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _lang => ref.read(langProvider);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(apiProvider).get<Map<String, dynamic>>(
            '/api/letters',
            queryParameters: {'lang': _lang},
          );
      if (!mounted) return;
      setState(() {
        _list = asMaps(res.data?['letters']);
        _linked = res.data?['linked'] != false;
        _loading = false;
      });
    } on DioException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _date(Object? v) {
    final dt = DateTime.tryParse('${v ?? ''}');
    return dt == null ? '' : DateFormat('d MMM yyyy').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final staff = ref.watch(sessionStoreProvider).user?.role != 'EMPLOYEE';

    return Scaffold(
      backgroundColor: HMC.bg,
      appBar: AppBar(title: Text(T.s(staff ? 'Letters' : 'My Letters', lang)), centerTitle: false),
      body: RefreshIndicator(
        color: HMC.primaryDark,
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Icon(Icons.description_outlined, color: HMC.primaryDark, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(T.s('Experience · Joining · KYC · Duty pass', lang),
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
              Text('${_list.length} ${T.s('letters issued', lang)}',
                  style: const TextStyle(color: HMC.emeraldDeep, fontSize: 11, fontWeight: FontWeight.w900)),
            ]),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator(color: HMC.primary)))
          else if (_error != null)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(children: [
                  Text(_error!, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                  const SizedBox(height: 10),
                  FilledButton.tonal(onPressed: _load, child: Text(T.s('Retry', lang))),
                ]),
              ),
            )
          else if (!_linked)
            _empty(lang, notLinked: true)
          else if (_list.isEmpty)
            _empty(lang)
          else
            ..._list.map((l) {
              final emp = l['employee'] is Map ? Map<String, dynamic>.from(l['employee'] as Map) : null;
              final issuedTo = l['issuedTo'] as String?;
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.push('/letters/${l['id']}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: HMC.primaryFade, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.description_outlined, color: HMC.primaryDark, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${l['ref']}', style: const TextStyle(fontWeight: FontWeight.w900, color: HMC.ink, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(
                            '${l['typeLabel']}${issuedTo != null && issuedTo.isNotEmpty ? ' → $issuedTo' : ''} · ${_date(l['createdAt'])}',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (emp != null)
                            Text('${emp['name']} · ${emp['code']}',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 10.5, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                      Icon(Icons.chevron_right, color: Colors.grey.shade300),
                    ]),
                  ),
                ),
              );
            }),
        ]),
      ),
    );
  }

  Widget _empty(String lang, {bool notLinked = false}) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(children: [
        Icon(Icons.mail_outline, size: 40, color: Colors.grey.shade300),
        const SizedBox(height: 10),
        Text(
          notLinked ? T.s('Your login is not linked to an employee profile yet — ask HR.', lang) : T.s('No letters issued yet', lang),
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        if (!notLinked) ...[
          const SizedBox(height: 4),
          Text(T.s('HR generates them from your profile — they appear here instantly.', lang),
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
        ],
      ]),
    );
  }
}
