class RosterCell {
  final String shiftId;
  final bool isOff;
  const RosterCell({this.shiftId = '', this.isOff = false});

  factory RosterCell.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return RosterCell(shiftId: '${map['shiftId'] ?? ''}', isOff: map['isOff'] == true);
  }

  bool same(RosterCell other) => shiftId == other.shiftId && isOff == other.isOff;

  Map<String, dynamic> toJson(String employeeId, String date) => {
    'employeeId': employeeId, 'date': date, 'shiftId': isOff || shiftId.isEmpty ? null : shiftId, 'isOff': isOff,
  };
}

class RosterShift {
  final String id, name, startTime;
  final double durationH;
  const RosterShift({required this.id, required this.name, required this.startTime, required this.durationH});

  factory RosterShift.fromJson(Map json) => RosterShift(
    id: '${json['id']}', name: '${json['name'] ?? ''}', startTime: '${json['startTime'] ?? ''}',
    durationH: (json['durationH'] as num?)?.toDouble() ?? 9,
  );

  String get short {
    final lower = name.toLowerCase();
    if (lower.contains('night')) return 'Night';
    if (lower.contains('season')) return 'Sea';
    if (lower.contains('general') || lower.contains('day')) return 'Day';
    final first = name.trim().split(RegExp(r'\s+')).first;
    return first.length <= 6 ? first : first.substring(0, 5);
  }
}

class RosterEmployee {
  final String id, code, name, dept, deptId;
  final String? defShift, defStart;
  final Map<String, RosterCell> cells;
  const RosterEmployee({
    required this.id, required this.code, required this.name, required this.dept, required this.deptId,
    required this.defShift, required this.defStart, required this.cells,
  });

  factory RosterEmployee.fromJson(Map json) {
    final raw = json['cells'];
    final cells = <String, RosterCell>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        cells['${entry.key}'] = RosterCell.fromJson(entry.value);
      }
    }
    return RosterEmployee(
      id: '${json['id']}', code: '${json['code'] ?? ''}', name: '${json['name'] ?? ''}',
      dept: '${json['dept'] ?? '—'}', deptId: '${json['deptId'] ?? ''}',
      defShift: json['defShift'] as String?, defStart: json['defStart'] as String?,
      cells: cells,
    );
  }
}

class RosterSwap {
  final String id, requester, peer, date, status;
  final String? note;
  final bool mine;
  const RosterSwap({
    required this.id, required this.requester, required this.peer, required this.date,
    required this.status, required this.note, required this.mine,
  });

  factory RosterSwap.fromJson(Map json) => RosterSwap(
    id: '${json['id']}', requester: '${json['requester'] ?? ''}', peer: '${json['peer'] ?? ''}',
    date: '${json['date'] ?? ''}', status: '${json['status'] ?? ''}',
    note: json['note'] as String?, mine: json['mine'] == true,
  );
}

class RosterPeer {
  final String id, name, code;
  final String? department;
  const RosterPeer({required this.id, required this.name, required this.code, required this.department});
  factory RosterPeer.fromJson(Map json) => RosterPeer(
    id: '${json['id']}', name: '${json['name'] ?? ''}', code: '${json['code'] ?? ''}',
    department: json['department'] as String?,
  );
}

class RosterDepartment {
  final String id, name;
  const RosterDepartment(this.id, this.name);
  factory RosterDepartment.fromJson(Map json) => RosterDepartment('${json['id']}', '${json['name'] ?? ''}');
}

class RosterSnapshot {
  final String weekStart, weekEnd, prevW, nextW, today;
  final List<String> days;
  final List<RosterDepartment> departments;
  final List<RosterShift> shifts;
  final List<RosterEmployee> employees;
  final List<RosterSwap> swaps;
  final List<RosterPeer> peers;
  final String? myEmployeeId;
  final bool canSwap;
  final int pendingSwapCount;

  const RosterSnapshot({
    required this.weekStart, required this.weekEnd, required this.prevW, required this.nextW, required this.today,
    required this.days, required this.departments, required this.shifts, required this.employees,
    required this.swaps, required this.peers, required this.myEmployeeId, required this.canSwap,
    required this.pendingSwapCount,
  });

  factory RosterSnapshot.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map) parse) =>
      ((json[key] as List?) ?? const []).whereType<Map>().map((e) => parse(e)).toList();
    return RosterSnapshot(
      weekStart: '${json['weekStart'] ?? ''}', weekEnd: '${json['weekEnd'] ?? ''}',
      prevW: '${json['prevW'] ?? ''}', nextW: '${json['nextW'] ?? ''}', today: '${json['today'] ?? ''}',
      days: ((json['days'] as List?) ?? const []).map((e) => '$e').toList(),
      departments: list('departments', RosterDepartment.fromJson),
      shifts: list('shifts', RosterShift.fromJson),
      employees: list('employees', RosterEmployee.fromJson),
      swaps: list('swaps', RosterSwap.fromJson),
      peers: list('peers', RosterPeer.fromJson),
      myEmployeeId: json['myEmployeeId'] as String?,
      canSwap: json['canSwap'] == true,
      pendingSwapCount: (json['pendingSwapCount'] as num?)?.toInt() ?? 0,
    );
  }

  RosterSnapshot withSwaps(List<RosterSwap> swaps) => RosterSnapshot(
    weekStart: weekStart, weekEnd: weekEnd, prevW: prevW, nextW: nextW, today: today,
    days: days, departments: departments, shifts: shifts, employees: employees,
    swaps: swaps, peers: peers, myEmployeeId: myEmployeeId, canSwap: canSwap,
    pendingSwapCount: swaps.where((s) => s.status == 'PENDING').length,
  );
}

const rosterDow = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const rosterMonths = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String rosterWeekTitle(List<String> days) {
  if (days.length < 7) return days.join('–');
  final last = DateTime.tryParse(days[6]);
  final month = last == null ? '' : ' ${rosterMonths[last.month - 1]}';
  return '${days[0].substring(8)}–${days[6].substring(8)}$month';
}

String rosterShortDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null || iso.length < 10) return iso;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]}';
}
