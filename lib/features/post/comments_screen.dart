import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/utils/time_format.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/design/design.dart';
import '../../core/models/comment.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../widgets/gif_picker_sheet.dart';

final _commentsProvider =
    StateNotifierProvider.family<CommentsNotifier, CommentsState, String>(
  (ref, postId) => CommentsNotifier(postId, ref.watch(apiClientProvider)),
);

class CommentsState {
  final List<Comment> comments;
  final bool isLoading;
  final Set<String> expandedReplies;

  const CommentsState({
    this.comments = const [],
    this.isLoading = false,
    this.expandedReplies = const {},
  });

  CommentsState copyWith({
    List<Comment>? comments,
    bool? isLoading,
    Set<String>? expandedReplies,
  }) =>
      CommentsState(
        comments: comments ?? this.comments,
        isLoading: isLoading ?? this.isLoading,
        expandedReplies: expandedReplies ?? this.expandedReplies,
      );
}

class CommentsNotifier extends StateNotifier<CommentsState> {
  final String postId;
  final ApiClient _api;

  CommentsNotifier(this.postId, this._api) : super(const CommentsState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final resp = await _api.get(ApiEndpoints.postComments(postId));
      final data = resp.data;
      final listData = data is Map && data.containsKey('data') ? data['data'] : data;
      final comments = (listData as List)
          .map((e) => Comment.fromJson(e as Map<String, dynamic>))
          .toList();
      state = CommentsState(comments: comments);
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> addComment(String text, {String gifUrl = ''}) async {
    final resp = await _api.post(ApiEndpoints.postComments(postId), data: {
      'text': text,
      if (gifUrl.isNotEmpty) 'gif_url': gifUrl,
    });
    final data = resp.data;
    final commentData = data is Map && data.containsKey('data') ? data['data'] : data;
    final comment = Comment.fromJson(commentData as Map<String, dynamic>);
    state = state.copyWith(comments: [comment, ...state.comments]);
  }

  Future<void> addReply(String parentId, String text, {String gifUrl = ''}) async {
    final resp = await _api.post(ApiEndpoints.postComments(postId), data: {
      'text': text,
      'parent_id': parentId,
      if (gifUrl.isNotEmpty) 'gif_url': gifUrl,
    });
    final data = resp.data;
    final replyData = data is Map && data.containsKey('data') ? data['data'] : data;
    final reply = Comment.fromJson(replyData as Map<String, dynamic>);
    final updated = state.comments.map((c) {
      if (c.id == parentId) {
        return c.copyWith(
          replies: [...c.replies, reply],
          repliesCount: c.repliesCount + 1,
        );
      }
      return c;
    }).toList();
    state = state.copyWith(comments: updated);
  }

  void toggleReplies(String commentId) {
    final set = Set<String>.from(state.expandedReplies);
    if (set.contains(commentId)) {
      set.remove(commentId);
    } else {
      set.add(commentId);
    }
    state = state.copyWith(expandedReplies: set);
  }

  Future<void> likeComment(String commentId) async {
    final updated = state.comments.map((c) {
      if (c.id == commentId) {
        return c.copyWith(
          isLiked: !c.isLiked,
          likesCount: c.isLiked
              ? (c.likesCount > 0 ? c.likesCount - 1 : 0)
              : c.likesCount + 1,
        );
      }
      // Search in replies too
      if (c.replies.any((r) => r.id == commentId)) {
        return c.copyWith(
          replies: c.replies.map((r) {
            if (r.id == commentId) {
              return r.copyWith(
                isLiked: !r.isLiked,
                likesCount: r.isLiked
                    ? (r.likesCount > 0 ? r.likesCount - 1 : 0)
                    : r.likesCount + 1,
              );
            }
            return r;
          }).toList(),
        );
      }
      return c;
    }).toList();
    state = state.copyWith(comments: updated);
    try {
      await _api.post(ApiEndpoints.likeComment(commentId));
    } catch (_) {
      // Rollback optimistic update on failure
      state = state.copyWith(comments: state.comments.map((c) {
        if (c.id == commentId) {
          return c.copyWith(
            isLiked: !c.isLiked,
            likesCount: c.isLiked
                ? (c.likesCount > 0 ? c.likesCount - 1 : 0)
                : c.likesCount + 1,
          );
        }
        if (c.replies.any((r) => r.id == commentId)) {
          return c.copyWith(
            replies: c.replies.map((r) {
              if (r.id == commentId) {
                return r.copyWith(
                  isLiked: !r.isLiked,
                  likesCount: r.isLiked
                      ? (r.likesCount > 0 ? r.likesCount - 1 : 0)
                      : r.likesCount + 1,
                );
              }
              return r;
            }).toList(),
          );
        }
        return c;
      }).toList());
    }
  }
}

class CommentsScreen extends ConsumerStatefulWidget {
  final String postId;
  /// Опциональный comment ID для подсветки + автоскролла (deep-link
  /// из notification). nil = обычное открытие.
  final String? focusedCommentId;

  const CommentsScreen({
    super.key,
    required this.postId,
    this.focusedCommentId,
  });

  @override
  ConsumerState<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends ConsumerState<CommentsScreen> {
  final _commentCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _focusedCommentKey = GlobalKey();
  String? _replyToId;
  String? _replyToUsername;
  bool _hasScrolledToFocused = false;

  @override
  void initState() {
    super.initState();
  }

  /// Auto-scroll к подсвеченному комменту после того как список отрисуется.
  /// Вызывается один раз (через _hasScrolledToFocused guard).
  void _maybeScrollToFocused() {
    if (_hasScrolledToFocused) return;
    if (widget.focusedCommentId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _focusedCommentKey.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        alignment: 0.25,
      );
      _hasScrolledToFocused = true;
    });
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    final replyId = _replyToId;
    _commentCtrl.clear();
    setState(() {
      _replyToId = null;
      _replyToUsername = null;
    });
    try {
      if (replyId != null) {
        await ref.read(_commentsProvider(widget.postId).notifier)
            .addReply(replyId, text);
      } else {
        await ref.read(_commentsProvider(widget.postId).notifier)
            .addComment(text);
      }
    } catch (e) {
      if (!mounted) return;
      _commentCtrl.text = text;
      showSeeUSnackBar(context, 'Не удалось отправить комментарий',
          tone: SeeUTone.danger);
    }
  }

  Future<void> _submitGif(String url) async {
    final replyId = _replyToId;
    setState(() {
      _replyToId = null;
      _replyToUsername = null;
    });
    try {
      if (replyId != null) {
        await ref.read(_commentsProvider(widget.postId).notifier)
            .addReply(replyId, '', gifUrl: url);
      } else {
        await ref.read(_commentsProvider(widget.postId).notifier)
            .addComment('', gifUrl: url);
      }
    } catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Не удалось отправить GIF',
          tone: SeeUTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final commentsState = ref.watch(_commentsProvider(widget.postId));
    final me = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(MediaQuery.of(context).padding.top + 56),
        child: SeeUGlassBar(
          blur: 28,
          kicker: 'Обсуждение',
          title: Text('Комментарии',
              style: SeeUTypography.displayS.copyWith(color: c.ink)),
          leading: IconButton(
            icon: Icon(PhosphorIcons.arrowLeft(), size: 22, color: c.ink),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: commentsState.isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: SeeUColors.accent))
                : commentsState.comments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '\u2026',
                              style: SeeUTypography.displayXL.copyWith(
                                fontSize: 56,
                                color: c.ink3,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Пока нет комментариев',
                              style: SeeUTypography.title,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Будьте первым!',
                              style: SeeUTypography.body
                                  .copyWith(color: c.ink2),
                            ),
                          ],
                        ),
                      )
                    : Builder(builder: (_) {
                        // Trigger scroll-to-focused после рендера, если есть.
                        _maybeScrollToFocused();
                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: commentsState.comments.length,
                          itemBuilder: (context, index) {
                            final comment = commentsState.comments[index];
                            final isExpanded = commentsState.expandedReplies
                                .contains(comment.id);
                            final isFocused =
                                widget.focusedCommentId != null &&
                                    comment.id == widget.focusedCommentId;
                            return _CommentTile(
                              key: isFocused ? _focusedCommentKey : null,
                              comment: comment,
                              isExpanded: isExpanded,
                              isHighlighted: isFocused,
                              hairline: index > 0,
                              onLike: () => ref
                                  .read(_commentsProvider(widget.postId)
                                      .notifier)
                                  .likeComment(comment.id),
                              onReply: () {
                                setState(() {
                                  _replyToId = comment.id;
                                  _replyToUsername = comment.author.username;
                                });
                                _commentCtrl.text =
                                    '@${comment.author.username} ';
                                _commentCtrl.selection =
                                    TextSelection.fromPosition(
                                  TextPosition(
                                      offset: _commentCtrl.text.length),
                                );
                                _focusNode.requestFocus();
                              },
                              onToggleReplies: () => ref
                                  .read(_commentsProvider(widget.postId)
                                      .notifier)
                                  .toggleReplies(comment.id),
                            );
                          },
                        );
                      }),
          ),
          // Reply indicator
          if (_replyToUsername != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(SeeURadii.pill),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(
                    'Ответ @$_replyToUsername',
                    style: SeeUTypography.caption.copyWith(
                      color: SeeUColors.accent,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() {
                      _replyToId = null;
                      _replyToUsername = null;
                    }),
                    child: Icon(PhosphorIcons.x(),
                        size: 16, color: SeeUColors.accent),
                  ),
                ],
              ),
            ),
          // Comment input — единый стеклянный бар.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _commentCtrl,
            builder: (_, value, __) => SeeUGlassInputBar(
              controller: _commentCtrl,
              focusNode: _focusNode,
              blur: 28,
              hintText: _replyToUsername != null
                  ? 'Ответ @$_replyToUsername...'
                  : 'Добавить комментарий...',
              canSend: value.text.trim().isNotEmpty,
              onSend: _submitComment,
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MeAvatar(me: me),
                  const SizedBox(width: 6),
                  _CommentGifButton(onSelected: _submitGif),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Аватар текущего пользователя для инпут-бара комментариев.
class _MeAvatar extends StatelessWidget {
  final dynamic me;
  const _MeAvatar({required this.me});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return CircleAvatar(
      radius: 18,
      backgroundImage: me?.avatarUrl != null && me!.avatarUrl!.isNotEmpty
          ? CachedNetworkImageProvider(me!.avatarUrl!,
              maxWidth: 108, maxHeight: 108)
          : null,
      backgroundColor: c.ink3.withValues(alpha: 0.3),
      child: (me?.avatarUrl == null || me!.avatarUrl!.isEmpty)
          ? Text(
              (me?.username.isNotEmpty ?? false)
                  ? me!.username[0].toUpperCase()
                  : 'U',
              style: SeeUTypography.caption.copyWith(color: Colors.white))
          : null,
    );
  }
}

/// Opens the shared GIF picker sheet — placed next to [_MeAvatar] in the
/// comment composer's `leading` slot on all three composer surfaces.
class _CommentGifButton extends StatelessWidget {
  final ValueChanged<String> onSelected;
  const _CommentGifButton({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: () => showGifPickerSheet(context, onSelected: onSelected),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: c.surface2,
          shape: BoxShape.circle,
          border: Border.all(color: c.line, width: 0.5),
        ),
        child: Icon(PhosphorIconsRegular.image, size: 17, color: c.ink3),
      ),
    );
  }
}

// Embeddable comments section for PostDetailScreen
class CommentsSection extends ConsumerStatefulWidget {
  final String postId;

  const CommentsSection({super.key, required this.postId});

  @override
  ConsumerState<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends ConsumerState<CommentsSection> {
  final _commentCtrl = TextEditingController();
  final _focusNode = FocusNode();
  String? _replyToId;
  String? _replyToUsername;

  @override
  void dispose() {
    _commentCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    final replyId = _replyToId;
    _commentCtrl.clear();
    setState(() {
      _replyToId = null;
      _replyToUsername = null;
    });
    try {
      if (replyId != null) {
        await ref
            .read(_commentsProvider(widget.postId).notifier)
            .addReply(replyId, text);
      } else {
        await ref
            .read(_commentsProvider(widget.postId).notifier)
            .addComment(text);
      }
    } catch (e) {
      if (!mounted) return;
      _commentCtrl.text = text;
      showSeeUSnackBar(context, 'Не удалось отправить комментарий',
          tone: SeeUTone.danger);
    }
  }

  Future<void> _submitGif(String url) async {
    final replyId = _replyToId;
    setState(() {
      _replyToId = null;
      _replyToUsername = null;
    });
    try {
      if (replyId != null) {
        await ref
            .read(_commentsProvider(widget.postId).notifier)
            .addReply(replyId, '', gifUrl: url);
      } else {
        await ref
            .read(_commentsProvider(widget.postId).notifier)
            .addComment('', gifUrl: url);
      }
    } catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Не удалось отправить GIF',
          tone: SeeUTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final commentsState = ref.watch(_commentsProvider(widget.postId));
    final me = ref.watch(authProvider).user;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (commentsState.isLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(color: SeeUColors.accent),
            ),
          )
        else
          ...commentsState.comments.indexed.map(
            ((int, Comment) e) => _CommentTile(
              comment: e.$2,
              isExpanded:
                  commentsState.expandedReplies.contains(e.$2.id),
              hairline: e.$1 > 0,
              onLike: () => ref
                  .read(_commentsProvider(widget.postId).notifier)
                  .likeComment(e.$2.id),
              onReply: () {
                setState(() {
                  _replyToId = e.$2.id;
                  _replyToUsername = e.$2.author.username;
                });
                _commentCtrl.text = '@${e.$2.author.username} ';
                _commentCtrl.selection = TextSelection.fromPosition(
                  TextPosition(offset: _commentCtrl.text.length),
                );
                _focusNode.requestFocus();
              },
              onToggleReplies: () => ref
                  .read(_commentsProvider(widget.postId).notifier)
                  .toggleReplies(e.$2.id),
            ),
          ),
        if (_replyToUsername != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(SeeURadii.pill),
            ),
            child: Row(
              children: [
                Text(
                  'Ответ @$_replyToUsername',
                  style: SeeUTypography.caption.copyWith(color: SeeUColors.accent),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() {
                    _replyToId = null;
                    _replyToUsername = null;
                  }),
                  child: Icon(PhosphorIcons.x(), size: 16, color: SeeUColors.accent),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _commentCtrl,
          builder: (_, value, __) => SeeUGlassInputBar(
            controller: _commentCtrl,
            focusNode: _focusNode,
            blur: 28,
            hintText: _replyToUsername != null
                ? 'Ответ @$_replyToUsername...'
                : 'Добавить комментарий...',
            canSend: value.text.trim().isNotEmpty,
            onSend: _submitComment,
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MeAvatar(me: me),
                const SizedBox(width: 6),
                _CommentGifButton(onSelected: _submitGif),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Comment comment;
  final bool isExpanded;
  /// Подсветка для deep-link из notification — accent-soft фон + ramка.
  final bool isHighlighted;
  /// Hairline-разделитель сверху (между top-level комментами).
  final bool hairline;
  final VoidCallback onLike;
  final VoidCallback onReply;
  final VoidCallback onToggleReplies;

  const _CommentTile({
    super.key,
    required this.comment,
    required this.isExpanded,
    this.isHighlighted = false,
    this.hairline = false,
    required this.onLike,
    required this.onReply,
    required this.onToggleReplies,
  });

  String _likesWord(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'лайк';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'лайка';
    return 'лайков';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final tile = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      // Deep-link highlight: accent-soft подложка + лёгкая рамка.
      decoration: isHighlighted
          ? BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(SeeURadii.small),
              border: Border.all(
                color: SeeUColors.accent.withValues(alpha: 0.4),
                width: 1,
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 17,
                backgroundImage: comment.author.avatarUrl != null &&
                        comment.author.avatarUrl!.isNotEmpty
                    ? CachedNetworkImageProvider(comment.author.avatarUrl!,
                        maxWidth: 108, maxHeight: 108)
                    : null,
                backgroundColor:
                    c.ink3.withValues(alpha: 0.3),
                child: (comment.author.avatarUrl == null ||
                        comment.author.avatarUrl!.isEmpty)
                    ? Text(
                        comment.author.username.isNotEmpty
                            ? comment.author.username[0].toUpperCase()
                            : '?',
                        style: SeeUTypography.micro
                            .copyWith(color: Colors.white))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${comment.author.username} ',
                            style: SeeUTypography.caption.copyWith(
                              fontWeight: FontWeight.w700,
                              color: c.ink,
                            ),
                          ),
                          if (comment.text.isNotEmpty)
                            TextSpan(
                              text: comment.text,
                              style: SeeUTypography.body,
                            ),
                        ],
                      ),
                    ),
                    if (comment.gifUrl.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(SeeURadii.medium),
                        child: CachedNetworkImage(
                          imageUrl: comment.gifUrl,
                          width: 160,
                          height: 160,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            width: 160,
                            height: 160,
                            color: c.surface2,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        // Kicker-байлайн времени — зеркалит editorial-байлайн
                        // post_card («@handle · время»).
                        Text(
                          '· ${formatRelativeTime(comment.createdAt).toUpperCase()}',
                          style: SeeUTypography.kicker.copyWith(color: c.ink3),
                        ),
                        const SizedBox(width: 16),
                        if (comment.likesCount > 0)
                          Text(
                            '${comment.likesCount} ${_likesWord(comment.likesCount)}',
                            style: SeeUTypography.micro.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        const SizedBox(width: 16),
                        Tappable.faded(
                          onTap: onReply,
                          child: Text(
                            'Ответить',
                            style: SeeUTypography.micro.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Replies toggle
                    if (comment.repliesCount > 0) ...[
                      const SizedBox(height: 8),
                      Tappable.faded(
                        onTap: onToggleReplies,
                        child: Row(
                          children: [
                            Text(
                              isExpanded
                                  ? 'Скрыть ответы'
                                  : 'Показать ответы (${comment.repliesCount})',
                              style: SeeUTypography.caption.copyWith(
                                color: SeeUColors.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              isExpanded
                                  ? PhosphorIcons.caretUp()
                                  : PhosphorIcons.caretDown(),
                              size: 14,
                              color: SeeUColors.accent,
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Nested replies with vertical line
                    if (isExpanded && comment.replies.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...comment.replies.map(
                        (reply) => Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Vertical indent line
                                Container(
                                  width: 2,
                                  margin: const EdgeInsets.only(left: 17),
                                  decoration: BoxDecoration(
                                    color: c.line,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                CircleAvatar(
                                  radius: 14,
                                  backgroundImage:
                                      reply.author.avatarUrl != null &&
                                              reply.author.avatarUrl!.isNotEmpty
                                          ? CachedNetworkImageProvider(
                                              reply.author.avatarUrl!,
                                              maxWidth: 108, maxHeight: 108)
                                          : null,
                                  backgroundColor: c.ink3
                                      .withValues(alpha: 0.3),
                                  child: (reply.author.avatarUrl == null ||
                                          reply.author.avatarUrl!.isEmpty)
                                      ? Text(
                                          reply.author.username.isNotEmpty
                                              ? reply.author.username[0]
                                                  .toUpperCase()
                                              : '?',
                                          style: SeeUTypography.micro
                                              .copyWith(
                                                  color: Colors.white,
                                                  fontSize: 10))
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      RichText(
                                        text: TextSpan(
                                          children: [
                                            TextSpan(
                                              text:
                                                  '${reply.author.username} ',
                                              style: SeeUTypography.caption
                                                  .copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: c.ink,
                                              ),
                                            ),
                                            if (reply.text.isNotEmpty)
                                              TextSpan(
                                                text: reply.text,
                                                style: SeeUTypography.body,
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (reply.gifUrl.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 6),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                                SeeURadii.medium),
                                            child: CachedNetworkImage(
                                              imageUrl: reply.gifUrl,
                                              width: 120,
                                              height: 120,
                                              fit: BoxFit.cover,
                                              placeholder: (_, __) => Container(
                                                width: 120,
                                                height: 120,
                                                color: c.surface2,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Tappable.scaled(
                onTap: onLike,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    comment.isLiked
                        ? PhosphorIcons.heart(PhosphorIconsStyle.fill)
                        : PhosphorIcons.heart(),
                    size: 16,
                    color: comment.isLiked
                        ? SeeUColors.like
                        : SeeUColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (!hairline) return tile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Divider(height: 0.5, thickness: 0.5, color: c.line),
        ),
        tile,
      ],
    );
  }
}

/// Instagram-style comments bottom sheet: slides up over the current screen
/// (e.g. the full-screen photo viewer), draggable + scrollable list with a
/// pinned input. Reuses the same provider/tiles as [CommentsScreen].
Future<void> showCommentsSheet(BuildContext context, String postId) {
  return showSeeUBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Flexible: showSeeUBottomSheet кладёт builder-результат в Column —
    // DraggableScrollableSheet нужны ограниченные constraints по высоте.
    builder: (_) => Flexible(
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => _CommentsSheetBody(
            postId: postId, scrollController: scrollController),
      ),
    ),
  );
}

class _CommentsSheetBody extends ConsumerStatefulWidget {
  final String postId;
  final ScrollController scrollController;
  const _CommentsSheetBody({
    required this.postId,
    required this.scrollController,
  });

  @override
  ConsumerState<_CommentsSheetBody> createState() => _CommentsSheetBodyState();
}

class _CommentsSheetBodyState extends ConsumerState<_CommentsSheetBody> {
  final _commentCtrl = TextEditingController();
  final _focusNode = FocusNode();
  String? _replyToId;
  String? _replyToUsername;

  @override
  void dispose() {
    _commentCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    final replyId = _replyToId;
    final notifier = ref.read(_commentsProvider(widget.postId).notifier);
    _commentCtrl.clear();
    setState(() {
      _replyToId = null;
      _replyToUsername = null;
    });
    try {
      if (replyId != null) {
        await notifier.addReply(replyId, text);
      } else {
        await notifier.addComment(text);
      }
    } catch (e) {
      if (!mounted) return;
      _commentCtrl.text = text;
      showSeeUSnackBar(context, 'Не удалось отправить комментарий',
          tone: SeeUTone.danger);
    }
  }

  Future<void> _submitGif(String url) async {
    final replyId = _replyToId;
    final notifier = ref.read(_commentsProvider(widget.postId).notifier);
    setState(() {
      _replyToId = null;
      _replyToUsername = null;
    });
    try {
      if (replyId != null) {
        await notifier.addReply(replyId, '', gifUrl: url);
      } else {
        await notifier.addComment('', gifUrl: url);
      }
    } catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Не удалось отправить GIF',
          tone: SeeUTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final state = ref.watch(_commentsProvider(widget.postId));
    final me = ref.watch(authProvider).user;

    // Оформление контейнера (фон, скругление, drag handle) даёт
    // showSeeUBottomSheet — здесь только контент.
    return Column(
        children: [
          // Editorial-заголовок шита: kicker + серифный display.
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Column(
              children: [
                Text('ОБСУЖДЕНИЕ',
                    style: SeeUTypography.kicker.copyWith(color: c.ink3)),
                const SizedBox(height: 2),
                Text('Комментарии',
                    style: SeeUTypography.displayS.copyWith(color: c.ink)),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          // list
          Expanded(
            child: state.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: SeeUColors.accent))
                : state.comments.isEmpty
                    ? ListView(
                        controller: widget.scrollController,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(40),
                            child: Center(
                              child: Text(
                                'Пока нет комментариев.\nБудьте первым!',
                                textAlign: TextAlign.center,
                                style: SeeUTypography.body
                                    .copyWith(color: c.ink3),
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: state.comments.length,
                        itemBuilder: (_, i) {
                          final cm = state.comments[i];
                          return _CommentTile(
                            comment: cm,
                            isExpanded:
                                state.expandedReplies.contains(cm.id),
                            hairline: i > 0,
                            onLike: () => ref
                                .read(_commentsProvider(widget.postId).notifier)
                                .likeComment(cm.id),
                            onReply: () {
                              setState(() {
                                _replyToId = cm.id;
                                _replyToUsername = cm.author.username;
                              });
                              _commentCtrl.text = '@${cm.author.username} ';
                              _commentCtrl.selection =
                                  TextSelection.fromPosition(
                                TextPosition(offset: _commentCtrl.text.length),
                              );
                              _focusNode.requestFocus();
                            },
                            onToggleReplies: () => ref
                                .read(_commentsProvider(widget.postId).notifier)
                                .toggleReplies(cm.id),
                          );
                        },
                      ),
          ),
          if (_replyToUsername != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(SeeURadii.pill),
              ),
              child: Row(
                children: [
                  Text('Ответ @$_replyToUsername',
                      style: SeeUTypography.caption
                          .copyWith(color: SeeUColors.accent)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() {
                      _replyToId = null;
                      _replyToUsername = null;
                    }),
                    child: Icon(PhosphorIcons.x(),
                        size: 16, color: SeeUColors.accent),
                  ),
                ],
              ),
            ),
          // input (rises above keyboard) — единый стеклянный бар.
          Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _commentCtrl,
              builder: (_, value, __) => SeeUGlassInputBar(
                controller: _commentCtrl,
                focusNode: _focusNode,
                blur: 28,
                hintText: _replyToUsername != null
                    ? 'Ответ @$_replyToUsername...'
                    : 'Добавить комментарий...',
                canSend: value.text.trim().isNotEmpty,
                onSend: _submit,
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MeAvatar(me: me),
                    const SizedBox(width: 6),
                    _CommentGifButton(onSelected: _submitGif),
                  ],
                ),
              ),
            ),
          ),
        ],
    );
  }
}
