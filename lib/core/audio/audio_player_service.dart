import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/audio_track.dart';
import '../providers/audio_provider.dart';
import '../../features/music/audio_design.dart';
import '../providers/realtime_provider.dart';
import 'audio_handler.dart';

/// Thin wrapper over [SeeUAudioHandler] that preserves the same public API
/// that the rest of the app depended on. The handler drives both playback
/// and the OS media session (lock screen, notification, headphone buttons).
class AudioPlayerService {
  AudioPlayerService() : _handler = audioHandlerInstance;

  final SeeUAudioHandler _handler;

  AudioTrack? _current;
  AudioTrack? get current => _current;

  Stream<bool> get playingStream => _handler.playingStream;
  Stream<Duration?> get positionStream => _handler.positionStream;
  Stream<Duration?> get durationStream => _handler.durationStream;
  Stream<ProcessingState> get processingStateStream =>
      _handler.processingStateStream;

  Stream<int?> get currentIndexStream => _handler.currentIndexStream;

  bool get isReordering => _handler.isReordering;

  bool get isPlaying => _handler.isPlaying;
  Duration get position => _handler.position;
  Duration? get duration => _handler.duration;
  double get speed => _handler.speed;

  /// Load [tracks] as one gapless source and start at [initialIndex].
  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int initialIndex = 0,
    double speed = 1.0,
    LoopMode loopMode = LoopMode.off,
  }) async {
    _current = tracks.isEmpty ? null : tracks[initialIndex.clamp(0, tracks.length - 1)];
    await _handler.setQueue(
      tracks,
      initialIndex: initialIndex,
      speed: speed,
      loopMode: loopMode,
    );
  }

  Future<void> addToQueue(AudioTrack track) => _handler.addToQueue(track);
  Future<void> reorder(List<String> targetIds) => _handler.reorder(targetIds);
  Future<void> removeAt(int index) => _handler.removeAt(index);
  Future<void> removeRange(int from) => _handler.removeRange(from);
  Future<void> seekToIndex(int index) => _handler.seekToIndex(index);
  Future<void> seekToNext() => _handler.seekToNext();
  Future<void> seekToPrevious() => _handler.seekToPrevious();
  Future<void> setLoopMode(LoopMode mode) => _handler.setLoopMode(mode);
  Future<void> setSpeed(double s) => _handler.setSpeed(s);

  Future<void> togglePlayPause() async {
    if (_handler.isPlaying) {
      await _handler.pause();
    } else {
      if (_current != null) await _handler.play();
    }
  }

  Future<void> seek(Duration pos) => _handler.seek(pos);

  Future<void> stop() async {
    await _handler.stop();
    _current = null;
  }

  Future<void> dispose() async {
    // Handler lifetime is managed by AudioService — do not dispose it here.
  }
}

final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  final s = AudioPlayerService();
  ref.onDispose(s.dispose);
  return s;
});

// ── Queue-aware player state ──────────────────────────────────────────────────

/// Repeat behaviour, mapped 1:1 onto just_audio [LoopMode].
enum PlayerRepeatMode { off, all, one }

class MiniPlayerState {
  final AudioTrack? track;
  final bool playing;
  final Duration position;
  final Duration? duration;

  // Queue context — empty list means no queue (single-track mode).
  final List<AudioTrack> queue;
  final int queueIndex;
  final String queueSource; // feed | playlist | saved | recent | trending | detail

  // Playback modes (persisted in player state).
  final bool shuffle;
  final PlayerRepeatMode repeat;
  final double speed;

  /// Original (unshuffled) queue order, captured when shuffle is enabled so
  /// that toggling shuffle off can restore the exact previous ordering.
  final List<AudioTrack> originalQueue;

  const MiniPlayerState({
    this.track,
    this.playing = false,
    this.position = Duration.zero,
    this.duration,
    this.queue = const [],
    this.queueIndex = 0,
    this.queueSource = 'feed',
    this.shuffle = false,
    this.repeat = PlayerRepeatMode.off,
    this.speed = 1.0,
    this.originalQueue = const [],
  });

  bool get hasQueue => queue.length > 1;
  bool get hasNext =>
      repeat == PlayerRepeatMode.all ? queue.length > 1 : queueIndex < queue.length - 1;
  bool get hasPrev =>
      repeat == PlayerRepeatMode.all ? queue.length > 1 : queueIndex > 0;

  MiniPlayerState copyWith({
    AudioTrack? track,
    bool? clearTrack,
    bool? playing,
    Duration? position,
    Duration? duration,
    bool? clearDuration,
    List<AudioTrack>? queue,
    int? queueIndex,
    String? queueSource,
    bool? shuffle,
    PlayerRepeatMode? repeat,
    double? speed,
    List<AudioTrack>? originalQueue,
  }) {
    return MiniPlayerState(
      track: (clearTrack ?? false) ? null : (track ?? this.track),
      playing: playing ?? this.playing,
      position: position ?? this.position,
      duration: (clearDuration ?? false) ? null : (duration ?? this.duration),
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
      queueSource: queueSource ?? this.queueSource,
      shuffle: shuffle ?? this.shuffle,
      repeat: repeat ?? this.repeat,
      speed: speed ?? this.speed,
      originalQueue: originalQueue ?? this.originalQueue,
    );
  }
}

class MiniPlayerNotifier extends StateNotifier<MiniPlayerState> {
  MiniPlayerNotifier(this._service, this._ref) : super(const MiniPlayerState()) {
    // Wire lock-screen / headphone skip buttons back into Riverpod queue.
    audioHandlerInstance.onSkipToNext = () => next();
    audioHandlerInstance.onSkipToPrevious = () => previous();

    _subs.add(_service.playingStream.listen((p) {
      state = state.copyWith(playing: p);
      final t = state.track;
      if (t == null) return;
      if (p) {
        // Resume → re-announce presence (a prior pause cleared it for friends).
        _stoppedTimer?.cancel();
        _sendNowPlaying(t);
      } else {
        // Debounce stop: a brief pause during a seek shouldn't spam "stopped".
        _stoppedTimer?.cancel();
        _stoppedTimer = Timer(const Duration(milliseconds: 600), () {
          _ref.read(realtimeSenderProvider).send('music.stopped', {});
          // Presence was cleared for friends — allow the next resume of this
          // same track to re-announce now-playing.
          _lastNowPlayingTrackId = null;
        });
      }
    }));
    _subs.add(_service.positionStream.listen((p) {
      state = state.copyWith(position: p ?? Duration.zero);
      _maybeSavePosition();
    }));
    _subs.add(_service.durationStream.listen((d) {
      state = state.copyWith(duration: d);
    }));
    // just_audio drives auto-advance natively via the ConcatenatingAudioSource
    // (gapless preload). We follow the active index to keep Riverpod state,
    // realtime "now playing", and play-recording in sync.
    _subs.add(_service.currentIndexStream.listen(_onIndexChanged));
  }

  final AudioPlayerService _service;
  final Ref _ref;

  final List<StreamSubscription> _subs = [];
  Timer? _stoppedTimer;

  /// Когда в последний раз отправили позицию на сервер.
  DateTime? _lastPositionSave;

  /// Позиция сохраняется только у того, что имеет смысл продолжать: у книги и
  /// подкаста. Песню никто не «дослушивает с 1:07», а трёхсекундный мем — тем
  /// более. Пишем раз в 10 секунд, чтобы не долбить сервер на каждый тик.
  void _maybeSavePosition() {
    final t = state.track;
    if (t == null || !state.playing) return;
    if (!modeOf(t).resumable) return;
    if (t.durationSeconds <= 0) return;

    final now = DateTime.now();
    if (_lastPositionSave != null &&
        now.difference(_lastPositionSave!) < const Duration(seconds: 10)) {
      return;
    }
    _lastPositionSave = now;
    _flushPosition(t);
  }

  void _flushPosition(AudioTrack t) {
    final pos = state.position.inSeconds;
    final dur = state.duration?.inSeconds ?? t.durationSeconds;
    if (dur <= 0) return;

    // Дослушал почти до конца — помечаем завершённым, иначе трек навсегда
    // застрянет в «Продолжить» с надписью «осталось меньше минуты».
    final completed = dur - pos <= 15;

    saveAudioPosition(
      _ref.read(apiClientProvider),
      trackId: t.id,
      positionSeconds: pos,
      durationSeconds: dur,
      completed: completed,
    );
  }

  /// Продолжить с того места, где остановился. Зовётся при запуске книги или
  /// подкаста — песня всегда начинается сначала.
  Future<void> _restorePosition(AudioTrack track) async {
    if (!modeOf(track).resumable) return;
    final saved = await fetchAudioPosition(_ref.read(apiClientProvider), track.id);
    if (saved <= 5) return;
    // Трек могли перезалить короче — не прыгаем за конец.
    if (track.durationSeconds > 0 && saved >= track.durationSeconds - 10) return;
    await seek(Duration(seconds: saved));
  }

  @override
  void dispose() {
    // Уходим — записываем, где остановились, иначе последние минуты потеряются.
    final t = state.track;
    if (t != null && modeOf(t).resumable) _flushPosition(t);
    _stoppedTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  String? _lastRecordedTrackId;
  String? _lastNowPlayingTrackId;

  /// Play a single track (queue of one).
  Future<void> play(AudioTrack track) async {
    await playWithQueue(track: track, queue: [track], index: 0, source: 'feed');
  }

  /// Play a track from a queue. Pass the full list and the index of [track].
  Future<void> playWithQueue({
    required AudioTrack track,
    required List<AudioTrack> queue,
    required int index,
    String source = 'feed',
  }) async {
    // Tapping the already-playing track toggles play/pause instead of
    // rebuilding the source (avoids an audible restart).
    if (state.track?.id == track.id && state.queue.isNotEmpty) {
      await toggle();
      return;
    }
    final list = queue.isEmpty ? [track] : queue;
    final idx = index.clamp(0, list.length - 1);
    state = state.copyWith(
      track: track,
      queue: list,
      originalQueue: list,
      queueIndex: idx,
      queueSource: source,
      shuffle: false,
    );
    await _service.setQueue(
      list,
      initialIndex: idx,
      speed: state.speed,
      loopMode: _loopFor(state.repeat),
    );
    // just_audio's currentIndexStream does NOT re-emit when a fresh source
    // starts at the same index (e.g. 0 → 0), so announce the initial track
    // explicitly here. _onIndexChanged handles subsequent auto-advances; the
    // dedupe in _announce prevents a double record if the stream does emit.
    _announce(track, source);

    // Книгу и подкаст продолжаем с того места, где остановились.
    _lastPositionSave = null;
    await _restorePosition(track);
  }

  /// Append [track] to the live queue (and original order) without interrupting.
  Future<void> addToQueue(AudioTrack track) async {
    if (state.queue.isEmpty || state.track == null) {
      await playWithQueue(track: track, queue: [track], index: 0, source: state.queueSource);
      return;
    }
    // A track can't appear twice — queue widget keys (ValueKey(id)) and reorder
    // matching both rely on unique ids.
    if (state.queue.any((t) => t.id == track.id)) return;
    state = state.copyWith(
      queue: [...state.queue, track],
      originalQueue: [...state.originalQueue, track],
    );
    await _service.addToQueue(track);
  }

  /// Jump to [index] in the current queue.
  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    await _service.seekToIndex(index);
  }

  /// Manually reorder the queue (drag in the queue sheet). Gapless.
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= state.queue.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0 || target >= state.queue.length) return;
    if (target == oldIndex) return;
    final list = List<AudioTrack>.from(state.queue);
    final moved = list.removeAt(oldIndex);
    list.insert(target, moved);
    final currentIdx = state.track == null
        ? state.queueIndex
        : list.indexWhere((t) => t.id == state.track!.id);
    state = state.copyWith(
      queue: list,
      queueIndex: currentIdx < 0 ? 0 : currentIdx,
      originalQueue: state.shuffle ? state.originalQueue : list,
    );
    await _service.reorder(list.map((t) => t.id).toList());
  }

  /// Убрать трек из очереди. Играющий убрать нельзя — для этого есть «дальше»
  /// и закрытие плеера.
  Future<void> removeFromQueue(int index) async {
    if (index <= state.queueIndex || index >= state.queue.length) return;
    final removedId = state.queue[index].id;
    await _service.removeAt(index);
    final list = List<AudioTrack>.from(state.queue)..removeAt(index);
    state = state.copyWith(
      queue: list,
      // Убранный трек надо выкинуть и из originalQueue, иначе при выключении
      // shuffle он «воскреснет» — а в источнике плеера его уже нет, и очередь
      // рассинхронится (фантомный трек, кривой индекс, битый now-playing).
      originalQueue: state.shuffle
          ? state.originalQueue.where((t) => t.id != removedId).toList()
          : list,
    );
  }

  /// «Очистить» в очереди: отрезаем всё, что после текущего трека. Сам трек
  /// продолжает играть — обрывать звук на кнопке «очистить» было бы грубо.
  Future<void> clearUpcoming() async {
    if (state.queue.length <= state.queueIndex + 1) return;
    await _service.removeRange(state.queueIndex + 1);
    final list = state.queue.sublist(0, state.queueIndex + 1);
    state = state.copyWith(
      queue: list,
      // Как и в removeFromQueue: подрезаем originalQueue до реально оставшихся
      // треков, иначе выключение shuffle вернёт отрезанные (их нет в источнике).
      originalQueue: state.shuffle
          ? state.originalQueue.where((t) => list.any((k) => k.id == t.id)).toList()
          : list,
    );
  }

  Future<void> next() async {
    if (!state.hasNext) return;
    await _service.seekToNext();
  }

  Future<void> previous() async {
    // Standard music-app behaviour: restart current track if we are >3s in,
    // otherwise step to the previous track.
    if (_service.position > const Duration(seconds: 3)) {
      await _service.seek(Duration.zero);
      return;
    }
    if (!state.hasPrev) {
      await _service.seek(Duration.zero);
      return;
    }
    await _service.seekToPrevious();
  }

  /// Toggle shuffle. On: keep the current track, Fisher–Yates the rest.
  /// Off: restore the original captured order. Both are gapless (move ops).
  Future<void> toggleShuffle() async {
    final current = state.track;
    if (!state.shuffle) {
      final original = List<AudioTrack>.from(state.queue);
      final rest = original.where((t) => t.id != current?.id).toList();
      _fisherYates(rest);
      final newQueue = <AudioTrack>[if (current != null) current, ...rest];
      state = state.copyWith(
        shuffle: true,
        originalQueue: original,
        queue: newQueue,
        queueIndex: 0,
      );
      await _service.reorder(newQueue.map((t) => t.id).toList());
    } else {
      final original =
          state.originalQueue.isNotEmpty ? state.originalQueue : state.queue;
      final restored = List<AudioTrack>.from(original);
      final idx = current == null
          ? 0
          : restored.indexWhere((t) => t.id == current.id);
      state = state.copyWith(
        shuffle: false,
        queue: restored,
        queueIndex: idx < 0 ? 0 : idx,
      );
      await _service.reorder(restored.map((t) => t.id).toList());
    }
  }

  /// Cycle repeat off → all → one → off and apply to just_audio.
  Future<void> cycleRepeat() async {
    final next = switch (state.repeat) {
      PlayerRepeatMode.off => PlayerRepeatMode.all,
      PlayerRepeatMode.all => PlayerRepeatMode.one,
      PlayerRepeatMode.one => PlayerRepeatMode.off,
    };
    state = state.copyWith(repeat: next);
    await _service.setLoopMode(_loopFor(next));
  }

  Future<void> setSpeed(double s) async {
    state = state.copyWith(speed: s);
    await _service.setSpeed(s);
  }

  LoopMode _loopFor(PlayerRepeatMode m) => switch (m) {
        PlayerRepeatMode.off => LoopMode.off,
        PlayerRepeatMode.all => LoopMode.all,
        PlayerRepeatMode.one => LoopMode.one,
      };

  void _fisherYates<T>(List<T> list) {
    final rnd = Random();
    for (var i = list.length - 1; i > 0; i--) {
      final j = rnd.nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }

  void _onIndexChanged(int? index) {
    if (index == null) return;
    // During a reorder/shuffle, just_audio emits intermediate indices while the
    // `move` ops apply. state.queue is already in its final order, so mapping
    // those indices here would point at the wrong track → spurious play-records
    // and a wrong now_playing. The notifier has already set the correct track,
    // so skip these transient emits entirely.
    if (_service.isReordering) return;
    final q = state.queue;
    if (index < 0 || index >= q.length) return;
    final t = q[index];
    state = state.copyWith(track: t, queueIndex: index);
    _announce(t, state.queueSource);
    // Автопереход к следующей книге/подкасту тоже должен продолжаться с
    // сохранённого места — раньше _restorePosition звался только для первого
    // тапнутого трека, и все последующие resumable начинались с 0:00.
    if (modeOf(t).resumable) {
      _lastPositionSave = null;
      _restorePosition(t);
    }
  }

  /// Record the play (deduped) + broadcast now-playing for a track change.
  void _announce(AudioTrack track, String source) {
    _sendNowPlaying(track);
    _recordPlay(track.id, source);
  }

  /// Always broadcast the full now-playing payload so friend cards can render
  /// title/artist/cover (NowPlayingFriendsNotifier reads these fields).
  ///
  /// Deduped per track start: on first play both `playWithQueue` and the
  /// `currentIndexStream` → `_onIndexChanged` path call `_announce`, which would
  /// otherwise emit two identical frames. A pause (which broadcasts
  /// `music.stopped`) clears `_lastNowPlayingTrackId`, so resuming the same
  /// track legitimately re-announces presence to friends.
  void _sendNowPlaying(AudioTrack track) {
    if (_lastNowPlayingTrackId == track.id) return;
    _lastNowPlayingTrackId = track.id;
    _ref.read(realtimeSenderProvider).send('music.now_playing', {
      'track_id': track.id,
      'title': track.title,
      'artist': track.displayArtist,
      'cover_url': track.coverUrl,
    });
  }

  Future<void> toggle() => _service.togglePlayPause();

  /// Просто остановить, не закрывая плеер — таймер сна и системная пауза.
  Future<void> pause() async {
    if (state.playing) await _service.togglePlayPause();
  }

  Future<void> seek(Duration p) => _service.seek(p);

  Future<void> close() async {
    _stoppedTimer?.cancel();
    // Осознанное закрытие книги/подкаста должно сохранить последнюю позицию —
    // позиции пишутся раз в 10с, и без этого потеряется до ~10с, а у самого
    // конца — не проставится «дослушано». Симметрично dispose().
    final t = state.track;
    if (t != null && modeOf(t).resumable) _flushPosition(t);
    // Reset the play-record + now-playing dedupe so re-playing the same track
    // after a Стоп records the play and re-announces presence again.
    _lastRecordedTrackId = null;
    _lastNowPlayingTrackId = null;
    await _service.stop();
    state = state.copyWith(
      clearTrack: true,
      clearDuration: true,
      queue: const [],
      originalQueue: const [],
      queueIndex: 0,
      shuffle: false,
    );
    _ref.read(realtimeSenderProvider).send('music.stopped', {});
  }

  void setCurrentLiked(bool liked) {
    final t = state.track;
    if (t == null) return;
    state = state.copyWith(track: t.copyWith(isLikedByMe: liked));
  }

  void setCurrentSaved(bool saved) {
    final t = state.track;
    if (t == null) return;
    state = state.copyWith(track: t.copyWith(isSavedByMe: saved));
  }

  void _recordPlay(String trackId, String source) {
    if (_lastRecordedTrackId == trackId) return;
    _lastRecordedTrackId = trackId;
    _ref.read(apiClientProvider).post(
      ApiEndpoints.audioTrackPlay(trackId),
      data: {'source': source},
    ).ignore();
  }
}

final miniPlayerProvider =
    StateNotifierProvider<MiniPlayerNotifier, MiniPlayerState>((ref) {
  return MiniPlayerNotifier(ref.watch(audioPlayerServiceProvider), ref);
});

// ── "Слушают сейчас" (MUSIC-1) ────────────────────────────────────────────────

class NowPlayingInfo {
  final String userId;
  final String trackId;
  final String title;
  final String artist;
  final String coverUrl;
  final DateTime since;
  const NowPlayingInfo({
    required this.userId,
    required this.trackId,
    required this.title,
    required this.artist,
    required this.coverUrl,
    required this.since,
  });
}

final nowPlayingFriendsProvider =
    StateNotifierProvider<NowPlayingFriendsNotifier, Map<String, NowPlayingInfo>>(
        (ref) => NowPlayingFriendsNotifier(ref));

class NowPlayingFriendsNotifier
    extends StateNotifier<Map<String, NowPlayingInfo>> {
  static const _ttl = Duration(seconds: 90);
  final Ref _ref;
  ProviderSubscription<AsyncValue<RealtimeEvent>>? _sub;
  Timer? _pruneTimer;

  NowPlayingFriendsNotifier(this._ref) : super(const {}) {
    // Прунинг по TTL раньше жил только внутри listener'а — если друг замолчал
    // и его `music.stopped` потерялся, а новых realtime-событий нет, его
    // карточка «слушает сейчас» висела вечно. Периодический таймер её убирает.
    _pruneTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final cutoff = DateTime.now().subtract(_ttl);
      final filtered = <String, NowPlayingInfo>{};
      var changed = false;
      state.forEach((k, v) {
        if (v.since.isAfter(cutoff)) {
          filtered[k] = v;
        } else {
          changed = true;
        }
      });
      if (changed) state = filtered;
    });
    _sub = _ref.listen<AsyncValue<RealtimeEvent>>(
      realtimeEventsProvider,
      (_, next) {
        next.whenData((evt) {
          if (evt.payload is! Map) return;
          final p = (evt.payload as Map).cast<String, dynamic>();
          final uid = p['from_user_id']?.toString() ?? '';
          if (uid.isEmpty) return;
          if (evt.type == 'music.now_playing') {
            final info = NowPlayingInfo(
              userId: uid,
              trackId: p['track_id']?.toString() ?? '',
              title: p['title']?.toString() ?? '',
              artist: p['artist']?.toString() ?? '',
              coverUrl: p['cover_url']?.toString() ?? '',
              since: DateTime.now(),
            );
            state = {...state, uid: info};
          } else if (evt.type == 'music.stopped') {
            if (state.containsKey(uid)) {
              final next = Map<String, NowPlayingInfo>.from(state);
              next.remove(uid);
              state = next;
            }
          }
          final cutoff = DateTime.now().subtract(_ttl);
          final filtered = <String, NowPlayingInfo>{};
          var changed = false;
          state.forEach((k, v) {
            if (v.since.isAfter(cutoff)) {
              filtered[k] = v;
            } else {
              changed = true;
            }
          });
          if (changed) state = filtered;
        });
      },
    );
  }

  @override
  void dispose() {
    _pruneTimer?.cancel();
    _sub?.close();
    super.dispose();
  }
}
