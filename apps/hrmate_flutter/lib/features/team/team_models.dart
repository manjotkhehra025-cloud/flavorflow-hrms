import '../../core/i18n.dart';
import '../../core/widgets.dart';

class TeamDepartment {
  final String id;
  final String name;
  const TeamDepartment(this.id, this.name);
}

class TeamMember {
  final String id, name, dept, shift, status;
  final String? photo, inAt, outAt;
  final bool completed;
  final int weeklyOff;

  TeamMember.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String,
        dept = json['dept'] as String,
        shift = json['shift'] as String,
        status = json['status'] as String,
        photo = json['photo'] as String?,
        inAt = json['inAt'] as String?,
        outAt = json['outAt'] as String?,
        completed = json['completed'] == true,
        weeklyOff = (json['weeklyOff'] as num).toInt();

  TeamMember.withWeeklyOff(TeamMember row, this.weeklyOff)
      : id = row.id, name = row.name, dept = row.dept, shift = row.shift,
        status = row.status, photo = row.photo, inAt = row.inAt,
        outAt = row.outAt, completed = row.completed;
}

class TeamLeave {
  final String id, name, dept, fromDate, toDate, type;
  final num days;

  TeamLeave.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String,
        dept = json['dept'] as String,
        fromDate = json['fromDate'] as String,
        toDate = json['toDate'] as String,
        type = json['type'] as String,
        days = json['days'] as num;
}

class TeamSnapshot {
  final String activeDept;
  final List<TeamMember> rows;
  final List<TeamDepartment> departments;
  final List<TeamLeave> leaves;
  final Map<String, int> counts;

  TeamSnapshot.fromJson(Map<String, dynamic> json)
      : activeDept = json['activeDept'] as String,
        rows = asMaps(json['rows']).map(TeamMember.fromJson).toList(),
        departments = asMaps(json['departments'])
            .map((d) => TeamDepartment(d['id'] as String, d['name'] as String)).toList(),
        leaves = asMaps(json['leaves']).map(TeamLeave.fromJson).toList(),
        counts = (json['counts'] as Map).map((k, v) => MapEntry('$k', (v as num).toInt()));

  TeamSnapshot.withWeeklyOff(TeamSnapshot data, String employeeId, int day)
      : activeDept = data.activeDept,
        rows = data.rows.map((r) => r.id == employeeId ? TeamMember.withWeeklyOff(r, day) : r).toList(),
        departments = data.departments, leaves = data.leaves, counts = data.counts;
}

// API date-only values must not be converted to a device timezone.
String teamShortDate(String iso, String lang) {
  final date = DateTime.tryParse(iso);
  if (date == null) return '—';
  return '${date.day} ${T.s(kMonthsShort[date.month - 1], lang)}';
}

const teamDayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const teamDayLabels = ['Sun off', 'Mon off', 'Tue off', 'Wed off', 'Thu off', 'Fri off', 'Sat off'];
