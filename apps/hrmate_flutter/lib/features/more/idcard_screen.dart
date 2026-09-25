import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// (path_provider is a declared pubspec dep)
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';

final idcardProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = ref.read(apiProvider);
  final res = await dio.get<Map<String, dynamic>>('/api/idcard');
  return res.data ?? const {};
});

/// Digital ID badge (mockup p4-idcard) + QR gate sheet + PNG share.
class IdCardScreen extends ConsumerWidget {
  IdCardScreen({super.key});

  final _repaintKey = GlobalKey();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final data = ref.watch(idcardProvider);

    return Scaffold(
      appBar: AppBar(title: Text(T.s('My ID card', lang))),
      backgroundColor: HMC.bg,
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator(color: HMC.primary)),
        error: (e, _) => Center(child: Text(apiErrorMessage(e))),
        data: (j) {
          final shift = (j['shift'] as Map?)?.cast<String, dynamic>();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
            children: [
              RepaintBoundary(key: _repaintKey, child: _badge(j, shift)),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: HMC.primaryDark, minimumSize: const Size.fromHeight(54)),
                icon: const Icon(Icons.qr_code_2),
                label: Text(T.s('Show QR at gate', lang), style: const TextStyle(fontWeight: FontWeight.w900)),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  isDismissible: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => GateQrSheet(name: '${j['name']}', code: '${j['code']}'),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: HMC.primaryDark,
                  side: const BorderSide(color: HMC.primaryDark),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.share_outlined),
                label: Text(T.s('Download / share PNG', lang), style: const TextStyle(fontWeight: FontWeight.w800)),
                onPressed: () => _sharePng(context, '${j['code']}'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _badge(Map<String, dynamic> j, Map<String, dynamic>? shift) {
    final name = '${j['name']}';
    final initials = name.trim().isEmpty ? '?' : name.trim().split(RegExp(r'\s+')).map((w) => w[0]).take(2).join().toUpperCase();
    return Container(
      decoration: BoxDecoration(
        color: HMC.ink,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 22, offset: Offset(0, 10))],
      ),
      child: Stack(children: [
        // emerald swoosh decoration
        Positioned(
          bottom: -70, right: -70,
          child: Container(
            width: 220, height: 220,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: HMC.primary.withOpacity(0.25), width: 26)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
          child: Column(children: [
            Row(children: [
              Image.asset('assets/hrmate_emblem.png', width: 30, height: 30),
              const SizedBox(width: 8),
              const Text('HRMate', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.3)),
            ]),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: HMC.primary, width: 3)),
              child: CircleAvatar(
                radius: 38,
                backgroundColor: const Color(0xFF1E293B),
                child: Text(initials, style: const TextStyle(color: HMC.primary, fontWeight: FontWeight.w900, fontSize: 26)),
              ),
            ),
            const SizedBox(height: 12),
            Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 2),
            Text('Employee ID: ${j['code']}', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            const SizedBox(height: 14),
            _row('Designation', '${j['designation'] ?? '—'}'),
            _row('Department', '${j['department'] ?? '—'}'),
            _row('Blood Group', j['bloodGroup'] != null ? '🩸 ${j['bloodGroup']}' : '—'),
            _row('Joined', _fmtJoin(j['joined'] as String?)),
            _row('Phone', '${j['phone'] ?? '—'}'),
            if (shift != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.07), borderRadius: BorderRadius.circular(12)),
                  child: Text('${shift['name']} · ${shift['startTime']} +${shift['durationH']}h',
                      style: const TextStyle(color: HMC.primary, fontWeight: FontWeight.w800, fontSize: 12.5)),
                ),
              ),
            const SizedBox(height: 10),
            Text('${j['company']}', style: const TextStyle(color: Colors.white38, fontSize: 10.5, letterSpacing: 0.3)),
          ]),
        ),
      ]),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.5),
        child: Row(children: [
          Text('$k:  ', style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
          Expanded(child: Text(v, style: const TextStyle(color: Colors.white, fontSize: 12.8, fontWeight: FontWeight.w600))),
        ]),
      );

  String _fmtJoin(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.day.toString().padLeft(2, '0')} ${_const3(d.month)} ${d.year}';
  }

  String _const3(int m) => const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];

  Future<void> _sharePng(BuildContext context, String code) async {
    try {
      final boundary = _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/hrmate-badge-$code.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      if (!context.mounted) return;
      await Share.shareXFiles([XFile(file.path)], subject: 'HRMate ID — $code');
    } catch (_) {/* share sheet dismissed or unsupported */}
  }
}

/// ── Gate QR sheet (mockup p4-qr) — HMAC token QR with live refresh countdown ──

class GateQrSheet extends ConsumerStatefulWidget {
  final String name;
  final String code;
  const GateQrSheet({super.key, required this.name, required this.code});

  @override
  ConsumerState<GateQrSheet> createState() => _GateQrSheetState();
}

class _GateQrSheetState extends ConsumerState<GateQrSheet> {
  Timer? _tick;
  String? _token;
  int _refreshIn = 30;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_refreshIn <= 1) {
        _load();
      } else {
        setState(() => _refreshIn--);
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(apiProvider).get<Map<String, dynamic>>('/api/gate');
      if (!mounted) return;
      setState(() {
        _token = res.data?['token'] as String?;
        _refreshIn = (res.data?['refreshInSec'] as num?)?.toInt() ?? 30;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = apiErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    return Container(
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: HMC.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 26),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Spacer(),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
        ]),
        Text(
          T.s('Show this at the factory gate', lang),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: HMC.ink),
        ),
        const SizedBox(height: 2),
        Text(lang == 'pa' ? 'ਗੇਟ ਉੱਤੇ ਦਿਖਾਓ' : 'ਗੇਟ ਉੱਤੇ ਦਿਖਾਓ',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 16)]),
          child: _error != null
              ? SizedBox(height: 220, child: Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center))))
              : _token == null
                  ? const SizedBox(height: 220, child: Center(child: CircularProgressIndicator(color: HMC.primary)))
                  : QrImageView(data: _token!, size: 220, backgroundColor: Colors.white, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: HMC.ink), dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: HMC.ink)),
        ),
        const SizedBox(height: 14),
        Text('${widget.name} · ${widget.code}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: HMC.ink)),
        const SizedBox(height: 4),
        Text(T.s('Code refreshes every 30 seconds', lang), style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
          child: Text('${_refreshIn}s', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: HMC.ink)),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: HMC.ink,
            side: BorderSide(color: Colors.grey.shade400),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(T.s('Scan a coworker instead', lang), style: const TextStyle(fontWeight: FontWeight.w800)),
          onPressed: () {
            Navigator.of(context).pop();
            context.push('/gatekeeper');
          },
        ),
      ]),
    );
  }
}
