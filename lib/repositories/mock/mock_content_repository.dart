import '../../models/announcement.dart';
import '../../models/holiday.dart';
import '../content_repository.dart';
import 'mock_database.dart';

class MockContentRepository implements ContentRepository {
  MockContentRepository(this._db);
  final MockDatabase _db;
  int _seq = 100;

  @override
  Future<List<Holiday>> getHolidays(int year) async {
    await MockDatabase.latency();
    final list = _db.holidays.where((h) => h.date.year == year).toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  @override
  Future<List<Announcement>> getAnnouncements() async {
    await MockDatabase.latency();
    final list = List<Announcement>.from(_db.announcements);
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.date.compareTo(a.date);
    });
    return list;
  }

  @override
  Future<Announcement> addAnnouncement({required String title, required String body, required String author, bool pinned = false}) async {
    await MockDatabase.latency();
    final a = Announcement(
      id: 'A${_seq++}',
      title: title.trim(),
      body: body.trim(),
      date: DateTime.now(),
      author: author,
      pinned: pinned,
    );
    _db.announcements.add(a);
    // TODO(push): send a push notification to all employees.
    return a;
  }

  @override
  Future<void> deleteAnnouncement(String id) async {
    await MockDatabase.latency();
    _db.announcements.removeWhere((a) => a.id == id);
  }
}
