enum AttendanceStatus { present, absent, leave, holiday, weekend, notMarked }

extension AttendanceStatusX on AttendanceStatus {
  String get label {
    switch (this) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.leave:
        return 'On Leave';
      case AttendanceStatus.holiday:
        return 'Holiday';
      case AttendanceStatus.weekend:
        return 'Week Off';
      case AttendanceStatus.notMarked:
        return 'Not Marked';
    }
  }
}

/// GPS position captured at punch time.
/// TODO(geo): fill this from the device GPS (e.g. the `geolocator` package).
class PunchLocation {
  const PunchLocation({required this.latitude, required this.longitude, this.accuracyMeters});
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.employeeId,
    required this.date,
    required this.status,
    this.punchIn,
    this.punchOut,
    this.punchInLocation,
    this.punchOutLocation,
    this.selfieUrl,
    this.note,
  });

  final String employeeId;

  /// The calendar day (time part is ignored).
  final DateTime date;
  final AttendanceStatus status;
  final DateTime? punchIn;
  final DateTime? punchOut;
  final PunchLocation? punchInLocation;
  final PunchLocation? punchOutLocation;

  /// TODO(selfie): URL/path of the selfie captured at punch-in.
  final String? selfieUrl;
  final String? note;

  bool get hasPunchedIn => punchIn != null;
  bool get hasPunchedOut => punchOut != null;
  bool get isWorking => punchIn != null && punchOut == null;

  Duration get workedDuration {
    if (punchIn == null) return Duration.zero;
    final end = punchOut ?? DateTime.now();
    final d = end.difference(punchIn!);
    return d.isNegative ? Duration.zero : d;
  }

  AttendanceRecord copyWith({
    AttendanceStatus? status,
    DateTime? punchIn,
    DateTime? punchOut,
    PunchLocation? punchInLocation,
    PunchLocation? punchOutLocation,
    String? selfieUrl,
    String? note,
  }) {
    return AttendanceRecord(
      employeeId: employeeId,
      date: date,
      status: status ?? this.status,
      punchIn: punchIn ?? this.punchIn,
      punchOut: punchOut ?? this.punchOut,
      punchInLocation: punchInLocation ?? this.punchInLocation,
      punchOutLocation: punchOutLocation ?? this.punchOutLocation,
      selfieUrl: selfieUrl ?? this.selfieUrl,
      note: note ?? this.note,
    );
  }
}
