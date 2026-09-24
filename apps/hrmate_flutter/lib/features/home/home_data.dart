import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';

/// Server response for GET /api/attendance (home block + history rows).
class AttendanceBlock {
  final Map<String, dynamic>? today;
  final Map<String, dynamic> shift;
  final bool isWeeklyOff;
  final bool geofenceEnabled;
  final String? companyName;
  final Map<String, int> chips;
  final List<Map<String, dynamic>> records;

  const AttendanceBlock({
    required this.today,
    required this.shift,
    required this.isWeeklyOff,
    required this.geofenceEnabled,
    required this.companyName,
    required this.chips,
    required this.records,
  });

  static AttendanceBlock fromJson(Map<String, dynamic> j) => AttendanceBlock(
        today: j['today'] as Map<String, dynamic>?,
        shift: (j['shift'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{'name': 'General Day Shift', 'startTime': '08:00', 'durationH': 9},
        isWeeklyOff: j['isWeeklyOff'] == true,
        geofenceEnabled: j['geofenceEnabled'] == true,
        companyName: j['companyName'] as String?,
        chips: ((j['chips'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', v is int ? v : 0)),
        records: ((j['records'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList(),
      );

  DateTime? get checkInAt => today?['checkIn'] == null ? null : DateTime.tryParse(today!['checkIn'] as String);
  DateTime? get checkOutAt => today?['checkOut'] == null ? null : DateTime.tryParse(today!['checkOut'] as String);
}

/// Fetches fresh state for the punch loop — call `invalidate(attendanceProvider)`
/// after any punch / request to re-pull.
final attendanceProvider = FutureProvider<AttendanceBlock>((ref) async {
  final dio = ref.read(apiProvider);
  final res = await dio.get<Map<String, dynamic>>('/api/attendance');
  return AttendanceBlock.fromJson(res.data ?? const {});
});
