class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.date,
    required this.author,
    this.pinned = false,
  });

  final String id;
  final String title;
  final String body;
  final DateTime date;
  final String author;
  final bool pinned;
}
