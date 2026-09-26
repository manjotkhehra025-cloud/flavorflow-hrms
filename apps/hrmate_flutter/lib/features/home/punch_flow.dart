import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'home_data.dart';
import 'punch_queue.dart';

/// Full-screen punch flow: camera preview → capture → GPS card + confirm.
/// Mirrors mockup p2-selfie.png.
class PunchFlowScreen extends ConsumerStatefulWidget {
  final String action; // 'checkin' | 'checkout'
  const PunchFlowScreen({super.key, required this.action});

  @override
  ConsumerState<PunchFlowScreen> createState() => _PunchFlowState();
}

class _PunchFlowState extends ConsumerState<PunchFlowScreen> {
  CameraController? _cam;
  String? _camError;
  XFile? _shot;
  Position? _pos;
  String? _geoError;
  int? _weakAcc;
  bool _gpsRetried = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initGps();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final c = CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await c.initialize();
      if (!mounted) return;
      setState(() => _cam = c);
    } catch (e) {
      if (mounted) setState(() => _camError = 'Camera unavailable — grant permission and retry.');
    }
  }

  Future<void> _initGps() async {
    _weakAcc = null;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _geoError = 'Location permission needed to punch.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      // Same 150 m cap as web: a coarser fix cannot prove fence membership.
      // The first fix is often the coarse one, so retry once automatically.
      if (pos.accuracy > 150 && !_gpsRetried) {
        _gpsRetried = true;
        _initGps();
        return;
      }
      if (pos.accuracy > 150) {
        setState(() {
          _pos = null;
          _geoError = null;
          _weakAcc = pos.accuracy.round();
        });
        return;
      }
      setState(() {
        _pos = pos;
        _geoError = null;
        _weakAcc = null;
      });
    } catch (e) {
      if (mounted) setState(() => _geoError = 'GPS fix failed — try near a window/gate.');
    }
  }

  @override
  void dispose() {
    _cam?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_cam == null || !_cam!.value.isInitialized) return;
    final shot = await _cam!.takePicture();
    setState(() => _shot = shot);
    if (_pos == null) _initGps(); // give GPS another chance at confirm step
  }

  Future<void> _confirm() async {
    if (_shot == null || _busy) return;
    final lang = ref.read(langProvider);
    setState(() => _busy = true);
    try {
      final dio = ref.read(apiProvider);
      final bytes = await File(_shot!.path).readAsBytes();
      final up = await dio.post<Map<String, dynamic>>(
        '/api/attendance/selfie',
        data: {'dataUrl': 'data:image/jpeg;base64,${base64Encode(bytes)}'},
      );
      await dio.post<Map<String, dynamic>>('/api/attendance', data: {
        'action': widget.action,
        'lat': _pos?.latitude,
        'lng': _pos?.longitude,
        'acc': _pos?.accuracy,
        'selfieRef': (up.data ?? {})['path'],
      });
      await File(_shot!.path).delete().catchError((_) => File(_shot!.path));
      ref.invalidate(attendanceProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.action == 'checkin' ? T.s('Checked in ✓', lang) : T.s('Checked out ✓', lang)),
        backgroundColor: HMC.primaryDark,
      ));
      context.go('/home');
    } catch (e) {
      // Offline? queue the whole punch so a tap later finishes it.
      final offline = e is DioException &&
          (e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout);
      if (offline) {
        await ref.read(punchQueueProvider).enqueue(PendingPunch(
              action: widget.action,
              selfiePath: _shot!.path,
              lat: _pos?.latitude,
              lng: _pos?.longitude,
              queuedAtMs: DateTime.now().millisecondsSinceEpoch,
            ));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(T.s('No signal — punch saved, tap Sync on Home to finish.', lang)),
          backgroundColor: HMC.warn,
        ));
        context.go('/home');
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiErrorMessage(e)),
          backgroundColor: Colors.red.shade700,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final block = ref.watch(attendanceProvider).valueOrNull;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: HMC.ink),
                    onPressed: () => context.pop(),
                  ),
                ),
                const Spacer(),
                Text(
                  T.s('Selfie confirmation', lang).toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.4, color: HMC.ink),
                ),
                const Spacer(),
                const SizedBox(width: 48),
              ]),
            ),
            const SizedBox(height: 8),
            // Camera frame / captured preview
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: _shot != null
                      ? Image.file(File(_shot!.path), fit: BoxFit.cover)
                      : _cam != null && _cam!.value.isInitialized
                          ? CameraPreview(_cam!)
                          : Container(
                              color: HMC.ink,
                              child: Center(
                                child: _camError != null
                                    ? Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Text(_camError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                                      )
                                    : const CircularProgressIndicator(color: HMC.primary),
                              ),
                            ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _pos != null
                  ? _GpsCardOk(
                      company: block?.companyName ?? 'GD Foods',
                      geofence: block?.geofenceEnabled ?? false,
                      lang: lang,
                      acc: _pos!.accuracy.round(),
                    )
                  : _weakAcc != null
                      ? _GpsCardWeak(acc: _weakAcc!, lang: lang, onRetry: _initGps)
                      : _GpsCardWait(error: _geoError, lang: lang),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              if (_shot != null) File(_shot!.path).delete().ignore();
                              _shot = null;
                            }),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const StadiumBorder(),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Text(T.s('Retake', lang), style: const TextStyle(fontWeight: FontWeight.w700, color: HMC.ink)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 2,
                  child: _GradientButton(
                    label: _busy
                        ? T.s('Saving…', lang)
                        : widget.action == 'checkin'
                            ? T.s('Confirm check-in', lang)
                            : T.s('Confirm check-out', lang),
                    icon: Icons.fingerprint,
                    onTap: _busy ? null : (_shot == null ? _capture : _confirm),
                  ),
                ),
              ]),
            ),
            Text(
              T.s('Photo is used for attendance proof only', lang),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _GpsCardOk extends StatelessWidget {
  final String company;
  final bool geofence;
  final String lang;
  final int acc;
  const _GpsCardOk({required this.company, required this.geofence, required this.lang, required this.acc});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Row(children: [
        const CircleAvatar(backgroundColor: HMC.primaryFade, child: Icon(Icons.check, color: HMC.primaryDark)),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(T.s('GPS locked', lang), style: const TextStyle(fontWeight: FontWeight.w900, color: HMC.ink, fontSize: 16)),
          Text(
            geofence
                ? '$company · ${T.s('inside factory fence', lang)} · ±${acc}m'
                : '$company · ${T.s('location attached', lang)} · ±${acc}m',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ]),
      ]),
    );
  }
}

class _GpsCardWeak extends StatelessWidget {
  final int acc;
  final String lang;
  final VoidCallback onRetry;
  const _GpsCardWeak({required this.acc, required this.lang, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HMC.warnFade,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Row(children: [
        const Icon(Icons.gps_not_fixed, color: HMC.warn),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${T.s('Weak GPS', lang)} (±$acc m) — ${T.s('stand in the open and retry', lang)}',
            style: const TextStyle(fontWeight: FontWeight.w700, color: HMC.warn, fontSize: 12.5),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          child: Text(T.s('Retry', lang), style: const TextStyle(fontWeight: FontWeight.w900, color: HMC.warn)),
        ),
      ]),
    );
  }
}

class _GpsCardWait extends StatelessWidget {
  final String? error;
  final String lang;
  const _GpsCardWait({this.error, required this.lang});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error != null ? HMC.warnFade : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Row(children: [
        if (error == null)
          const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2.4))
        else
          const Icon(Icons.location_off, color: HMC.warn),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            error ?? T.s('Getting GPS…', lang),
            style: TextStyle(fontWeight: FontWeight.w700, color: error != null ? HMC.warn : HMC.ink),
          ),
        ),
      ]),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _GradientButton({required this.label, required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.7 : 1,
      child: Material(
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF10D9A0), Color(0xFF0EA5A4)]),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      ),
    );
  }
}
