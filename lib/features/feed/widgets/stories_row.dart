import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/design/design.dart';
import '../../../core/models/audio_track.dart';
import '../../../core/providers/access_provider.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../core/providers/realtime_provider.dart';
import '../../../core/providers/story_provider.dart';
import 'story_poll_overlay.dart';
import 'story_viewers_sheet.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/models/story.dart';
import '../../stories/text_story_backgrounds.dart';
import 'story_circle.dart';

class StoriesRow extends ConsumerWidget {
  const StoriesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storyState = ref.watch(storyProvider);
    final authState = ref.watch(authProvider);
    final me = authState.user;

    if (storyState.isLoading) {
      return _buildShimmer();
    }

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: storyState.storyGroups.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: StoryCircle(
                imageUrl: me?.avatarUrl,
                username: 'Ваша история',
                isOwn: true,
                onTap: () => context.push('/story/create'),
              ),
            );
          }
          final group = storyState.storyGroups[index - 1];
          // PROFILE-3: зелёный ring если в группе есть хоть одна CF-story.
          final hasCloseFriends =
              group.stories.any((s) => s.isCloseFriendsOnly);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: StoryCircle(
              imageUrl: group.author.avatarUrl,
              username: group.author.username,
              isSeen: group.allSeen,
              hasCloseFriendsStory: hasCloseFriends,
              onTap: () => _openStoryViewer(
                  context, storyState.storyGroups, index - 1, me?.id),
            ),
          );
        },
      ),
    );
  }

  void _openStoryViewer(
      BuildContext context, List<StoryGroup> groups, int groupIndex, String? currentUserId) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => StoryViewerRoute(
          groups: groups,
          initialGroupIndex: groupIndex,
          currentUserId: currentUserId,
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return SizedBox(
      height: 100,
      child: SeeUShimmer(
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: 6,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShimmerBox(width: 68, height: 68, radius: SeeURadii.pill),
                  const SizedBox(height: 5),
                  ShimmerBox(width: 52, height: 10, radius: 5),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// Inline story viewer route wrapper
/// Стеклянная плашка/чип поверх story-медиа: свой backdrop-blur (18) +
/// светлый градиент → тёмный тинт + тонкий бордюр. Единый рецепт для
/// бейджей автора, счётчика просмотров, музыки, own-story bar и reply-pill.
class _StoryGlassPill extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _StoryGlassPill({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  });

  static const double radius = SeeURadii.pill;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.14),
                Colors.black.withValues(alpha: 0.28),
              ],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// §03 «Лента» (SeeU CORE): фон вьюера историй и сплошные тёмные зоны
// letterbox'а — верхняя под прогресс-бары/автора, нижняя под reply-бар и
// кнопки. Медиа рендерится МЕЖДУ зонами, а не под весь экран.
const Color _kStoryViewerBg = Color(0xFF0E0C0A);
const double _kStoryTopZoneH = 104;
const double _kStoryBottomZoneH = 96;

class StoryViewerRoute extends StatelessWidget {
  final List<StoryGroup> groups;
  final int initialGroupIndex;
  final String? currentUserId;

  const StoryViewerRoute({
    super.key,
    required this.groups,
    required this.initialGroupIndex,
    this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    return SwipeToDismiss(
      downOnly: true,
      child: _InlineStoryViewer(
        groups: groups,
        initialGroupIndex: initialGroupIndex,
        currentUserId: currentUserId,
      ),
    );
  }
}

class _InlineStoryViewer extends ConsumerStatefulWidget {
  final List<StoryGroup> groups;
  final int initialGroupIndex;
  final String? currentUserId;

  const _InlineStoryViewer({
    required this.groups,
    required this.initialGroupIndex,
    this.currentUserId,
  });

  @override
  ConsumerState<_InlineStoryViewer> createState() =>
      _InlineStoryViewerState();
}

class _InlineStoryViewerState extends ConsumerState<_InlineStoryViewer>
    with TickerProviderStateMixin {
  late int _groupIndex;
  late int _storyIndex;
  late AnimationController _progressController;
  // H24: _pageController removed — not attached to any PageView; _groupIndex is changed directly via setState

  // Reply state
  bool _isReplyOpen = false;
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();

  /// Per-session realtime override of `views_count`. When the server
  /// pushes `story.view.added`, we stash the new count here and use it in
  /// build over `widget.groups[i].viewsCount`. Stays empty until at least
  /// one event arrives. Cleared on dispose with the State itself.
  final Map<String, int> _liveViewsOverride = {};

  /// Optimistic like override, keyed by story id — `widget.groups` is a
  /// static snapshot captured when the viewer was opened (StoryProvider's
  /// state is immutable and re-created on every mutation), so a like/unlike
  /// during this viewing session needs a local layer on top of the
  /// server-hydrated `story.isLiked` to show up immediately. Reconciled
  /// against the provider's authoritative state after each toggle (see
  /// [_toggleLike]) since StoryNotifier.toggleLike rolls back on failure.
  final Map<String, bool> _likedOverride = {};

  /// Локальный оверрайд poll'а после голосования. `widget.groups` — тот же
  /// список объектов, что лежит в состоянии StoryNotifier'а; мутировать его
  /// по индексу (как раньше делал _updateStoryPoll) значило менять
  /// «иммутабельный» стейт мимо провайдера.
  final Map<String, StoryPoll> _pollOverride = {};

  /// Истории, для которых просмотр уже отправлен в ЭТОЙ сессии вьюера.
  final Set<String> _seenSent = {};

  ProviderSubscription<AsyncValue<RealtimeEvent>>? _wsSub;

  // Like animation
  AnimationController? _likeAnimController;
  Animation<double>? _likeScaleAnim;
  bool _showCenterHeart = false;

  // Heart button scale animation
  AnimationController? _heartBtnAnimController;
  Animation<double>? _heartBtnScaleAnim;

  // Swipe tracking
  bool _isSwiping = false;
  // M17: Track long-press state to prevent onTapUp from firing after long-press
  bool _isLongPressing = false;

  // ── Audio playback ─────────────────────────────────────────────────────
  // Photo-stories с audio_track_id играют Spotify-style фоновую музыку.
  // Кэш track-метадаты по UUID, чтобы повторно не дёргать /audio-tracks/:id
  // при возврате к уже-проигранной story.
  AudioPlayer? _audioPlayer;
  final Map<String, AudioTrack?> _audioCache = {};
  String? _currentLoadedTrackId; // последний загруженный URL в плеер
  /// Generation-guard для _syncAudio (как _initToken у FeedVideoPlayer):
  /// при быстром перелистывании конкурентные вызовы не должны доигрывать
  /// setUrl/play трека уже пропущенной истории.
  int _audioSyncToken = 0;

  // ── Video stories ──────────────────────────────────────────────────────
  // Раньше видео-истории рендерились CachedNetworkImage'ем (mp4 как
  // картинка → вечный спиннер/градиент): плеера в вьюере не было вовсе.
  VideoPlayerController? _videoCtrl;
  String? _videoUrl; // URL, загруженный в _videoCtrl
  int _videoInitToken = 0;

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.initialGroupIndex;
    _storyIndex = 0;

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        if (!mounted) return;
        // Defensive guard: even if the progress controller somehow finishes
        // (race between `.stop()` in `_openReply` and a pending status tick,
        // a hot-reload, etc.) while the reply sheet is open, do NOT advance
        // — the user is mid-typing and getting yanked to the next story is
        // the bug audit-flagged in P1.
        if (_isReplyOpen) return;
        _nextStory();
      });
    _startProgressForCurrent();

    // Audio: пробуем стартануть music для первой story в фоне (не ждём).
    _audioPlayer = AudioPlayer();
    _syncAudio();
    _syncVideo();
    // Регистрируем просмотр первой истории — раньше markSeen не вызывался
    // НИГДЕ: кольцо никогда не гасло, а счётчик просмотров автора не рос.
    _markCurrentSeen();

    // Subscribe to realtime view-count pushes (`story.view.added`) so the
    // open viewer's «X views» badge updates live as new viewers arrive,
    // instead of being stale from when the sheet was opened.
    _wsSub = ref.listenManual<AsyncValue<RealtimeEvent>>(
      realtimeEventsProvider,
      (prev, next) {
        next.whenData((evt) {
          if (evt.type != 'story.view.added' || evt.payload is! Map) return;
          final p = (evt.payload as Map).cast<String, dynamic>();
          final id = p['story_id']?.toString() ?? '';
          final n = p['views_count'];
          if (id.isEmpty || n is! num) return;
          if (!mounted) return;
          setState(() => _liveViewsOverride[id] = n.toInt());
        });
      },
    );

    // Center heart animation
    _likeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (!mounted) return;
          setState(() => _showCenterHeart = false);
        }
      });
    _likeScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.4), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(CurvedAnimation(
      parent: _likeAnimController!,
      curve: Curves.easeOut,
    ));

    // Heart button bounce
    _heartBtnAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _heartBtnScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(
      parent: _heartBtnAnimController!,
      curve: Curves.easeInOut,
    ));

    // Кнопка отправки ответа подписана на _replyController через
    // ValueListenableBuilder — глобальный listener+setState не нужен.
  }

  @override
  void dispose() {
    _wsSub?.close();
    _progressController.dispose();
    _likeAnimController?.dispose();
    _heartBtnAnimController?.dispose();
    _replyController.dispose();
    _replyFocusNode.dispose();
    _audioPlayer?.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  /// Стартует прогресс для текущей истории. Фото/текст — фиксированные 5 сек;
  /// для видео прогресс запускает _syncVideo, когда клип инициализирован
  /// (длительность бара = длительность клипа).
  void _startProgressForCurrent() {
    if (_currentStory.isVideo) return;
    _progressController.duration = const Duration(seconds: 5);
    _progressController.forward();
  }

  /// Пауза истории целиком: прогресс + видео (если играет).
  void _pauseStory() {
    _progressController.stop();
    _videoCtrl?.pause();
  }

  /// Продолжить с места паузы.
  void _resumeStory() {
    _progressController.forward();
    final vc = _videoCtrl;
    if (vc != null && vc.value.isInitialized) vc.play();
  }

  /// Подгоняет видео-плеер под текущую историю (generation-guard от быстрых
  /// перелистываний — зеркалит _syncAudio/_initToken FeedVideoPlayer).
  Future<void> _syncVideo() async {
    final token = ++_videoInitToken;
    final story = _currentStory;

    if (!story.isVideo || story.mediaUrl.isEmpty) {
      final old = _videoCtrl;
      _videoCtrl = null;
      _videoUrl = null;
      if (old != null) await old.dispose();
      return;
    }
    if (_videoUrl == story.mediaUrl && _videoCtrl != null) {
      _videoCtrl!
        ..seekTo(Duration.zero)
        ..play();
      _progressController
        ..reset()
        ..forward();
      return;
    }

    final old = _videoCtrl;
    _videoCtrl = null;
    _videoUrl = null;
    if (old != null) await old.dispose();
    if (!mounted || token != _videoInitToken) return;

    final ctrl = VideoPlayerController.networkUrl(Uri.parse(story.mediaUrl));
    try {
      await ctrl.initialize();
    } catch (_) {
      await ctrl.dispose();
      return;
    }
    if (!mounted || token != _videoInitToken) {
      await ctrl.dispose();
      return;
    }
    _videoCtrl = ctrl;
    _videoUrl = story.mediaUrl;
    final d = ctrl.value.duration;
    if (d > Duration.zero) {
      _progressController.duration = d;
    }
    _progressController
      ..reset()
      ..forward();
    ctrl
      ..setLooping(false)
      ..play();
    setState(() {});
  }

  StoryGroup get _currentGroup => widget.groups[_groupIndex];
  Story get _currentStory => _currentGroup.stories[_storyIndex];

  /// STORY-3: вызывается из StoryPollOverlay после успешного POST — кладём
  /// свежие counts в локальный оверрайд (см. [_pollOverride]).
  void _updateStoryPoll(String storyId, StoryPoll updatedPoll) {
    if (mounted) setState(() => _pollOverride[storyId] = updatedPoll);
  }

  /// Регистрирует просмотр текущей истории: кольцо у аватарки гаснет, автор
  /// видит зрителя в списке. Дедуп на сессию вьюера; свои истории и так не
  /// считаются (бэк игнорирует self-view), но и не дёргаем их вовсе.
  void _markCurrentSeen() {
    if (!mounted) return;
    if (widget.currentUserId != null &&
        _currentGroup.author.id == widget.currentUserId) {
      return;
    }
    final story = _currentStory;
    if (!_seenSent.add(story.id)) return;
    ref.read(storyProvider.notifier).markSeen(story.id);
  }

  void _nextStory() {
    if (_isReplyOpen) return;
    _progressController.reset();
    if (_storyIndex < _currentGroup.stories.length - 1) {
      setState(() => _storyIndex++);
      // M15: mounted check before forward after potential navigation
      if (!mounted) return;
      _startProgressForCurrent();
    } else if (_groupIndex < widget.groups.length - 1) {
      // H24: setState directly, no PageController needed
      setState(() {
        _groupIndex++;
        _storyIndex = 0;
      });
      if (!mounted) return;
      _startProgressForCurrent();
    } else {
      Navigator.of(context).pop();
      return;
    }
    _syncAudio();
    _syncVideo();
    _markCurrentSeen();
  }

  void _prevStory() {
    if (_isReplyOpen) return;
    _progressController.reset();
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
    } else if (_groupIndex > 0) {
      // H24: setState directly, no PageController needed
      setState(() {
        _groupIndex--;
        _storyIndex = widget.groups[_groupIndex].stories.length - 1;
      });
    }
    if (!mounted) return;
    _startProgressForCurrent();
    _syncAudio();
    _syncVideo();
    _markCurrentSeen();
  }

  void _nextGroup() {
    if (_groupIndex < widget.groups.length - 1) {
      _progressController.reset();
      // H24: setState directly, no PageController needed
      setState(() {
        _groupIndex++;
        _storyIndex = 0;
      });
      if (!mounted) return;
      _startProgressForCurrent();
      _syncAudio();
      _syncVideo();
      _markCurrentSeen();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prevGroup() {
    if (_groupIndex > 0) {
      _progressController.reset();
      // H24: setState directly, no PageController needed
      setState(() {
        _groupIndex--;
        _storyIndex = 0;
      });
      if (!mounted) return;
      _startProgressForCurrent();
      _syncAudio();
      _syncVideo();
      _markCurrentSeen();
    }
  }

  /// Подгоняет аудио-плеер под current story:
  /// - audio_track_id null или mediaType=video → stop + clear (видео-сторис
  ///   звучит сам, дублировать не надо).
  /// - есть id → fetch из кэша или /audio-tracks/:id → setUrl + play.
  Future<void> _syncAudio() async {
    final token = ++_audioSyncToken;
    final story = _currentStory;
    final player = _audioPlayer;
    if (player == null) return;

    final trackId = story.audioTrackId;
    if (trackId == null || trackId.isEmpty ||
        story.mediaType == StoryMediaType.video) {
      if (_currentLoadedTrackId != null) {
        await player.stop();
        _currentLoadedTrackId = null;
      }
      return;
    }
    if (_currentLoadedTrackId == trackId && player.playing) return;

    // Load (через кэш) и play.
    AudioTrack? track = _audioCache[trackId];
    if (track == null && !_audioCache.containsKey(trackId)) {
      try {
        final api = ref.read(apiClientProvider);
        final r = await api.get(ApiEndpoints.audioTrackById(trackId));
        final data = r.data is Map && (r.data as Map).containsKey('data')
            ? r.data['data']
            : r.data;
        if (data is Map<String, dynamic>) {
          track = AudioTrack.fromJson(data);
        }
      } catch (_) {
        track = null;
      }
      _audioCache[trackId] = track;
    }
    if (track == null || track.audioUrl.isEmpty) return;
    // За время fetch'а юзер мог перелистнуть — доигрывать чужой трек нельзя.
    if (!mounted || token != _audioSyncToken) return;
    try {
      await player.setUrl(track.audioUrl);
      if (!mounted || token != _audioSyncToken) {
        await player.stop();
        return;
      }
      // MUSIC-7: seek на offset до play если juzер выбрал не-начало трека.
      if (story.audioStartSeconds > 0) {
        await player.seek(Duration(seconds: story.audioStartSeconds));
      }
      _currentLoadedTrackId = trackId;
      if (!mounted || token != _audioSyncToken) return;
      await player.play();
      if (mounted) setState(() {});
    } catch (_) {/* network/decoding error — silent */}
  }

  /// §03: «Поделиться» на чужой истории — системный share со ссылкой на
  /// профиль автора (у историй нет публичного URL — они эфемерны).
  void _shareStory(Story story) {
    _pauseStory();
    final username = _currentGroup.author.username;
    Share.share(
        'История @$username в SeeU — https://seeu.app/profile/$username');
  }

  void _openReply() {
    _pauseStory();
    setState(() => _isReplyOpen = true);
    _replyFocusNode.requestFocus();
  }

  void _closeReply() {
    _replyFocusNode.unfocus();
    _replyController.clear();
    setState(() => _isReplyOpen = false);
    _resumeStory();
  }

  /// Отправляет ответ на сторис как обычное личное сообщение автору
  /// (нет отдельного backend-эндпоинта "ответить на сторис" — переиспользуем
  /// DM с текстовым контекстом). Успех показывается ТОЛЬКО после того как
  /// запрос реально прошёл — до этого поле/панель не трогаем, чтобы при
  /// ошибке пользователь мог повторить отправку без повторного набора текста.
  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();

    final authorId = _currentGroup.author.id;
    try {
      final chatId = await ref
          .read(chatListProvider.notifier)
          .getOrCreateChat(authorId);
      if (chatId == null) {
        throw Exception('Не удалось открыть чат с автором истории');
      }
      await ref.read(chatMessagesProvider(chatId).notifier).sendMessage(
            'Ответ на историю:\n$text',
            rethrowOnError: true,
          );

      if (!mounted) return;
      _replyController.clear();
      _replyFocusNode.unfocus();
      setState(() => _isReplyOpen = false);
      _resumeStory();
      showSeeUSnackBar(
        context,
        'Сообщение отправлено',
        icon: PhosphorIcons.paperPlaneTilt(),
        tone: SeeUTone.success,
        duration: const Duration(seconds: 2),
      );
    } catch (_) {
      if (!mounted) return;
      showSeeUSnackBar(
        context,
        'Не удалось отправить сообщение. Попробуйте ещё раз',
        tone: SeeUTone.danger,
      );
    }
  }

  void _toggleLike() {
    HapticFeedback.mediumImpact();
    final storyId = _currentStory.id;
    final bool wasLiked = _likedOverride[storyId] ?? _currentStory.isLiked;
    final bool newLiked = !wasLiked;
    setState(() {
      _likedOverride[storyId] = newLiked;
      if (newLiked) {
        _showCenterHeart = true;
        _likeAnimController!.reset();
        _likeAnimController!.forward();
      }
    });
    _heartBtnAnimController!.reset();
    _heartBtnAnimController!.forward();
    // Delegate to StoryNotifier — it does the actual POST/DELETE, persists
    // `is_liked`/`likes_count` server-side (BACK: liked stories previously
    // never came back on refetch, so this used to be purely a local Set that
    // reset every time the viewer reopened), and rolls its own state back on
    // failure. We reconcile our local override against that authoritative
    // state afterwards instead of duplicating the error handling here.
    _likeStoryApi(storyId);
  }

  Future<void> _likeStoryApi(String storyId) async {
    await ref.read(storyProvider.notifier).toggleLike(storyId);
    if (!mounted) return;
    // Reconcile: if the request failed, StoryNotifier already rolled its own
    // state back to the pre-toggle value — mirror that here so this viewer
    // doesn't keep showing a filled heart the backend never recorded.
    for (final group in ref.read(storyProvider).storyGroups) {
      for (final s in group.stories) {
        if (s.id == storyId) {
          setState(() => _likedOverride[storyId] = s.isLiked);
          return;
        }
      }
    }
  }

  /// §03 «Story свой»: слева внизу — стопка из 2 аватаров зрителей 24px
  /// (пересечение на 8px, бордюр 1.5 цветом фона вьюера) + число просмотров
  /// (600 15 белым). Тап открывает существующий StoryViewersSheet.
  /// Данных об аватарах зрителей в модели Story нет — стопка рисуется
  /// детерминированными градиент-заглушками из [SeeUColors.avatarPalettes],
  /// число при этом реальное (с учётом realtime-оверрайда).
  Widget _buildOwnStoryBottom(Story story) {
    final live = _liveViewsOverride[story.id] ?? story.viewsCount;

    // Одна градиент-заглушка аватара зрителя.
    Widget viewerStub(int seed) {
      final palette =
          SeeUColors.avatarPalettes[seed % SeeUColors.avatarPalettes.length];
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: palette,
          ),
          border: Border.all(color: _kStoryViewerBg, width: 1.5),
        ),
      );
    }

    // 0 зрителей — стопки нет; 1 зритель — один кружок.
    final stubCount = live >= 2 ? 2 : live;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openViewersSheet(story),
        // Высота 44 — держим тач-таргет по гайду при аватарах 24px.
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (stubCount > 0) ...[
                SizedBox(
                  width: 24.0 + (stubCount - 1) * 16.0,
                  height: 24,
                  child: Stack(
                    children: [
                      for (var i = 0; i < stubCount; i++)
                        Positioned(left: i * 16.0, child: viewerStub(i)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                live == 0 ? 'Пока никто не посмотрел' : '$live',
                style: SeeUTypography.body.copyWith(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openViewersSheet(Story story) async {
    HapticFeedback.lightImpact();
    _pauseStory();
    await showSeeUBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StoryViewersSheet(
        storyId: story.id,
        totalCount: _liveViewsOverride[story.id] ?? story.viewsCount,
      ),
    );
    if (mounted && !_isReplyOpen) {
      _resumeStory();
    }
  }

  /// §03 «Story свой»: меню управления своей историей («три точки» справа
  /// вверху). Пока меню/подтверждение открыты — история на паузе; при
  /// закрытии без удаления возобновляем показ.
  Future<void> _openOwnStoryOptions(Story story) async {
    HapticFeedback.lightImpact();
    _pauseStory();
    final action = await showSeeUBottomSheet<String>(
      context: context,
      builder: (sheetCtx) {
        final c = sheetCtx.seeuColors;
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const PhosphorIcon(PhosphorIconsRegular.trash,
                    color: SeeUColors.like),
                title: Text('Удалить историю',
                    style:
                        SeeUTypography.body.copyWith(color: SeeUColors.like)),
                onTap: () => Navigator.of(sheetCtx).pop('delete'),
              ),
              ListTile(
                leading: Icon(PhosphorIcons.x(), color: c.ink),
                title: Text('Закрыть', style: SeeUTypography.body),
                onTap: () => Navigator.of(sheetCtx).pop('close'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (action == 'delete') {
      // _deleteCurrentStory сам держит паузу (подтверждение), возобновляет при
      // отмене и закрывает вьюер после успешного удаления.
      await _deleteCurrentStory(story);
    } else if (!_isReplyOpen) {
      _resumeStory();
    }
  }

  /// Удаляет текущую (видимую) историю после подтверждения. Успех → закрываем
  /// вьюер; список историй провайдер уже обновил, так что кружок исчезнет.
  Future<void> _deleteCurrentStory(Story story) async {
    final confirmed = await showSeeUConfirm(
      context,
      title: 'Удалить историю?',
      message: 'Её больше не увидят — просмотры и реакции пропадут.',
      confirmLabel: 'Удалить',
      destructive: true,
      icon: PhosphorIconsRegular.trash,
    );
    if (!mounted) return;
    if (!confirmed) {
      if (!_isReplyOpen) _resumeStory();
      return;
    }

    final ok = await ref.read(storyProvider.notifier).deleteStory(story.id);
    if (!mounted) return;
    if (!ok) {
      showSeeUSnackBar(
        context,
        'Не удалось удалить историю. Попробуйте ещё раз',
        tone: SeeUTone.danger,
      );
      if (!_isReplyOpen) _resumeStory();
      return;
    }
    // История удалена — закрываем вьюер (StoryProvider уже убрал её из ленты).
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final story = _currentStory;
    final group = _currentGroup;
    final isLiked = _likedOverride[story.id] ?? story.isLiked;
    final isOwnStory = widget.currentUserId != null &&
        group.author.id == widget.currentUserId;

    // Фолбэк-фон (когда у story нет media) — из общей avatarPalettes вместо
    // локального хардкода hex-градиентов.
    final gradientColors = SeeUColors
        .avatarPalettes[_groupIndex % SeeUColors.avatarPalettes.length];

    final bool hasValidUrl =
        story.mediaUrl.isNotEmpty;

    Widget storyImageWidget;
    if (story.isText) {
      // STORY-1: text-сторис — рендерим background-preset из bg_color +
      // центрированный текст из textOverlay.
      final bg = textStoryBackgroundFor(story.bgColor);
      storyImageWidget = Container(
        decoration: BoxDecoration(
          gradient: bg.gradient,
          color: bg.color,
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Text(
          story.textOverlay ?? '',
          textAlign: TextAlign.center,
          // Editorial: серифный display-пресет для text-сторис.
          style: SeeUTypography.displayM.copyWith(
            color: bg.textColor,
            fontSize: 30,
            height: 1.25,
          ),
        ),
      );
    } else if (!hasValidUrl) {
      // No URL — show gradient background immediately
      storyImageWidget = Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
        ),
      );
    } else if (story.isVideo) {
      // Видео-история — реальный плеер (раньше mp4 скармливался
      // CachedNetworkImage и показывался вечный спиннер/градиент).
      final vc = _videoCtrl;
      final ready = vc != null &&
          _videoUrl == story.mediaUrl &&
          vc.value.isInitialized;
      storyImageWidget = ready
          ? FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: vc.value.size.width,
                height: vc.value.size.height,
                child: VideoPlayer(vc),
              ),
            )
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
              ),
              child: const Center(
                child: CircularProgressIndicator(
                    color: Colors.white54, strokeWidth: 2),
              ),
            );
    } else {
      // Full-screen story media — decode/cache to the device width rather than
      // the full-res source to keep memory bounded.
      final fullCacheWidth = (MediaQuery.sizeOf(context).width *
              MediaQuery.devicePixelRatioOf(context))
          .round();
      storyImageWidget = CachedNetworkImage(
        imageUrl: story.mediaUrl,
        fit: BoxFit.cover,
        memCacheWidth: fullCacheWidth,
        maxWidthDiskCache: fullCacheWidth,
        placeholder: (_, __) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(
                color: Colors.white54, strokeWidth: 2),
          ),
        ),
        errorWidget: (_, __, ___) => GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      // §03: фон вьюера — тёплый чёрный из дизайна, не чистый black.
      backgroundColor: _kStoryViewerBg,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Main gesture + content layer
          GestureDetector(
        onTapDown: (details) {
          if (_isReplyOpen) return;
          _pauseStory();
        },
        onTapUp: (details) {
          // M17: Ignore tap-up if a long-press was in progress
          if (_isLongPressing) return;
          if (_isReplyOpen) {
            _closeReply();
            return;
          }
          final width = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < width / 2) {
            _prevStory();
          } else {
            _nextStory();
          }
        },
        onLongPressStart: (_) {
          if (_isReplyOpen) return;
          _isLongPressing = true;
          _pauseStory();
        },
        onLongPressEnd: (_) {
          if (_isReplyOpen) return;
          _isLongPressing = false;
          _resumeStory();
        },
        onHorizontalDragStart: (details) {
          if (_isReplyOpen) return;
          _isSwiping = true;
          _pauseStory();
        },
        onHorizontalDragEnd: (details) {
          if (!_isSwiping || _isReplyOpen) return;
          _isSwiping = false;
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -300) {
            _nextGroup();
          } else if (velocity > 300) {
            _prevGroup();
          } else {
            _resumeStory();
          }
        },
        onVerticalDragEnd: (details) {
          if (_isReplyOpen) return;
          if (details.primaryVelocity != null &&
              details.primaryVelocity! > 300) {
            Navigator.of(context).pop();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // §03: медиа letterbox'ится между сплошными тёмными зонами
            // (не под весь экран). Оверлеи по медиа — полл, подпись,
            // центр-сердце — живут ВНУТРИ этой зоны, чтобы не заезжать на
            // тёмные поля. Тап-зоны навигации при этом работают по всей
            // высоте: зоны ниже — hit-testable ColoredBox'ы, тапы по ним
            // доходят до общего GestureDetector'а.
            Positioned(
              top: _kStoryTopZoneH,
              bottom: _kStoryBottomZoneH,
              left: 0,
              right: 0,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  storyImageWidget,

                  // STORY-3: интерактивный poll-overlay. Позиционируется в
                  // (x,y) фракциях зоны медиа, viewer тапает option → POST →
                  // state update. Автор не видит интерактивные кнопки — для
                  // него просто превью.
                  if (story.poll != null)
                    Positioned.fill(
                      child: LayoutBuilder(builder: (ctx, cs) {
                        final p = _pollOverride[story.id] ?? story.poll!;
                        final isAuthor =
                            widget.currentUserId == story.author.id;
                        return Stack(
                          children: [
                            Positioned(
                              left: (p.x.clamp(0.0, 0.9)) * cs.maxWidth,
                              top: (p.y.clamp(0.0, 0.85)) * cs.maxHeight,
                              child: StoryPollOverlay(
                                storyId: story.id,
                                poll: p,
                                readOnly: isAuthor,
                                onVoted: (updated) {
                                  // Обновляем story-state in-place чтобы вся
                                  // группа увидела новые counts без re-fetch.
                                  _updateStoryPoll(story.id, updated);
                                },
                              ),
                            ),
                          ],
                        );
                      }),
                    ),

                  // Text overlay (для photo/video сторис с подписью).
                  // Для text-сторис текст уже отрендерен внутри
                  // storyImageWidget — здесь не дублируем.
                  if (!story.isText &&
                      story.textOverlay != null &&
                      story.textOverlay!.isNotEmpty)
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 32),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius:
                              BorderRadius.circular(SeeURadii.small),
                        ),
                        child: Text(
                          story.textOverlay!,
                          style: SeeUTypography.title.copyWith(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                  // Center heart animation — по центру зоны медиа.
                  if (_showCenterHeart && _likeScaleAnim != null)
                    Center(
                      child: AnimatedBuilder(
                        animation: _likeScaleAnim!,
                        builder: (_, __) => Transform.scale(
                          scale: _likeScaleAnim!.value,
                          child: const Icon(
                            PhosphorIconsFill.heart,
                            color: SeeUColors.like,
                            size: 100,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // §03: сплошная верхняя зона (вместо градиент-скрима) — фон под
            // прогресс-барами и плашкой автора.
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _kStoryTopZoneH,
              child: ColoredBox(color: _kStoryViewerBg),
            ),

            // §03: сплошная нижняя зона (вместо градиент-скрима) — фон под
            // reply-баром и кнопками действий.
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: _kStoryBottomZoneH,
              child: ColoredBox(color: _kStoryViewerBg),
            ),

            // Progress bars (4px height)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  // Единая стеклянная панель под всеми прогресс-барами;
                  // сами 4px-бары внутри — плоские, fill акцентный.
                  child: _StoryGlassPill(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    child: Row(
                      children:
                          List.generate(group.stories.length, (i) {
                        return Expanded(
                          child: Container(
                            margin: EdgeInsets.only(
                              left: i == 0 ? 0 : 1.5,
                              right:
                                  i == group.stories.length - 1 ? 0 : 1.5,
                            ),
                            height: 3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              // §03: заполнение прогресса — БЕЛОЕ (не коралл),
                              // фон — rgba(255,255,255,.35).
                              child: i < _storyIndex
                                  ? Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(2),
                                      ),
                                    )
                                  : i == _storyIndex
                                      ? AnimatedBuilder(
                                          animation: _progressController,
                                          builder: (_, __) => Stack(
                                            children: [
                                              Container(
                                                color: Colors.white
                                                    .withValues(
                                                        alpha: 0.35),
                                              ),
                                              FractionallySizedBox(
                                                widthFactor:
                                                    Curves.easeOutQuad.transform(
                                                        _progressController.value),
                                                child: Container(
                                                  decoration:
                                                      BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius:
                                                        BorderRadius
                                                            .circular(2),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.35),
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                        ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),

            // User info header (avatar + username + time; X button is in outer Stack)
            Positioned(
              top: 0,
              left: 0,
              right: 56, // leave space for the X button in the outer stack
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.only(top: 36, left: 16, right: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _StoryGlassPill(
                      padding:
                          const EdgeInsets.fromLTRB(6, 6, 14, 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Builder(builder: (_) {
                            final initials = Container(
                              color: Colors.grey,
                              alignment: Alignment.center,
                              child: Text(
                                group.author.username.isNotEmpty
                                    ? group.author.username[0].toUpperCase()
                                    : '?',
                                style: SeeUTypography.caption
                                    .copyWith(color: Colors.white),
                              ),
                            );
                            final url = group.author.avatarUrl;
                            return ClipOval(
                              child: SizedBox(
                                width: 32,
                                height: 32,
                                child: (url != null && url.isNotEmpty)
                                    ? CachedNetworkImage(
                                        imageUrl: url,
                                        fit: BoxFit.cover,
                                        // Header avatar paints at 32 logical px.
                                        memCacheWidth: (32 *
                                                MediaQuery.devicePixelRatioOf(
                                                    context))
                                            .round(),
                                        maxWidthDiskCache: (32 *
                                                MediaQuery.devicePixelRatioOf(
                                                    context))
                                            .round(),
                                        placeholder: (_, __) => initials,
                                        errorWidget: (_, __, ___) => initials,
                                      )
                                    : initials,
                              ),
                            );
                          }),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              group.author.username,
                              style: SeeUTypography.subtitle.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '· ${formatRelativeTime(story.createdAt).toUpperCase()}',
                            style: SeeUTypography.kicker.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Music tag — Instagram-style плашка с названием трека.
            // Показывается только когда story имеет audio_track_id и трек
            // уже подгружен в кэш. До загрузки — ничего не рендерим (всё
            // равно музыка ещё не играет).
            if (story.audioTrackId != null &&
                _audioCache[story.audioTrackId] != null)
              Positioned(
                bottom: 100,
                left: 16,
                child: _StoryGlassPill(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(PhosphorIconsBold.musicNote,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        '${_audioCache[story.audioTrackId!]!.title} · '
                                '${_audioCache[story.audioTrackId!]!.artist}'
                            .toUpperCase(),
                        style: SeeUTypography.kicker.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // View count (bottom-left)
            Positioned(
              bottom: 130,
              left: 16,
              child: _StoryGlassPill(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PhosphorIcon(
                      PhosphorIcons.eye(),
                      color: Colors.white.withValues(alpha: 0.85),
                      size: 16,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${_liveViewsOverride[story.id] ?? story.viewsCount}',
                      style: SeeUTypography.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom section: viewers (own) or reply bar + like (others)
            if (!_isReplyOpen)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: isOwnStory
                        ? _buildOwnStoryBottom(story)
                        : Builder(builder: (context) {
                            // §03: поле «Ответить…» показывается ТОЛЬКО при
                            // наличии доступа к переписке (access ≠ follow).
                            // Без доступа — лишь Лайк и Поделиться.
                            final hasAccess = ref
                                .watch(accessCheckProvider(
                                    _currentGroup.author.id))
                                .maybeWhen(
                                    data: (v) => v, orElse: () => false);
                            return Row(
                              children: [
                                if (hasAccess) ...[
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: _openReply,
                                      child: Container(
                                        height: 44,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(
                                                  SeeURadii.pill),
                                          border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: 0.5),
                                            width: 1.5,
                                          ),
                                        ),
                                        padding: const EdgeInsets
                                            .symmetric(horizontal: 16),
                                        alignment:
                                            Alignment.centerLeft,
                                        child: Text(
                                          'Ответить ${_currentGroup.author.username}…',
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis,
                                          style: SeeUTypography.body
                                              .copyWith(
                                            color: Colors.white
                                                .withValues(alpha: 0.7),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ] else
                                  const Spacer(),
                                GestureDetector(
                                  onTap: _toggleLike,
                                  child: AnimatedBuilder(
                                    animation: _heartBtnScaleAnim!,
                                    builder: (_, child) =>
                                        Transform.scale(
                                      scale:
                                          _heartBtnScaleAnim!.value,
                                      child: child,
                                    ),
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.14),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isLiked
                                            ? PhosphorIconsFill.heart
                                            : PhosphorIconsRegular
                                                .heart,
                                        color: isLiked
                                            ? SeeUColors.like
                                            : Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                GestureDetector(
                                  onTap: () => _shareStory(story),
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Colors.white
                                          .withValues(alpha: 0.14),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      PhosphorIconsRegular.shareFat,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }),
                  ),
                ),
              ),

            // Reply text field overlay
            if (_isReplyOpen)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                // Стеклянный reply-бар вместо плоского чёрного оверлея:
                // blur + светлый градиент → тёмный тинт + hairline сверху.
                child: ClipRect(
                  child: BackdropFilter(
                    filter:
                        ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.14),
                            Colors.black.withValues(alpha: 0.28),
                          ],
                        ),
                        border: Border(
                          top: BorderSide(
                            color:
                                Colors.white.withValues(alpha: 0.18),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _replyController,
                              focusNode: _replyFocusNode,
                              autofocus: true,
                              style: SeeUTypography.body.copyWith(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                              cursorColor: SeeUColors.accent,
                              decoration: InputDecoration(
                                hintText: 'Ответить...',
                                hintStyle:
                                    SeeUTypography.body.copyWith(
                                  color: Colors.white54,
                                  fontSize: 15,
                                ),
                                filled: true,
                                fillColor: Colors.white
                                    .withValues(alpha: 0.10),
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                          SeeURadii.pill),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                          SeeURadii.pill),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                          SeeURadii.pill),
                                  borderSide: const BorderSide(
                                    color: SeeUColors.accent,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              textInputAction:
                                  TextInputAction.send,
                              onSubmitted: (_) => _sendReply(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Кнопка отправки слушает ТОЛЬКО контроллер поля —
                          // раньше на каждый символ вызывался setState всего
                          // вьюера (blur-оверлеи + прогрессбары), заметный
                          // джанк при наборе.
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _replyController,
                            builder: (_, value, __) {
                              final hasText =
                                  value.text.trim().isNotEmpty;
                              return AnimatedOpacity(
                                opacity: hasText ? 1.0 : 0.4,
                                duration:
                                    const Duration(milliseconds: 150),
                                child: GestureDetector(
                                  onTap: _sendReply,
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: hasText
                                          ? SeeUColors.accent
                                          : Colors.white.withValues(
                                              alpha: 0.10),
                                      border: hasText
                                          ? null
                                          : Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.22),
                                              width: 0.8,
                                            ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        PhosphorIconsRegular
                                            .paperPlaneTilt,
                                        color: Colors.white,
                                        size: 20,
                                      ),
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
                    ),
                  ),
                ),
              ),
          ],
          ),
          ),
          // Top-right controls — always work, above everything. Своя история:
          // «три точки» (управление: удалить/закрыть) + крестик; чужая —
          // только крестик.
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 36, right: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isOwnStory) ...[
                      SeeUGlassCircleButton(
                        size: 38,
                        icon: const PhosphorIcon(
                            PhosphorIconsRegular.dotsThreeOutline,
                            color: Colors.white,
                            size: 20),
                        onTap: () => _openOwnStoryOptions(story),
                      ),
                      const SizedBox(width: 10),
                    ],
                    SeeUGlassCircleButton(
                      size: 38,
                      icon: PhosphorIcon(PhosphorIcons.x(),
                          color: Colors.white, size: 20),
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

