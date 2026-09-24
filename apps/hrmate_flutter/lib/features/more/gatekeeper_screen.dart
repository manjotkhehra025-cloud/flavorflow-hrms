import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';

/// Gatekeeper mode (mockup p4-gatekeeper): scan a coworker's QR → verified view.
class GatekeeperScreen extends ConsumerStatefulWidget {
  const GatekeeperScreen({super.key});

  @override
  ConsumerState<GatekeeperScreen> createState() => _GatekeeperScreenState();
}

class _GatekeeperScreenState extends ConsumerState<GatekeeperScreen> {
  final MobileScannerController _ctl = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _busy = false;
  Map<String, dynamic>? _result;
  String? _error;

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (_busy || _result != null) return;
    final raw = cap.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    setState(() => _busy = true);
    try {
      final res = await ref.read(apiProvider).post('/api/gate', data: {'token': raw});
      if (!mounted) return;
      setState(() => _result = (res.data ?? const {}).cast<String, dynamic>());
    } catch (e) {
      final msg = apiErrorMessage(e);
      if (!mounted) return;
      setState(() => _error = msg);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() { _error = null; _busy = false; });
      });
    } finally {
      if (mounted && _result == null) {
        // allow the next scan attempt after the error window
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted && _result == null) setState(() => _busy = false);
        });
      } else if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    if (_result != null) return _verified(lang, _result!);
    return Scaffold(
      backgroundColor: HMC.ink,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(T.s('Gate scan', lang), style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(icon: const Icon(Icons.flash_on), onPressed: () => _ctl.toggleTorch()),
          IconButton(icon: const Icon(Icons.flip_camera_ios), onPressed: () => _ctl.switchCamera()),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(children: [
              MobileScanner(controller: _ctl, onDetect: _onDetect),
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 240, height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(color: HMC.primary, width: 3),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
              if (_busy) const Center(child: CircularProgressIndicator(color: HMC.primary)),
              if (_error != null)
                Positioned(
                  left: 16, right: 16, bottom: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: HMC.danger, fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            T.s('Point at the gate QR on their phone', lang),
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      ]),
    );
  }

  Widget _verified(String lang, Map<String, dynamic> r) {
    final emp = ((r['employee'] as Map?) ?? const {}).cast<String, dynamic>();
    final today = ((r['today'] as Map?) ?? const {}).cast<String, dynamic>();
    final shift = ((emp['shift'] as Map?) ?? const {}).cast<String, dynamic>();
    final ok = r['verified'] == true;
    final name = '${emp['name'] ?? '—'}';
    final initials = name.trim().isEmpty ? '?' : name.trim().split(RegExp(r'\s+')).map((w) => w[0]).take(2).join().toUpperCase();
    final checkedIn = today['checkedIn'] as String?;

    return Scaffold(
      appBar: AppBar(title: Text(T.s('Gate scan', lang))),
      backgroundColor: HMC.bg,
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 26, 20, 26), children: [
        Column(children: [
          Container(
            width: 86, height: 86,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: HMC.primaryDark),
            child: Icon(ok ? Icons.check : Icons.close, color: Colors.white, size: 46),
          ),
          const SizedBox(height: 10),
          Text(ok ? T.s('Verified', lang) : T.s('Not verified', lang),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: HMC.ink)),
        ]),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 14, offset: Offset(0, 6))]),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 30, backgroundColor: HMC.primaryFade, child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w900, color: HMC.primaryDark, fontSize: 20))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5, color: HMC.ink)),
                const SizedBox(height: 8),
                Row(children: [
                  _kv3('ID number', '${emp['code'] ?? '—'}'),
                  _kv3('Department', '${emp['department'] ?? '—'}'),
                  if (shift.isNotEmpty) _kv3("Today's shift", '${shift['startTime']}+${((shift['durationH'] as num?) ?? 0).round()}h'),
                ]),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: checkedIn == null ? HMC.bg : HMC.primaryFade, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    checkedIn == null ? T.s('Not punched in yet', lang) : '${T.s('Checked in', lang)} ${_hhmm(checkedIn)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: checkedIn == null ? Colors.grey.shade600 : HMC.primaryDark,
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: HMC.warnFade, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: HMC.amber, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(T.s('Manually double-check the photo matches', lang), style: TextStyle(color: Colors.grey.shade800, fontSize: 12.5, fontWeight: FontWeight.w600))),
          ]),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: HMC.primaryDark, minimumSize: const Size.fromHeight(54)),
          icon: const Icon(Icons.login),
          label: Text(T.s('Allow entry', lang), style: const TextStyle(fontWeight: FontWeight.w900)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: HMC.ink,
            side: BorderSide(color: Colors.grey.shade400),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(T.s('Scan next', lang), style: const TextStyle(fontWeight: FontWeight.w800)),
          onPressed: () => setState(() => _result = null),
        ),
      ]),
    );
  }

  Widget _kv3(String k, String v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: HMC.ink)),
        ]),
      );

  String _hhmm(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
