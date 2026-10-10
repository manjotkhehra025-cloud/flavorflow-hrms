import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unread = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    try {
      final response = await AppScope.of(context).api.get('notifications');
      if (!mounted) return;
      setState(() => _unread = int.tryParse(stringValue(asJsonMap(response)['unread_count'])) ?? 0);
    } on ApiException {
      // Notifications are non-blocking; the center can be retried from the bell.
    }
  }

  Future<void> _open() async {
    setState(() => _loading = true);
    await showDialog<void>(
      context: context,
      builder: (_) => const _NotificationDialog(),
    );
    if (!mounted) return;
    setState(() => _loading = false);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Notifications',
        onPressed: _loading ? null : _open,
        icon: Stack(clipBehavior: Clip.none, children: [
          Icon(_loading ? Icons.hourglass_top_rounded : Icons.notifications_none_rounded, color: AppColors.muted, size: 21),
          if (_unread > 0)
            Positioned(
              right: -5,
              top: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: Color(0xFFE15460), shape: BoxShape.circle),
                child: Text(_unread > 9 ? '9+' : '$_unread', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
      );
}

class _NotificationDialog extends StatefulWidget {
  const _NotificationDialog();

  @override
  State<_NotificationDialog> createState() => _NotificationDialogState();
}

class _NotificationDialogState extends State<_NotificationDialog> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await AppScope.of(context).api.get('notifications');
      if (!mounted) return;
      setState(() => _items = asJsonList(asJsonMap(response)['items']));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(Map<String, dynamic> item) async {
    if (item['read_at'] != null) return;
    try {
      final response = await AppScope.of(context).api.patch('notifications/${item['id']}', const <String, dynamic>{});
      if (!mounted) return;
      final updated = asJsonMap(response);
      setState(() {
        _items = _items.map((entry) => entry['id'] == item['id'] ? updated : entry).toList();
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Row(children: [
          const Expanded(child: Text('Notifications')),
          IconButton(onPressed: _load, tooltip: 'Refresh notifications', icon: const Icon(Icons.refresh_rounded, size: 19)),
        ]),
        content: SizedBox(
          width: 480,
          height: 420,
          child: _loading && _items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _items.isEmpty
                  ? Center(child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12)))
                  : _items.isEmpty
                      ? const Center(child: Text('You are all caught up.', style: TextStyle(color: AppColors.muted, fontSize: 13)))
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final unread = item['read_at'] == null;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                              leading: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(color: unread ? AppColors.softBlue : AppColors.canvas, borderRadius: BorderRadius.circular(11)),
                                child: Icon(_notificationIcon(stringValue(item['kind'])), size: 17, color: unread ? AppColors.blue : AppColors.muted),
                              ),
                              title: Text(stringValue(item['title']), style: TextStyle(color: AppColors.ink, fontSize: 12, fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                              subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text('${stringValue(item['body'])}\n${_notificationTime(stringValue(item['created_at']))}', style: const TextStyle(color: AppColors.muted, fontSize: 10, height: 1.4))),
                              isThreeLine: true,
                              onTap: () => _markRead(item),
                              trailing: unread ? const Icon(Icons.circle, size: 8, color: AppColors.blue) : null,
                            );
                          },
                        ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
      );
}

IconData _notificationIcon(String kind) => switch (kind) {
      'shift_swap' => Icons.swap_horiz_rounded,
      'helpdesk_ticket' => Icons.support_agent_rounded,
      'test' => Icons.notifications_active_outlined,
      _ => Icons.notifications_none_rounded,
    };

String _notificationTime(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return '';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
