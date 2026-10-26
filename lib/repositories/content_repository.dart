import '../models/announcement.dart';
import '../models/holiday.dart';

/// Company content: holidays and announcements.
abstract class ContentRepository {
  Future<List<Holiday>> getHolidays(int year);
  Future<List<Announcement>> getAnnouncements();
  Future<Announcement> addAnnouncement({required String title, required String body, required String author, bool pinned = false});
  Future<void> deleteAnnouncement(String id);
}
