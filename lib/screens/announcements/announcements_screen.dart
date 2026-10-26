import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/content_provider.dart';
import '../../widgets/common.dart';

class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ContentProvider>();
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      floatingActionButton: auth.isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _showAdd(context),
              icon: const Icon(Icons.add),
              label: const Text('Post'),
            )
          : null,
      body: c.announcements.isEmpty
          ? const EmptyState(icon: Icons.campaign_outlined, message: 'No announcements')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: c.announcements.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final a = c.announcements[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (a.pinned) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.push_pin, size: 18, color: AppTheme.warning)),
                            Expanded(child: Text(a.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                            if (auth.isAdmin)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                tooltip: 'Delete',
                                onPressed: () => c.deleteAnnouncement(a.id),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(a.body),
                        const SizedBox(height: 10),
                        Text('${a.author}  \u2022  ${Fmt.date(a.date)}', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _showAdd(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    var pinned = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('New announcement'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
                const SizedBox(height: 12),
                TextField(controller: bodyCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Message')),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: pinned,
                  onChanged: (v) => setLocal(() => pinned = v ?? false),
                  title: const Text('Pin to top'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Post')),
          ],
        ),
      ),
    );
    if (ok == true && titleCtrl.text.trim().isNotEmpty && context.mounted) {
      final author = context.read<AuthProvider>().user?.name ?? 'HR';
      await context.read<ContentProvider>().addAnnouncement(
            title: titleCtrl.text,
            body: bodyCtrl.text,
            author: author,
            pinned: pinned,
          );
      if (context.mounted) showSnack(context, 'Announcement posted');
    }
    titleCtrl.dispose();
    bodyCtrl.dispose();
  }
}
