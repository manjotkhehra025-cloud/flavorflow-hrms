import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class SocialWallScreen extends StatefulWidget {
  const SocialWallScreen({super.key});

  @override
  State<SocialWallScreen> createState() => _SocialWallScreenState();
}

class _SocialWallScreenState extends State<SocialWallScreen> {
  List<Map<String, dynamic>> _posts = const [];
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
      final response = await AppScope.of(context).api.get('social-posts');
      if (!mounted) return;
      setState(() => _posts = asJsonList(asJsonMap(response)['items']));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newPost() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _PostComposerDialog(),
    );
    if (text == null || !mounted) return;
    try {
      await AppScope.of(context).api.post('social-posts', {'body': text});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your post is on the Social Wall.')),
      );
      await _load();
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _toggleLike(Map<String, dynamic> post) async {
    final id = stringValue(post['id']);
    try {
      final response = await AppScope.of(context).api.post('social-posts/$id/like');
      if (!mounted) return;
      final updated = asJsonMap(asJsonMap(response)['post']);
      setState(() {
        _posts = _posts.map((item) => stringValue(item['id']) == id ? updated : item).toList();
      });
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _addComment(Map<String, dynamic> post) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _CommentDialog(postAuthor: stringValue(post['author_name'])),
    );
    if (text == null || !mounted) return;
    final id = stringValue(post['id']);
    try {
      final response = await AppScope.of(context).api.post(
        'social-posts/$id/comments',
        {'body': text},
      );
      if (!mounted) return;
      final updated = asJsonMap(response);
      setState(() {
        _posts = _posts.map((item) => stringValue(item['id']) == id ? updated : item).toList();
      });
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _moderate(Map<String, dynamic> post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this post?'),
        content: const Text('It will no longer appear on the Social Wall.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AppScope.of(context).api.delete('social-posts/${post['id']}');
      if (!mounted) return;
      setState(() => _posts = _posts.where((item) => item['id'] != post['id']).toList());
      _showMessage('Post removed.');
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeading(
                    title: 'Social Wall',
                    subtitle: 'Share updates, recognize the team, and stay connected.',
                    trailing: IconButton.filledTonal(
                      onPressed: _load,
                      tooltip: 'Refresh feed',
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ),
                  AppPanel(
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      children: [
                        PersonAvatar(name: user.fullName, size: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _newPost,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                              decoration: BoxDecoration(
                                color: AppColors.canvas,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Text('Share an update with the team…', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _newPost,
                          tooltip: 'Create post',
                          icon: const Icon(Icons.edit_note_rounded, color: AppColors.blue),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ErrorNotice(message: _error!, onRetry: _load)
                  else if (_loading && _posts.isEmpty) const SizedBox(height: 220, child: LoadingView(label: 'Loading the Social Wall…'))
                  else if (_posts.isEmpty)
                    const AppPanel(child: EmptyNotice(
                      title: 'Nothing on the wall yet',
                      subtitle: 'Start the conversation by sharing a team update.',
                      icon: Icons.forum_outlined,
                    ))
                  else
                    ..._posts.map((post) => Padding(
                          padding: const EdgeInsets.only(bottom: 13),
                          child: _PostCard(
                            post: post,
                            canModerate: user.can('social.manage'),
                            onLike: () => _toggleLike(post),
                            onComment: () => _addComment(post),
                            onModerate: () => _moderate(post),
                          ),
                        )),
                  if (_loading && _posts.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.canModerate,
    required this.onLike,
    required this.onComment,
    required this.onModerate,
  });

  final Map<String, dynamic> post;
  final bool canModerate;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onModerate;

  @override
  Widget build(BuildContext context) {
    final author = stringValue(post['author_name'], fallback: 'Team member');
    final comments = asJsonList(post['comments']);
    final liked = post['liked_by_me'] == true;
    return AppPanel(
      padding: const EdgeInsets.fromLTRB(17, 16, 17, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PersonAvatar(name: author, size: 42),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(author, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 3),
                  Text(_timeLabel(stringValue(post['created_at'])), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ]),
              ),
              if (canModerate)
                IconButton(onPressed: onModerate, tooltip: 'Moderate post', icon: const Icon(Icons.more_horiz_rounded, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 14),
          Text(stringValue(post['body']), style: const TextStyle(color: AppColors.ink, fontSize: 13, height: 1.55)),
          const SizedBox(height: 13),
          Row(
            children: [
              Text('${stringValue(post['like_count'], fallback: '0')} likes', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              const SizedBox(width: 12),
              Text('${stringValue(post['comment_count'], fallback: '0')} comments', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              const Spacer(),
              TextButton.icon(
                onPressed: onLike,
                icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 17, color: liked ? const Color(0xFFE35D6A) : AppColors.blue),
                label: Text(liked ? 'Liked' : 'Like'),
              ),
              TextButton.icon(
                onPressed: onComment,
                icon: const Icon(Icons.mode_comment_outlined, size: 16),
                label: const Text('Comment'),
              ),
            ],
          ),
          if (comments.isNotEmpty) ...[
            const Divider(height: 8),
            ...comments.map((comment) => Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    PersonAvatar(name: stringValue(comment['author_name']), size: 27),
                    const SizedBox(width: 8),
                    Expanded(child: RichText(text: TextSpan(style: const TextStyle(color: AppColors.ink, fontSize: 11, height: 1.45), children: [
                      TextSpan(text: '${stringValue(comment['author_name'])}  ', style: const TextStyle(fontWeight: FontWeight.w800)),
                      TextSpan(text: stringValue(comment['body'])),
                    ]))),
                  ]),
                )),
          ],
        ],
      ),
    );
  }
}

class _PostComposerDialog extends StatefulWidget {
  const _PostComposerDialog();

  @override
  State<_PostComposerDialog> createState() => _PostComposerDialogState();
}

class _PostComposerDialogState extends State<_PostComposerDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Share an update'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 2000,
            maxLines: 6,
            minLines: 4,
            decoration: const InputDecoration(hintText: 'What would you like your team to know?'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final text = _controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(context, text);
            },
            child: const Text('Post'),
          ),
        ],
      );
}

class _CommentDialog extends StatefulWidget {
  const _CommentDialog({required this.postAuthor});
  final String postAuthor;

  @override
  State<_CommentDialog> createState() => _CommentDialogState();
}

class _CommentDialogState extends State<_CommentDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Comment on ${widget.postAuthor}’s post'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Write a supportive comment…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final text = _controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(context, text);
            },
            child: const Text('Send'),
          ),
        ],
      );
}

String _timeLabel(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return 'Recently';
  final difference = DateTime.now().difference(date);
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return '${date.day}/${date.month}/${date.year}';
}
