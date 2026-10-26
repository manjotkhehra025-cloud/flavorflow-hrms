import 'package:flutter/foundation.dart';

import '../models/announcement.dart';
import '../models/holiday.dart';
import '../repositories/content_repository.dart';

class ContentProvider extends ChangeNotifier {
  ContentProvider(this._repo);
  final ContentRepository _repo;

  List<Holiday> _holidays = [];
  List<Announcement> _announcements = [];
  bool _loading = false;
  int _year = DateTime.now().year;

  List<Holiday> get holidays => _holidays;
  List<Announcement> get announcements => _announcements;
  bool get loading => _loading;
  int get year => _year;

  Holiday? get nextHoliday {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    for (final h in _holidays) {
      if (!h.date.isBefore(start)) return h;
    }
    return null;
  }

  Future<void> load({int? year}) async {
    _year = year ?? _year;
    _loading = true;
    notifyListeners();
    try {
      _holidays = await _repo.getHolidays(_year);
      _announcements = await _repo.getAnnouncements();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> addAnnouncement({required String title, required String body, required String author, bool pinned = false}) async {
    await _repo.addAnnouncement(title: title, body: body, author: author, pinned: pinned);
    _announcements = await _repo.getAnnouncements();
    notifyListeners();
  }

  Future<void> deleteAnnouncement(String id) async {
    await _repo.deleteAnnouncement(id);
    _announcements = await _repo.getAnnouncements();
    notifyListeners();
  }
}
