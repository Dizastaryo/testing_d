import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/time_format.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/design/design.dart';
import '../../core/models/comment.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';

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

  Future<void> addComment(String text) async {
    final resp = await _api.post(ApiEndpoints.postComments(postId), data: {'text': text});
    final data = resp.data;
    final commentData = data is Map && data.containsKey('data') ? data['data'] : data;
    final comment = Comment.fromJson(commentData as Map<String, dynamic>);
    state = state.copyWith(comments: [comment, ...state.comments]);
  }

  Future<void> addReply(String parentId, String text) async {
    final resp = await _api.post(ApiEndpoints.postComments(postId), data: {'text': text, 'parent_id': parentId});
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
    _api.post(ApiEndpoints.likeComment(commentId));
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

  void _submitComment() {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    if (_replyToId != null) {
      ref.read(_commentsProvider(widget.postId).notifier)
          .addReply(_replyToId!, text);
    } else {
      ref.read(_commentsProvider(widget.postId).notifier).addComment(text);
    }
    _commentCtrl.clear();
    setState(() {
      _replyToId = null;
      _replyToUsername = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final commentsState = ref.watch(_commentsProvider(widget.postId));
    final me = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Комментарии', style: SeeUTypography.subtitle),
        leading: IconButton(
          icon: Icon(PhosphorIcons.arrowLeft(), size: 22, color: c.ink),
          onPressed: () => Navigator.of(context).pop(),
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
                              style: TextStyle(
                                fontFamily: 'Fraunces',
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
          // Comment input
          SafeArea(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: c.surface2,
                border: Border(
                  top: BorderSide(
                    color: c.line,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: me?.avatarUrl != null
                        ? NetworkImage(me!.avatarUrl!)
                        : null,
                    backgroundColor:
                        c.ink3.withValues(alpha: 0.3),
                    child: me?.avatarUrl == null
                        ? Text(
                            me?.username.substring(0, 1).toUpperCase() ??
                                'U',
                            style: SeeUTypography.caption
                                .copyWith(color: Colors.white))
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      focusNode: _focusNode,
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submitComment(),
                      style: SeeUTypography.body,
                      decoration: InputDecoration(
                        hintText: _replyToUsername != null
                            ? 'Ответ @$_replyToUsername...'
                            : 'Добавить комментарий...',
                        hintStyle: SeeUTypography.body
                            .copyWith(color: c.ink3),
                        border: InputBorder.none,
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 0),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _commentCtrl,
                    builder: (_, value, __) {
                      return GestureDetector(
                        onTap: value.text.trim().isNotEmpty
                            ? _submitComment
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Text(
                            'Отправить',
                            style: SeeUTypography.subtitle.copyWith(
                              color: value.text.trim().isNotEmpty
                                  ? SeeUColors.accent
                                  : c.ink3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
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

  void _submitComment() {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    if (_replyToId != null) {
      ref
          .read(_commentsProvider(widget.postId).notifier)
          .addReply(_replyToId!, text);
    } else {
      ref
          .read(_commentsProvider(widget.postId).notifier)
          .addComment(text);
    }
    _commentCtrl.clear();
    setState(() {
      _replyToId = null;
      _replyToUsername = null;
    });
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
          ...commentsState.comments.map(
            (c) => _CommentTile(
              comment: c,
              isExpanded:
                  commentsState.expandedReplies.contains(c.id),
              onLike: () => ref
                  .read(_commentsProvider(widget.postId).notifier)
                  .likeComment(c.id),
              onReply: () {
                setState(() {
                  _replyToId = c.id;
                  _replyToUsername = c.author.username;
                });
                _commentCtrl.text = '@${c.author.username} ';
                _commentCtrl.selection = TextSelection.fromPosition(
                  TextPosition(offset: _commentCtrl.text.length),
                );
                _focusNode.requestFocus();
              },
              onToggleReplies: () => ref
                  .read(_commentsProvider(widget.postId).notifier)
                  .toggleReplies(c.id),
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
        SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.surface2,
              border: Border(
                top: BorderSide(
                  color: c.line,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: me?.avatarUrl != null
                      ? NetworkImage(me!.avatarUrl!)
                      : null,
                  backgroundColor:
                      c.ink3.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _commentCtrl,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submitComment(),
                    style: SeeUTypography.body,
                    decoration: InputDecoration(
                      hintText: _replyToUsername != null
                          ? 'Ответ @$_replyToUsername...'
                          : 'Добавить комментарий...',
                      hintStyle: SeeUTypography.body
                          .copyWith(color: c.ink3),
                      border: InputBorder.none,
                      filled: false,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _commentCtrl,
                  builder: (_, value, __) => GestureDetector(
                    onTap:
                        value.text.trim().isNotEmpty ? _submitComment : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Отправить',
                        style: SeeUTypography.subtitle.copyWith(
                          color: value.text.trim().isNotEmpty
                              ? SeeUColors.accent
                              : c.ink3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
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
  final VoidCallback onLike;
  final VoidCallback onReply;
  final VoidCallback onToggleReplies;

  const _CommentTile({
    super.key,
    required this.comment,
    required this.isExpanded,
    this.isHighlighted = false,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      // Deep-link highlight: тонкая accent-soft подложка + лёгкая рамка.
      decoration: isHighlighted
          ? BoxDecoration(
              color: c.accentSoft.withValues(alpha: 0.5),
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
                backgroundImage: comment.author.avatarUrl != null
                    ? NetworkImage(comment.author.avatarUrl!)
                    : null,
                backgroundColor:
                    c.ink3.withValues(alpha: 0.3),
                child: comment.author.avatarUrl == null
                    ? Text(
                        comment.author.username[0].toUpperCase(),
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
                          TextSpan(
                            text: comment.text,
                            style: SeeUTypography.body,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          formatRelativeTime(comment.createdAt),
                          style: SeeUTypography.micro,
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
                        GestureDetector(
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
                      GestureDetector(
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
                                      reply.author.avatarUrl != null
                                          ? NetworkImage(
                                              reply.author.avatarUrl!)
                                          : null,
                                  backgroundColor: c.ink3
                                      .withValues(alpha: 0.3),
                                  child: reply.author.avatarUrl == null
                                      ? Text(
                                          reply.author.username[0]
                                              .toUpperCase(),
                                          style: SeeUTypography.micro
                                              .copyWith(
                                                  color: Colors.white,
                                                  fontSize: 10))
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text:
                                              '${reply.author.username} ',
                                          style:
                                              SeeUTypography.caption.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: c.ink,
                                          ),
                                        ),
                                        TextSpan(
                                          text: reply.text,
                                          style: SeeUTypography.body,
                                        ),
                                      ],
                                    ),
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
              GestureDetector(
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
  }
}
