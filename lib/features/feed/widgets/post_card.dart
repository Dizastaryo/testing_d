import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/design/design.dart';
import '../../../core/models/post.dart';
import '../../../core/providers/blocks_provider.dart';
import '../../../core/providers/feed_provider.dart';
import '../../../core/providers/story_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/analytics/interest_tracker.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../widgets/report_sheet.dart';
import '../../../widgets/share_sheet.dart';
import 'post_card_widgets.dart';

class PostCard extends ConsumerStatefulWidget {
  final Post post;
  /// true когда карточка — главный контент отдельного экрана (PostDetail):
  /// после «скрыть»/«не интересно»/блокировки автора экран закрывается,
  /// вместо того чтобы оставить пользователя смотреть на «скрытый» пост.
  final bool isDetail;

  const PostCard({super.key, required this.post, this.isDetail = false});

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard>
    with TickerProviderStateMixin {
  /// Локальная копия поста — источник правды для ЭТОЙ карточки. PostCard
  /// живёт не только в ленте (детали поста, лента профиля, волны в
  /// «Интересном»), поэтому нельзя ни читать состояние из feedProvider
  /// (пост может отсутствовать там — раньше firstWhere кидал StateError),
  /// ни полагаться, что владелец списка перерисует карточку после мутации.
  /// Оптимистичные лайк/сохранение применяются сюда, а затем best-effort
  /// синхронизируются в провайдеры лент через applyPostUpdate.
  late Post _post;

  late AnimationController _heartAnimController;
  late Animation<double> _heartScaleAnim;
  late Animation<double> _heartOpacityAnim;
  bool _showHeart = false;
  bool _pollVoting = false;
  // Burst — particle-эффект поверх большой anim'ы. Два GlobalKey'а потому что
  // wave-layout и normal-layout рендерятся в разных Stack'ах, на экране в
  // момент времени только один — пуляем burst в оба (другой просто null'ится).
  final GlobalKey<SeeUHeartBurstState> _burstKeyWave =
      GlobalKey<SeeUHeartBurstState>();
  final GlobalKey<SeeUHeartBurstState> _burstKeyNormal =
      GlobalKey<SeeUHeartBurstState>();
  final PageController _pageController = PageController();

  // L09: Track current page for counter badge
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    // L09: Listen to page changes for counter badge
    _pageController.addListener(() {
      final page = _pageController.page?.round() ?? 0;
      if (page != _currentPage) {
        setState(() => _currentPage = page);
      }
    });
    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _heartScaleAnim = TweenSequence([
      TweenSequenceItem(
          tween: Tween<double>(begin: 0, end: 1.2)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 40),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.2, end: 1.0)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 20),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 1.0),
          weight: 40),
    ]).animate(_heartAnimController);
    _heartOpacityAnim = TweenSequence([
      TweenSequenceItem(
          tween: Tween<double>(begin: 0, end: 1.0),
          weight: 20),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 1.0),
          weight: 40),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 0.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 40),
    ]).animate(_heartAnimController);
    _heartAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) setState(() => _showHeart = false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Владелец списка (лента/профиль) прислал свежую версию — принимаем её.
    if (!identical(oldWidget.post, widget.post)) {
      _post = widget.post;
    }
  }

  @override
  void dispose() {
    _heartAnimController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// Применить мутацию к локальной копии + best-effort разослать её в
  /// провайдеры лент, где этот пост может лежать (лента, интересное) —
  /// чтобы вернувшись назад пользователь увидел то же состояние.
  void _applyPost(Post updated) {
    if (mounted) setState(() => _post = updated);
    ref.read(feedProvider.notifier).applyPostUpdate(updated);
    ref.read(exploreProvider.notifier).applyPostUpdate(updated);
  }

  /// §A4: голос за вариант опроса волны. Оптимистично инкрементим локально,
  /// затем подменяем свежим состоянием с сервера. Один голос — повторный тап
  /// уже заблокирован (pollVoted). Ошибка — откат к widget.post-состоянию.
  Future<void> _votePoll(PostPollOption opt) async {
    if (_pollVoting || _post.pollVoted) return;
    setState(() => _pollVoting = true);
    HapticFeedback.selectionClick();

    // Оптимистичный слепок.
    final optimistic = _post.copyWith(
      pollVotedOption: opt.id,
      pollTotalVotes: _post.pollTotalVotes + 1,
      pollOptions: [
        for (final o in _post.pollOptions)
          if (o.id == opt.id)
            PostPollOption(id: o.id, label: o.label, voteCount: o.voteCount + 1)
          else
            o,
      ],
    );
    _applyPost(optimistic);

    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.post(
        ApiEndpoints.postPollVote(_post.id),
        data: {'option_id': opt.id},
      );
      final raw = resp.data;
      final data = (raw is Map && raw['data'] is Map) ? raw['data'] : raw;
      if (data is Map) {
        _applyPost(Post.fromJson(data.cast<String, dynamic>()));
      }
    } catch (_) {
      // Откат: возвращаем версию из widget.post (до голоса).
      _applyPost(widget.post);
      if (mounted) {
        showSeeUSnackBar(context, 'Не удалось проголосовать',
            tone: SeeUTone.danger);
      }
    } finally {
      if (mounted) setState(() => _pollVoting = false);
    }
  }

  void _onDoubleTap() {
    if (!_post.isLiked) {
      _likePost();
    }
    HapticFeedback.mediumImpact();
    setState(() => _showHeart = true);
    _heartAnimController.forward(from: 0);
    // Particle-burst — стреляем в оба ключа, ответит только тот что mounted.
    _burstKeyWave.currentState?.burst();
    _burstKeyNormal.currentState?.burst();
  }

  Future<void> _likePost() async {
    HapticFeedback.lightImpact();
    final original = _post;
    final newLiked = !original.isLiked;
    _applyPost(original.copyWith(
      isLiked: newLiked,
      likesCount: newLiked
          ? original.likesCount + 1
          : (original.likesCount > 0 ? original.likesCount - 1 : 0),
    ));
    try {
      final api = ref.read(apiClientProvider);
      if (newLiked) {
        await api.post(ApiEndpoints.likePost(original.id));
      } else {
        await api.delete(ApiEndpoints.likePost(original.id));
      }
    } catch (_) {
      // Сервер отклонил — откатываем оптимистичное обновление.
      _applyPost(original);
    }
  }

  Future<void> _savePost() async {
    HapticFeedback.lightImpact();
    final original = _post;
    final newSaved = !original.isSaved;
    _applyPost(original.copyWith(isSaved: newSaved));
    try {
      final api = ref.read(apiClientProvider);
      if (newSaved) {
        await api.post(ApiEndpoints.savePost(original.id));
      } else {
        await api.delete(ApiEndpoints.savePost(original.id));
      }
    } catch (_) {
      _applyPost(original);
    }
  }

  Future<void> _confirmBlockAuthor() async {
    final author = _post.author;
    final confirmed = await showSeeUConfirm(
      context,
      title: 'Заблокировать @${author.username}?',
      message: 'Вы перестанете видеть посты и истории этого пользователя, '
          'а он — ваши. Подписки удалятся в обе стороны.',
      confirmLabel: 'Заблокировать',
      destructive: true,
      icon: PhosphorIcons.prohibit(),
    );
    if (!confirmed || !mounted) return;
    final err = await ref.read(blocksProvider.notifier).block(author.username);
    if (!mounted) return;
    if (err != null) {
      showSeeUSnackBar(context, 'Не удалось заблокировать: $err',
          tone: SeeUTone.danger);
      return;
    }
    showSeeUSnackBar(context, '@${author.username} заблокирован',
        icon: PhosphorIcons.prohibit());
    // Блок скрывает ВЕСЬ контент автора, а не только этот пост: чистим все
    // его посты из лент и перезагружаем ряд историй (его сторис пропадают).
    ref.read(feedProvider.notifier).removeAuthor(author.username);
    ref.read(storyProvider.notifier).loadStories();
    if (widget.isDetail) Navigator.of(context).maybePop();
  }

  void _onShareTap() {
    // Для CHAT-5 «Поделиться в сторис» прокидываем first media + author.
    // Если у поста нет media (чисто текстовый wave) — params null и tile
    // в sheet'е не появится.
    final firstMedia = _post.media.isNotEmpty ? _post.media.first : null;
    showShareSheet(
      context: context,
      url: postShareUrl(_post.id),
      title: 'Поделиться постом',
      subtitle: _post.author.username.isNotEmpty
          ? '@${_post.author.username}'
          : null,
      forwardablePostId: _post.id,
      sharedPostMediaUrl: firstMedia?.url,
      sharedPostMediaType: firstMedia?.type.name,
      sharedPostAuthor: _post.author.username,
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;

    if (post.isWave) {
      return _buildWaveCard(context, post);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, post),
          const SizedBox(height: 10),
          _buildMedia(context, post),
          const SizedBox(height: 12),
          _buildActions(context, post),
          _buildLikesRow(context, post),
          _buildCaption(context, post),
          _buildCommentsPreview(context, post),
          // Hairline-разделитель между подписью/комментами и меткой времени.
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Divider(
                height: 0.5, thickness: 0.5, color: context.seeuColors.line),
          ),
          _buildTimeRow(context, post),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildWaveCard(BuildContext context, Post post) {
    final c = context.seeuColors;
    // Акцентная планка волны: цвет автор выбирает при создании
    // (waveColorValue), по умолчанию — фирменный коралл.
    final accent = post.waveColorValue != null
        ? Color(post.waveColorValue!)
        : SeeUColors.accent;
    final text = (post.caption ?? '').trim();
    // Волна текст-первая. Если к ней приложено фото — показываем его узкой
    // центрированной карточкой под текстом (видео к волнам не прикладывают).
    final photo = post.media.isNotEmpty &&
            post.media.first.type != MediaType.video &&
            post.media.first.url.isNotEmpty
        ? post.media.first
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, post, isWave: true),
            const SizedBox(height: 10),
            GestureDetector(
              onDoubleTap: _onDoubleTap,
              behavior: HitTestBehavior.opaque,
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Тонкая планка + серифный курсив — весь мотив волны.
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: 2.5,
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                text.isEmpty ? '…' : text,
                                style: TextStyle(
                                  fontFamily: 'Times New Roman',
                                  fontFamilyFallback: const [
                                    'Playfair Display',
                                    'Georgia',
                                    'serif',
                                  ],
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w400,
                                  fontSize: 16,
                                  height: 1.55,
                                  color: c.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (photo != null) ...[
                        const SizedBox(height: 14),
                        Center(
                          child: FractionallySizedBox(
                            widthFactor: 0.72,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: AspectRatio(
                                aspectRatio: 4 / 3,
                                child: CachedNetworkImage(
                                  imageUrl: photo.url,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) =>
                                      Container(color: c.surface2),
                                  errorWidget: (_, __, ___) =>
                                      Container(color: c.surface2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Двойной тап → лайк: пламя в акцентном цвете волны.
                  if (_showHeart)
                    Positioned.fill(
                      child: Center(
                        child: AnimatedBuilder(
                          animation: _heartAnimController,
                          builder: (_, __) => Opacity(
                            opacity: _heartOpacityAnim.value,
                            child: Transform.scale(
                              scale: _heartScaleAnim.value,
                              child: Icon(
                                PhosphorIcons.heart(PhosphorIconsStyle.fill),
                                color: accent,
                                size: 72,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: Center(
                      child: SeeUHeartBurst(
                        key: _burstKeyWave,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (post.hasPoll) ...[
              const SizedBox(height: 14),
              _buildWavePoll(context, post, accent),
            ],
            const SizedBox(height: 14),
            _buildWaveActions(context, post),
            _buildWaveReplies(context, post),
            const SizedBox(height: 20),
          ],
      ),
    );
  }

  /// §A4: блок опроса под текстом волны. До голоса — тапабельные варианты; после
  /// — те же строки с progress-заливкой, процентами и отметкой выбранного.
  Widget _buildWavePoll(BuildContext context, Post post, Color accent) {
    final c = context.seeuColors;
    final voted = post.pollVotedOption;
    final total = post.pollTotalVotes;
    final revealed = post.pollVoted;
    return Padding(
      // Совмещаем с текстом волны (планка 2.5 + отступ 14).
      padding: const EdgeInsets.only(left: 16.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final opt in post.pollOptions) ...[
            _pollOptionTile(
              c: c,
              accent: accent,
              label: opt.label,
              votes: opt.voteCount,
              total: total,
              selected: voted == opt.id,
              revealed: revealed,
              onTap: (revealed || _pollVoting) ? null : () => _votePoll(opt),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            revealed
                ? '$total ${_votesWord(total)}'
                : 'Нажми, чтобы проголосовать',
            style: SeeUTypography.micro.copyWith(color: c.ink3),
          ),
        ],
      ),
    );
  }

  Widget _pollOptionTile({
    required SeeUThemeColors c,
    required Color accent,
    required String label,
    required int votes,
    required int total,
    required bool selected,
    required bool revealed,
    required VoidCallback? onTap,
  }) {
    final pct = total > 0 ? (votes / total).clamp(0.0, 1.0) : 0.0;
    return Tappable(
      onTap: onTap,
      enableHaptic: false, // свой selectionClick в _votePoll
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : c.line,
            width: selected ? 1.4 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Заливка результата после голоса.
            if (revealed)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: pct,
                    child: ColoredBox(
                      color: accent.withValues(alpha: selected ? 0.20 : 0.10),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  if (selected) ...[
                    Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                        size: 15, color: accent),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SeeUTypography.caption.copyWith(
                        color: c.ink,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (revealed) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${(pct * 100).round()}%',
                      style: SeeUTypography.caption.copyWith(
                        color: selected ? accent : c.ink3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Русское склонение «голос / голоса / голосов».
  String _votesWord(int n) {
    final m10 = n % 10;
    final m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'голос';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'голоса';
    return 'голосов';
  }

  // U14: Shared action row builder used by both wave and normal posts (DRY)
  Widget _buildActionsRow(BuildContext context, Post post) {
    final c = context.seeuColors;
    return Row(
      children: [
        Semantics(
          button: true,
          label: post.isLiked ? 'Убрать лайк' : 'Нравится',
          child: GestureDetector(
            onTap: _likePost,
            child: PostActionButtonRaw(
              icon: PhosphorIcon(
                post.isLiked
                    ? PhosphorIcons.heart(PhosphorIconsStyle.fill)
                    : PhosphorIcons.heart(),
                color:
                    post.isLiked ? SeeUColors.like : c.ink,
                size: 22,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PostActionButton(
          icon: PhosphorIcon(PhosphorIcons.chatCircle()),
          onTap: () => context.push('/post/${post.id}/comments'),
        ),
        const SizedBox(width: 8),
        PostActionButton(
          icon: PhosphorIcon(PhosphorIcons.shareFat()),
          onTap: _onShareTap,
        ),
        const Spacer(),
        PostActionButton(
          icon: PhosphorIcon(post.isSaved
              ? PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.fill)
              : PhosphorIcons.bookmarkSimple()),
          onTap: _savePost,
        ),
      ],
    );
  }

  /// Строка действий волны: у каждого действия число рядом (лайк · ответы ·
  /// репост), справа — «поделиться». Текст-первый формат волны требует
  /// счётчики прямо в строке, а не отдельным «Нравится …» ниже.
  Widget _buildWaveActions(BuildContext context, Post post) {
    final c = context.seeuColors;

    Widget metric({
      required Widget icon,
      String? count,
      required VoidCallback onTap,
    }) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(right: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              if (count != null && count != '0') ...[
                const SizedBox(width: 6),
                Text(
                  count,
                  style: SeeUTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        metric(
          icon: PhosphorIcon(
            post.isLiked
                ? PhosphorIcons.heart(PhosphorIconsStyle.fill)
                : PhosphorIcons.heart(),
            color: post.isLiked ? SeeUColors.like : c.ink,
            size: 22,
          ),
          count: post.likesCount > 0 ? formatCount(post.likesCount) : null,
          onTap: _likePost,
        ),
        metric(
          icon: PhosphorIcon(PhosphorIcons.chatCircle(),
              color: c.ink, size: 21),
          count: post.commentsCount > 0
              ? formatCount(post.commentsCount)
              : null,
          onTap: () => context.push('/post/${post.id}/comments'),
        ),
        metric(
          icon: PhosphorIcon(PhosphorIcons.repeat(),
              color: c.ink, size: 21),
          onTap: _onShareTap,
        ),
        const Spacer(),
        GestureDetector(
          onTap: _onShareTap,
          behavior: HitTestBehavior.opaque,
          child: PhosphorIcon(PhosphorIcons.shareFat(),
              color: c.ink, size: 21),
        ),
      ],
    );
  }

  /// «Ответили …» — тихая строка под волной. Имён ответивших сервер не отдаёт,
  /// поэтому показываем честное число ответов.
  Widget _buildWaveReplies(BuildContext context, Post post) {
    if (post.commentsCount <= 0) return const SizedBox.shrink();
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GestureDetector(
        onTap: () => context.push('/post/${post.id}/comments'),
        behavior: HitTestBehavior.opaque,
        child: Text(
          '${formatCount(post.commentsCount)} ${pluralRu(post.commentsCount, 'ответ', 'ответа', 'ответов')}',
          style: SeeUTypography.caption.copyWith(color: c.ink3),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Post post, {bool isWave = false}) {
    final c = context.seeuColors;
    // FEED-7: инъектированный из «Интересного» пост помечается бейджем —
    // иначе рекомендация неотличима от поста подписок и вводит в заблуждение.
    final isRecommended = ref.watch(
        feedProvider.select((s) => s.recommendedIds.contains(post.id)));
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.push('/profile/${post.author.username}'),
            child: Hero(
              tag: 'avatar-${post.author.username}',
              child: CircleAvatar(
                radius: 18,
                backgroundImage: post.author.avatarUrl != null &&
                        post.author.avatarUrl!.isNotEmpty
                    ? CachedNetworkImageProvider(
                        post.author.avatarUrl!,
                        // Avatar paints at 36 logical px — decode to that size
                        // instead of the full-res source.
                        maxWidth:
                            (36 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                        maxHeight:
                            (36 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                      )
                    : null,
                backgroundColor: c.surface2,
                child: (post.author.avatarUrl == null ||
                        post.author.avatarUrl!.isEmpty)
                    ? Icon(PhosphorIcons.user(),
                        color: c.ink3, size: 18)
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => context.push('/profile/${post.author.username}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          post.author.username,
                          style: SeeUTypography.subtitle
                              .copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (post.author.isVerified) ...[
                        const SizedBox(width: 4),
                        Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.fill),
                            color: SeeUColors.accent, size: 16),
                      ],
                      // «Волна» помечается коралловым kicker-суффиксом прямо в
                      // строке автора — читается как жанр поста, а не как имя.
                      if (isWave) ...[
                        const SizedBox(width: 6),
                        Text(
                          '· ВОЛНА',
                          style: SeeUTypography.kicker.copyWith(
                            color: SeeUColors.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (isRecommended) ...[
                        const SizedBox(width: 6),
                        Text(
                          '· РЕКОМЕНДУЕМ',
                          style: SeeUTypography.kicker.copyWith(
                            color: c.ink3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Editorial byline: mono kicker «@handle · время (· локация)»,
                  // зеркалит eyebrow wave-карточки. У волны локацию не
                  // показываем — она текст-первая, место не несёт смысла.
                  Text(
                    [
                      '@${post.author.username}',
                      formatRelativeTime(post.createdAt),
                      if (!isWave &&
                          post.location != null &&
                          post.location!.isNotEmpty)
                        post.location!,
                    ].join(' · ').toUpperCase(),
                    style: SeeUTypography.kicker.copyWith(color: c.ink3),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  // Sound-bridge (§03): «🎵 название · автор» коралловым под
                  // байлайном, когда к посту прикреплён трек.
                  if (!isWave && post.audioTrackTitle.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(PhosphorIconsFill.musicNotesSimple,
                            size: 13, color: SeeUColors.accent),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            post.audioTrackArtist.isNotEmpty
                                ? '${post.audioTrackTitle} · ${post.audioTrackArtist}'
                                : post.audioTrackTitle,
                            style: SeeUTypography.caption.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: SeeUColors.accent,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _showPostOptions(context, post),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(PhosphorIcons.dotsThreeOutline(),
                  size: 20, color: c.ink2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedia(BuildContext context, Post post) {
    final c = context.seeuColors;
    if (post.media.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SeeURadii.card),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              SeeUColors.accentSoft,
              SeeUColors.amber.withValues(alpha: 0.25),
            ],
          ),
        ),
        child: Center(
          child: Icon(PhosphorIcons.imageSquare(),
              color: c.ink3, size: 48),
        ),
      );
    }
    // M2: показываем пост в ОПУБЛИКОВАННОМ формате (1:1 / 4:5 / 9:16), а не
    // квадратом по умолчанию. Фолбэк: media → 4:5 (портрет). Клампим к
    // диапазону от 9:16 (0.5625, самый высокий) до 1:1 (1.0).
    final hasMultiple = post.media.length > 1;
    double clampAspect(double? a) => (a ?? 0.8).clamp(0.5625, 1.0).toDouble();
    // Карусель: контейнер берёт самый вытянутый (портретный) формат среди
    // всех медиа, а более широкие кадры центрируются letterbox'ом — каждый
    // показывается в СВОЁМ формате, ничего не форсится «под первый».
    final aspectRatio = hasMultiple
        ? post.media
            .map((m) => clampAspect(m.aspectRatio))
            .reduce((a, b) => a < b ? a : b)
        : clampAspect(post.media.first.aspectRatio);

    return GestureDetector(
      onDoubleTap: _onDoubleTap,
      // Фото в ленте НЕ разворачиваем на весь экран (по требованию).
      // Двойной тап — лайк.
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SeeURadii.card),
          boxShadow: SeeUShadows.md,
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image carousel or single image
              if (hasMultiple)
                PageView.builder(
                  controller: _pageController,
                  itemCount: post.media.length,
                  itemBuilder: (_, index) =>
                      _buildMediaItem(post.media[index], letterbox: true),
                )
              else
                _buildMediaItem(post.media.first),

              // Double-tap heart animation + particle burst
              if (_showHeart)
                Center(
                  child: AnimatedBuilder(
                    animation: _heartAnimController,
                    builder: (_, __) => Opacity(
                      opacity: _heartOpacityAnim.value,
                      child: Transform.scale(
                        scale: _heartScaleAnim.value,
                        child: Icon(
                          PhosphorIcons.heart(PhosphorIconsStyle.fill),
                          color: SeeUColors.accent,
                          size: 80,
                        ),
                      ),
                    ),
                  ),
                ),
              Center(
                child: SeeUHeartBurst(key: _burstKeyNormal),
              ),

              // Dot indicator for multiple images
              if (hasMultiple)
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: SmoothPageIndicator(
                      controller: _pageController,
                      count: post.media.length,
                      effect: WormEffect(
                        dotWidth: 6,
                        dotHeight: 6,
                        spacing: 5,
                        activeDotColor: SeeUColors.accent,
                        dotColor: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),

              // L09: Page counter badge with text (e.g. "1/3")
              if (hasMultiple)
                Positioned(
                  top: 12,
                  right: 12,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.14),
                              Colors.black.withValues(alpha: 0.28),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(SeeURadii.pill),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 0.5,
                          ),
                        ),
                        // BUG-16: micro-typography token + white override для
                        // counter-badge поверх media. Раньше inline fontSize:12.
                        child: Text(
                          '${_currentPage + 1}/${post.media.length}',
                          style: SeeUTypography.micro.copyWith(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaItem(PostMedia media, {bool letterbox = false}) {
    final c = context.seeuColors;
    if (media.type == MediaType.video) {
      return FeedVideoPlayer(
        url: media.url,
        thumbnailUrl: media.thumbnailUrl,
      );
    }
    // Full-bleed post media paints ≈ screen width (minus the 16px side
    // padding) — decode/cache to that size instead of the full-res source.
    final slotCacheWidth =
        ((MediaQuery.sizeOf(context).width - 32) *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    final image = CachedNetworkImage(
      imageUrl: media.url,
      // M2: одиночное фото заполняет свой истинный ratio (cover); в карусели
      // кадр показывается contain'ом внутри общего контейнера, чтобы разные
      // форматы не обрезались.
      fit: letterbox ? BoxFit.contain : BoxFit.cover,
      memCacheWidth: slotCacheWidth,
      maxWidthDiskCache: slotCacheWidth,
      placeholder: (_, __) => Container(
        color: c.surface2,
      ),
      errorWidget: (_, __, ___) => Container(
        color: c.surface2,
        child: Icon(PhosphorIcons.imageSquare(),
            color: c.ink3, size: 48),
      ),
    );
    if (!letterbox) return image;
    // Letterbox: нейтральный фон заполняет поля вокруг кадра в его формате.
    return Container(
      color: c.surface2,
      alignment: Alignment.center,
      child: image,
    );
  }

  // U14: Delegates to shared _buildActionsRow
  Widget _buildActions(BuildContext context, Post post) {
    return _buildActionsRow(context, post);
  }

  Widget _buildLikesRow(BuildContext context, Post post) {
    final c = context.seeuColors;
    if (post.likesCount <= 0) return const SizedBox.shrink();
    String likesText;
    final hasNamed = post.likedByUsername != null && post.likesCount > 0;
    if (hasNamed) {
      if (post.likesCount == 1) {
        likesText = 'Нравится ${post.likedByUsername}';
      } else {
        likesText = 'Нравится ${post.likedByUsername} и ещё ${formatCount(post.likesCount - 1)}';
      }
    } else {
      likesText = '${formatCount(post.likesCount)} отметок «Нравится»';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Text(
        likesText,
        style:
            SeeUTypography.caption.copyWith(fontWeight: FontWeight.w700, color: c.ink),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }

  Widget _buildCaption(BuildContext context, Post post) {
    if (post.caption == null || post.caption!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: PostExpandableCaption(
        postId: post.id,
        username: post.author.username,
        caption: post.caption!,
      ),
    );
  }

  Widget _buildCommentsPreview(BuildContext context, Post post) {
    final c = context.seeuColors;
    if (post.commentsCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () => context.push('/post/${post.id}/comments'),
        child: SeeUChip(
          label:
              '${formatCount(post.commentsCount)} ${pluralRu(post.commentsCount, 'комментарий', 'комментария', 'комментариев')}',
          bgColor: c.accentSoft,
          fgColor: SeeUColors.accent,
        ),
      ),
    );
  }

  Widget _buildTimeRow(BuildContext context, Post post) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        formatRelativeTime(post.createdAt),
        style: SeeUTypography.micro,
      ),
    );
  }

  void _toastMsg(String m) {
    if (!mounted) return;
    showSeeUSnackBar(context, m);
  }

  /// «Не интересно» — hides the post AND tells the ranking «show less like this»
  /// (negative interest signal on the author/content-type).
  void _notInterested(Post post) {
    ref.read(apiClientProvider).post(ApiEndpoints.viewPost(post.id)).ignore();
    ref.read(interestTrackerProvider).track(
          eventType: 'not_interested',
          entityType: 'post',
          entityId: post.id,
          authorId: post.author.id,
          source: 'feed_menu',
        );
    ref.read(feedProvider.notifier).removePost(post.id);
    _toastMsg('Спасибо, будем реже показывать такое');
    if (widget.isDetail) Navigator.of(context).maybePop();
  }

  /// «Скрыть» — just removes this post from the feed (no ranking signal).
  void _hidePost(Post post) {
    ref.read(apiClientProvider).post(ApiEndpoints.viewPost(post.id)).ignore();
    ref.read(feedProvider.notifier).removePost(post.id);
    _toastMsg('Пост скрыт');
    if (widget.isDetail) Navigator.of(context).maybePop();
  }

  void _copyLink(Post post) {
    Clipboard.setData(ClipboardData(text: postShareUrl(post.id)));
    _toastMsg('Ссылка скопирована');
  }

  Future<void> _unfollowAuthor(Post post) async {
    try {
      await ref
          .read(apiClientProvider)
          .delete(ApiEndpoints.followUser(post.author.username));
      _toastMsg('Вы отписались от @${post.author.username}');
    } catch (_) {
      _toastMsg('Не удалось отписаться');
    }
  }

  void _showPostOptions(BuildContext context, Post post) {
    final c = context.seeuColors;
    final myId = ref.read(authProvider).user?.id;
    showSeeUBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  Icon(PhosphorIconsRegular.eyeSlash, color: c.ink),
              title: Text('Не интересно', style: SeeUTypography.body),
              subtitle: Text('Реже показывать подобное',
                  style: SeeUTypography.caption.copyWith(color: c.ink3)),
              onTap: () {
                Navigator.pop(context);
                _notInterested(post);
              },
            ),
            ListTile(
              leading: Icon(PhosphorIcons.eyeClosed(), color: c.ink),
              title: Text('Скрыть этот пост', style: SeeUTypography.body),
              onTap: () {
                Navigator.pop(context);
                _hidePost(post);
              },
            ),
            ListTile(
              leading: Icon(PhosphorIcons.shareFat(),
                  color: c.ink),
              title: Text('Поделиться', style: SeeUTypography.body),
              onTap: () {
                Navigator.pop(context);
                if (!mounted) return;
                showShareSheet(
                  context: context,
                  url: postShareUrl(post.id),
                  title: 'Поделиться постом',
                  subtitle: post.author.username.isNotEmpty
                      ? '@${post.author.username}'
                      : null,
                  forwardablePostId: post.id,
                );
              },
            ),
            ListTile(
              leading: Icon(
                  post.isSaved
                      ? PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.fill)
                      : PhosphorIcons.bookmarkSimple(),
                  color: c.ink),
              // Это тоггл: на уже сохранённом посте пункт честно говорит,
              // что снимет сохранение (раньше всегда «Сохранить» + без
              // какого-либо фидбека).
              title: Text(
                  post.isSaved ? 'Убрать из сохранённого' : 'Сохранить',
                  style: SeeUTypography.body),
              onTap: () {
                final wasSaved = post.isSaved;
                _savePost();
                Navigator.pop(context);
                _toastMsg(wasSaved
                    ? 'Убрано из сохранённого'
                    : 'Сохранено в закладки');
              },
            ),
            ListTile(
              leading: Icon(PhosphorIcons.link(), color: c.ink),
              title: Text('Копировать ссылку', style: SeeUTypography.body),
              onTap: () {
                Navigator.pop(context);
                _copyLink(post);
              },
            ),
            if (myId != null && post.author.id != myId)
              ListTile(
                leading: Icon(PhosphorIcons.userMinus(), color: c.ink),
                title: Text('Отписаться от @${post.author.username}',
                    style: SeeUTypography.body),
                onTap: () {
                  Navigator.pop(context);
                  _unfollowAuthor(post);
                },
              ),
            ListTile(
              leading:
                  Icon(PhosphorIcons.flag(), color: SeeUColors.like),
              title: Text('Пожаловаться',
                  style: SeeUTypography.body
                      .copyWith(color: SeeUColors.like)),
              onTap: () {
                Navigator.pop(context);
                if (!mounted) return;
                showReportSheet(
                  context: context,
                  ref: ref,
                  targetType: 'post',
                  targetId: post.id,
                );
              },
            ),
            ListTile(
              leading: const PhosphorIcon(PhosphorIconsRegular.prohibit,
                  color: SeeUColors.danger),
              title: Text('Заблокировать автора',
                  style: SeeUTypography.body
                      .copyWith(color: SeeUColors.danger)),
              onTap: () {
                Navigator.pop(context);
                if (!mounted) return;
                _confirmBlockAuthor();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

}

// --- Action button (tappable) ------------------------------------------------
