import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';

/// Offline punch queue (P2): when the network dies mid-punch, we keep the
/// selfie file path + coordinates here and let the user retry with one tap.
class PendingPunch {
  final String action; // 'checkin' | 'checkout'
  final String selfiePath; // local file path
  final double? lat;
  final double? lng;
  final int queuedAtMs;

  const PendingPunch({
    required this.action,
    required this.selfiePath,
    this.lat,
    this.lng,
    required this.queuedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'action': action,
        'selfiePath': selfiePath,
        'lat': lat,
        'lng': lng,
        'queuedAtMs': queuedAtMs,
      };
  static PendingPunch fromJson(Map<String, dynamic> j) => PendingPunch(
        action: j['action'] as String,
        selfiePath: j['selfiePath'] as String,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        queuedAtMs: (j['queuedAtMs'] as num).toInt(),
      );
}

class PunchQueue extends ChangeNotifier {
  static const _kKey = 'hm_pending_punch';
  PendingPunch? _pending;
  bool syncBusy = false;
  PendingPunch? get pending => _pending;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw != null) {
      try {
        _pending = PendingPunch.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        _pending = null;
      }
    }
    notifyListeners();
  }

  Future<void> enqueue(PendingPunch p) async {
    _pending = p;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(p.toJson()));
    notifyListeners();
  }

  Future<void> clear(WidgetRef ref) async {
    _pending = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
    notifyListeners();
  }

  /// Try the queued punch once. Returns null on success, or the error text.
  Future<String?> sync(WidgetRef ref) async {
    if (_pending == null) return null;
    syncBusy = true;
    notifyListeners();
    try {
      final dio = ref.read(apiProvider);
      // selfie still lives locally — re-upload as data-URL like the live flow
      final file = File(_pending!.selfiePath);
      if (!await file.exists()) return 'Selfie file is gone on this device.';
      final b64 = base64Encode(await file.readAsBytes());
      final up = await dio.post<Map<String, dynamic>>(
        '/api/attendance/selfie',
        data: {'dataUrl': 'data:image/jpeg;base64,$b64'},
      );
      await dio.post<Map<String, dynamic>>('/api/attendance', data: {
        'action': _pending!.action,
        'lat': _pending!.lat,
        'lng': _pending!.lng,
        'selfieRef': (up.data ?? {})['path'],
      });
      await file.delete().catchError((_) => file);
      await clear(ref);
      return null;
    } catch (e) {
      return apiErrorMessage(e);
    } finally {
      syncBusy = false;
      notifyListeners();
    }
  }
}

final punchQueueProvider = ChangeNotifierProvider<PunchQueue>((ref) {
  final q = PunchQueue();
  // ignore: discarded_futures
  q.load();
  return q;
});
