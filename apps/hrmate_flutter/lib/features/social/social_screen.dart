import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Social Wall (mockup p5-social): composer on the navy header, pull-to-refresh
/// feed, like toggle (optimistic), comment thread sheet, paging ("Load more").
/// Posting obeys the super-admin canSocialPost switch; reading / liking /
/// commenting stay open to everyone — same rules as the web wall.
class SocialScreen extends ConsumerStatefulWidget {
  const SocialScreen({super.key});

  @override
  ConsumerState<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends ConsumerState<SocialScreen> {
  static const _pageSize = 30;

  final _composer = TextEditingController();
  final List<Map<String, dynamic>> _posts = [];
  bool _canPost = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _posting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more) {
      if (_loadingMore || !_hasMore || _posts.isEmpty) return;
      setState(() => _loadingMore = true);
    }
    try {
      final res = await ref.read(apiProvider).get<Map<String, dynamic>>(
            '/api/social',
            queryParameters: more ? {'before': '${_posts.last['createdAt']}'} : null,
          );
      final d = res.data ?? const <String, dynamic>{};
      final rows = asMaps(d['posts']);
      if (!mounted) return;
      setState(() {
        if (!more) _posts.clear();
        _posts.addAll(rows);
        _canPost = d['canPost'] == true;
        _hasMore = rows.length >= _pageSize;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _submitPost(String lang) async {
    final text = _composer.text.trim();
    if (text.length < 3) {
      hmToast(context, T.s('Write at least a few words.', lang));
      return;
    }
    setState(() => _posting = true);
    try {
      await ref.read(apiProvider).post('/api/social', data: {'body': text});
      _composer.clear();
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      hmToast(context, T.s('Posted to the wall ✔', lang), ok: true);
      await _load();
    } catch (e) {
      if (mounted) hmToast(context, apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _toggleLike(Map<String, dynamic> p) async {
    final was = p['liked'] == true;
    final n = (p['likes'] as num?)?.toInt() ?? 0;
    setState(() {
      p['liked'] = !was;
      p['likes'] = was ? n - 1 : n + 1;
    });
    try {
      final res = await ref.read(apiProvider).post<Map<String, dynamic>>('/api/social/${p['id']}/like');
      final d = res.data ?? const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        p['liked'] = d['liked'] == true;
        p['likes'] = (d['likes'] as num?)?.toInt() ?? p['likes'];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        p['liked'] = was;
        p['likes'] = n;
      });
      hmToast(context, apiErrorMessage(e));
    }
  }

  Future<void> _delete(Map<String, dynamic> p, String lang) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(T.s('Delete this post?', lang)),
        content: Text(T.s('It disappears from everyone\'s wall.', lang)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(T.s('Cancel', lang))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HMC.danger, minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(T.s('Delete', lang)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).delete('/api/social/${p['id']}');
      if (!mounted) return;
      setState(() => _posts.remove(p));
    } catch (e) {
      if (mounted) hmToast(context, apiErrorMessage(e));
    }
  }

  void _openComments(Map<String, dynamic> p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(
        postId: '${p['id']}',
        onCount: (c) {
          if (mounted) setState(() => p['commentCount'] = c);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final me = ref.watch(sessionStoreProvider).user;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(title: Text(T.s('Social Wall', lang))),
      body: RefreshIndicator(
        color: HMC.primary,
        onRefresh: _load,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) _load(more: true);
            return false;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              _composerBlock(lang, me?.name ?? ''),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator(color: HMC.primary)),
                )
              else if (_error != null && _posts.isEmpty)
                HmMessage(
                  icon: Icons.wifi_off_rounded,
                  text: _error!,
                  onRetry: _load,
                  retryLabel: T.s('Retry', lang),
                )
              else if (_posts.isEmpty)
                HmMessage(
                  icon: Icons.forum_outlined,
                  text: T.s('No posts yet', lang),
                  hint: T.s('Be the first to share a win with the team', lang),
                )
              else ...[
                for (final p in _posts)
                  _PostCard(
                    post: p,
                    lang: lang,
                    onLike: () => _toggleLike(p),
                    onComments: () => _openComments(p),
                    onDelete: p['canDelete'] == true ? () => _delete(p, lang) : null,
                  ),
                if (_loadingMore)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator(color: HMC.primary, strokeWidth: 2)),
                  ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _composerBlock(String lang, String myName) {
    return Stack(children: [
      Container(height: 70, color: HMC.ink),
      Container(
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Color(0x1A0A1628), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: _canPost
            ? Column(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  HmAvatar(name: myName, radius: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 1500,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: T.s('Share a win or update…', lang),
                        counterText: '',
                        fillColor: const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: HMC.emeraldDeep, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: HMC.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(96, 42),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: _posting ? null : () => _submitPost(lang),
                    child: _posting
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(T.s('Post', lang)),
                  ),
                ),
              ])
            : Row(children: [
                const Icon(Icons.lock_outline, color: HMC.amber),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _loading ? T.s('Loading…', lang) : T.s('Posting is turned off for you — you can still read and like posts.', lang),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ),
              ]),
      ),
    ]);
  }
}

class _PostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final String lang;
  final VoidCallback onLike;
  final VoidCallback onComments;
  final VoidCallback? onDelete;
  const _PostCard({
    required this.post,
    required this.lang,
    required this.onLike,
    required this.onComments,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final author = Map<String, dynamic>.from((post['author'] as Map?) ?? const {});
    final name = '${author['name'] ?? ''}';
    final dept = author['dept'] as String?;
    final liked = post['liked'] == true;
    final comments = asMaps(post['comments']);
    final commentCount = (post['commentCount'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x0F0A1628), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          HmAvatar(name: name, photo: author['photo'] as String?, radius: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w800, color: HMC.ink)),
                  if (dept != null)
                    TextSpan(text: ' · $dept', style: TextStyle(color: Colors.grey.shade600)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text('${post['at'] ?? ''}', style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5)),
            ]),
          ),
          if (onDelete != null)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.grey.shade500),
              onSelected: (_) => onDelete!(),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'delete', child: Text(T.s('Delete', lang))),
              ],
            ),
        ]),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text('${post['body'] ?? ''}', style: const TextStyle(fontSize: 15, height: 1.4, color: HMC.ink)),
        ),
        if (comments.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final c in comments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${c['user']}  ', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                      TextSpan(text: '${c['body']}', style: const TextStyle(fontSize: 12.5)),
                    ]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton.icon(
            onPressed: onLike,
            style: TextButton.styleFrom(foregroundColor: liked ? HMC.danger : HMC.ink),
            icon: Icon(liked ? Icons.favorite : Icons.favorite_border, size: 22),
            label: Text('${post['likes'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          TextButton.icon(
            onPressed: onComments,
            style: TextButton.styleFrom(foregroundColor: HMC.ink),
            icon: const Icon(Icons.chat_bubble_outline, size: 21),
            label: Text('$commentCount', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
      ]),
    );
  }
}

/// Full comment thread + composer (bottom sheet).
class _CommentsSheet extends ConsumerStatefulWidget {
  final String postId;
  final ValueChanged<int> onCount;
  const _CommentsSheet({required this.postId, required this.onCount});

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final _ctl = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final res = await ref.read(apiProvider).get<Map<String, dynamic>>('/api/social/${widget.postId}/comments');
      if (!mounted) return;
      setState(() {
        _rows = asMaps(res.data?['comments']);
        _error = null;
      });
      widget.onCount(_rows.length);
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _ctl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final res = await ref.read(apiProvider).post<Map<String, dynamic>>(
            '/api/social/${widget.postId}/comments',
            data: {'body': text},
          );
      final c = res.data?['comment'];
      if (!mounted) return;
      setState(() {
        if (c is Map) _rows.add(Map<String, dynamic>.from(c));
        _ctl.clear();
      });
      widget.onCount(_rows.length);
    } catch (e) {
      if (mounted) hmToast(context, apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(18, 12, 18, 12 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)),
          ),
        ),
        const SizedBox(height: 12),
        Text(T.s('Comments', lang), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: HMC.ink)),
        const SizedBox(height: 8),
        Flexible(
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(color: HMC.primary)),
                )
              : _error != null
                  ? Text(_error!, style: const TextStyle(color: HMC.danger))
                  : _rows.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: Text(T.s('No comments yet — say something nice!', lang),
                              style: TextStyle(color: Colors.grey.shade500)),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _rows.length,
                          itemBuilder: (_, i) {
                            final c = _rows[i];
                            final user = '${c['user'] ?? ''}';
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                HmAvatar(name: user, radius: 15),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(user, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                                      const SizedBox(height: 2),
                                      Text('${c['body'] ?? ''}', style: const TextStyle(fontSize: 13.5)),
                                      const SizedBox(height: 2),
                                      Text('${c['at'] ?? ''}', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
                                    ]),
                                  ),
                                ),
                              ]),
                            );
                          },
                        ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctl,
              maxLength: 400,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: T.s('Write a comment…', lang),
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: HMC.emeraldDeep, foregroundColor: Colors.white),
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.send_rounded),
          ),
        ]),
      ]),
    );
  }
}
