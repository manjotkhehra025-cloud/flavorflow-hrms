import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// My payslips (mockup p5-payslip): month chips → slip card (earnings,
/// deductions, NET PAY) → Share/PDF (public token link opens the printable
/// slip — "Print → Save as PDF") + copy link. Only LOCKED payroll shows,
/// and the whole screen honours the super-admin canViewPayslip switch.
class PayslipsScreen extends ConsumerStatefulWidget {
  const PayslipsScreen({super.key});

  @override
  ConsumerState<PayslipsScreen> createState() => _PayslipsScreenState();
}

class _PayslipsScreenState extends ConsumerState<PayslipsScreen> {
  List<Map<String, dynamic>> _list = [];
  final Map<String, Map<String, dynamic>> _slips = {};
  String? _selected;
  bool _loadingList = true;
  bool _loadingSlip = false;
  bool _locked = false;
  bool _sharing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadList();
  }

  String get _lang => ref.read(langProvider);

  Future<void> _loadList() async {
    setState(() {
      _loadingList = true;
      _error = null;
    });
    try {
      final res = await ref.read(apiProvider).get<Map<String, dynamic>>(
            '/api/payslips',
            queryParameters: {'lang': _lang},
          );
      final rows = asMaps(res.data?['payslips']);
      if (!mounted) return;
      setState(() {
        _list = rows;
        _locked = false;
        _slips.clear();
        _selected = rows.isEmpty ? null : '${rows.first['id']}';
      });
      final sel = _selected;
      if (sel != null) await _loadSlip(sel);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _locked = e.response?.statusCode == 403;
        _error = apiErrorMessage(e);
      });
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _loadSlip(String id) async {
    setState(() => _selected = id);
    if (_slips.containsKey(id)) return;
    setState(() => _loadingSlip = true);
    try {
      final res = await ref.read(apiProvider).get<Map<String, dynamic>>(
            '/api/payslips/$id',
            queryParameters: {'lang': _lang},
          );
      final slip = res.data?['payslip'];
      if (!mounted) return;
      if (slip is Map) setState(() => _slips[id] = Map<String, dynamic>.from(slip));
    } catch (e) {
      if (mounted) hmToast(context, apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loadingSlip = false);
    }
  }

  Future<String?> _shareUrl(String id) async {
    final res = await ref.read(apiProvider).post<Map<String, dynamic>>('/api/payslips/$id/share');
    final path = res.data?['path'];
    return path is String ? '$kApiBaseUrl$path' : null;
  }

  Future<void> _share(Map<String, dynamic> slip, {required bool copyOnly}) async {
    final lang = _lang;
    setState(() => _sharing = true);
    try {
      final url = await _shareUrl('${slip['id']}');
      if (url == null || !mounted) return;
      if (copyOnly) {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) hmToast(context, T.s('Link copied ✔', lang), ok: true);
      } else {
        await SharePlus.instance.share(ShareParams(
          text: '${T.s('Salary slip', lang)} — ${slip['monthLabel']}\n$url',
          subject: 'Payslip ${slip['month']} — ${slip['name']}',
        ));
      }
    } catch (e) {
      if (mounted) hmToast(context, apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final selected = _selected;
    final slip = selected == null ? null : _slips[selected];

    Widget body;
    if (_loadingList) {
      body = const Center(child: CircularProgressIndicator(color: HMC.primary));
    } else if (_locked) {
      body = ListView(children: [
        HmMessage(
          icon: Icons.lock_outline,
          text: T.s('Payslip viewing is turned off for you', lang),
          hint: T.s('Ask the super admin to allow this feature.', lang),
        ),
      ]);
    } else if (_error != null) {
      body = ListView(children: [
        HmMessage(icon: Icons.wifi_off_rounded, text: _error!, onRetry: _loadList, retryLabel: T.s('Retry', lang)),
      ]);
    } else if (_list.isEmpty) {
      body = ListView(children: [
        HmMessage(
          icon: Icons.receipt_long_outlined,
          text: T.s('No payslips yet', lang),
          hint: T.s('They appear here after your first locked payroll.', lang),
        ),
      ]);
    } else {
      body = ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final r = _list[i];
              final id = '${r['id']}';
              final on = id == selected;
              return ChoiceChip(
                label: Text(_chipLabel('${r['month']}')),
                selected: on,
                showCheckmark: false,
                onSelected: (_) => _loadSlip(id),
                selectedColor: HMC.ink,
                backgroundColor: const Color(0xFFE2E8F0),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                labelStyle: TextStyle(color: on ? Colors.white : HMC.ink, fontWeight: FontWeight.w700),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        if (slip == null)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Center(
              child: _loadingSlip
                  ? const CircularProgressIndicator(color: HMC.primary)
                  : Text(T.s('Could not load this slip', lang), style: TextStyle(color: Colors.grey.shade500)),
            ),
          )
        else ...[
          _SlipCard(slip: slip, lang: lang),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: HMC.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                onPressed: _sharing ? null : () => _share(slip, copyOnly: false),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                label: Text(T.s('Share / PDF', lang)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: HMC.ink,
                  minimumSize: const Size.fromHeight(48),
                  side: const BorderSide(color: HMC.ink, width: 1.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                onPressed: _sharing ? null : () => _share(slip, copyOnly: true),
                icon: const Icon(Icons.link, size: 20),
                label: Text(T.s('Copy link', lang)),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            T.s('The link opens your printable slip — use Print → Save as PDF.', lang),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
          ),
        ],
      ]);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(title: Text(T.s('My payslips', lang))),
      body: RefreshIndicator(color: HMC.primary, onRefresh: _loadList, child: body),
    );
  }

  String _chipLabel(String month) {
    final parts = month.split('-');
    if (parts.length != 2) return month;
    final m = int.tryParse(parts[1]) ?? 0;
    if (m < 1 || m > 12) return month;
    return '${kMonthsShort[m - 1]} ${parts[0]}';
  }
}

class _SlipCard extends StatelessWidget {
  final Map<String, dynamic> slip;
  final String lang;
  const _SlipCard({required this.slip, required this.lang});

  @override
  Widget build(BuildContext context) {
    final earnings = asMaps(slip['earnings']);
    final deductions = asMaps(slip['deductions']);
    final days = Map<String, dynamic>.from((slip['days'] as Map?) ?? const {});
    final bank = slip['bank'] as String?;
    final employerPf = (slip['employerPf'] as num?) ?? 0;
    final employerEsi = (slip['employerEsi'] as num?) ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x140A1628), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(color: HMC.primary, shape: BoxShape.circle),
            child: const Icon(Icons.eco, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${slip['companyName'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: HMC.ink)),
              Text('${slip['name'] ?? ''} · ${slip['code'] ?? ''}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
            ]),
          ),
        ]),
        const Divider(height: 26),
        Text('${T.s('Payslip', lang)} — ${slip['monthLabel'] ?? ''}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: HMC.ink)),
        const SizedBox(height: 2),
        Text(
          '${T.s('Employee ID', lang)}: ${slip['code'] ?? ''}  |  ${slip['dept'] ?? ''}',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        _row(T.s('Description', lang), T.s('Amount (₹)', lang), bold: true),
        const Divider(height: 10),
        for (final l in earnings) _line(l),
        const Divider(height: 10),
        _row(T.s('Total Earnings', lang), inr(slip['totalEarnings']), bold: true),
        const Divider(height: 10),
        if (deductions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(T.s('No deductions this month', lang), style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5)),
          )
        else
          for (final l in deductions) _line(l),
        const Divider(height: 10),
        _row(T.s('Total Deductions', lang), inr(slip['totalDeductions']), bold: true),
        const Divider(height: 18),
        Row(children: [
          Text(T.s('NET PAY', lang),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: HMC.emeraldDeep)),
          const Spacer(),
          Text(inr(slip['netPay']),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: HMC.emeraldDeep)),
        ]),
        const SizedBox(height: 4),
        Text(
          '${T.s('Payable days', lang)}: ${_n(days['payable'])}  |  ${T.s('Present', lang)}: ${_n(days['present'])}'
          '  |  ${T.s('Leave', lang)}: ${_n(days['leave'])}  |  ${T.s('Absent', lang)}: ${_n(days['absent'])}',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 11.5),
        ),
        Text(
          '${T.s('Paid via', lang)} ${slip['paymentMode'] ?? ''}${bank != null ? ' · $bank' : ''}',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 11.5),
        ),
        if (employerPf > 0 || employerEsi > 0) ...[
          const SizedBox(height: 8),
          Text(
            '${T.s('Company also pays on top of your salary', lang)}: '
            '${employerPf > 0 ? 'PF ${inr(employerPf)}' : ''}'
            '${employerPf > 0 && employerEsi > 0 ? ' + ' : ''}'
            '${employerEsi > 0 ? 'ESI ${inr(employerEsi)}' : ''}',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 10.5),
          ),
        ],
      ]),
    );
  }

  static String _n(Object? v) {
    if (v is num) return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return '${v ?? 0}';
  }

  Widget _line(Map<String, dynamic> l) {
    final hint = l['hint'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(T.s('${l['label']}', lang), style: const TextStyle(fontSize: 13.5, color: HMC.ink)),
            if (hint != null && hint.isNotEmpty)
              Text(hint, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ]),
        ),
        Text(inr(l['amount']), style: const TextStyle(fontSize: 13.5, color: HMC.ink)),
      ]),
    );
  }

  Widget _row(String k, String v, {bool bold = false}) {
    final st = TextStyle(fontSize: 13.5, color: HMC.ink, fontWeight: bold ? FontWeight.w800 : FontWeight.w400);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Expanded(child: Text(k, style: st)), Text(v, style: st)]),
    );
  }
}
