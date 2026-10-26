enum HolidayType { national, festival, optional }

extension HolidayTypeX on HolidayType {
  String get label {
    switch (this) {
      case HolidayType.national:
        return 'National';
      case HolidayType.festival:
        return 'Festival';
      case HolidayType.optional:
        return 'Optional';
    }
  }
}

class Holiday {
  const Holiday({required this.name, required this.date, this.type = HolidayType.festival});
  final String name;
  final DateTime date;
  final HolidayType type;
}
