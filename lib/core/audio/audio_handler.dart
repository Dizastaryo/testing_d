import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../models/audio_track.dart';

/// Singleton handler kept here so AudioPlayerService can reference it
/// without relying on AudioService.handler (not available in 0.18.x).
SeeUAudioHandler? _instance;
SeeUAudioHandler get audioHandlerInstance => _instance!;

/// Initialise the audio service once at app startup (before runApp).
Future<SeeUAudioHandler> initAudioHandler() async {
  _instance = await AudioService.init<SeeUAudioHandler>(
    builder: () => SeeUAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.my_app.channel.audio',
      androidNotificationChannelName: 'SeeU Музыка',
      androidNotificationOngoing: true,
      androidShowNotificationBadge: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );
  return _instance!;
}

class SeeUAudioHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();

  /// The whole play queue lives in a single source so just_audio can
  /// preload / cross-fade the next track → gapless auto-advance.
  ConcatenatingAudioSource? _playlist;

  /// Track ids in current playback order — mirror of [_playlist] children,
  /// used to compute gapless reorder (shuffle on/off) via move ops.
  final List<String> _trackOrder = [];

  /// True while a gapless [reorder] (drag / shuffle toggle) is applying its
  /// `move` ops. just_audio's currentIndexStream emits intermediate indices
  /// during those moves; consumers must ignore them so they don't announce a
  /// "now playing" for a track that isn't actually current.
  bool _reordering = false;
  bool get isReordering => _reordering;

  /// Wired by MiniPlayerNotifier so lock-screen / headphone buttons
  /// can trigger queue navigation managed in Riverpod.
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;

  SeeUAudioHandler() {
    _configureSession();
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    // Surface the currently-playing item to the OS media session so the
    // lock-screen / notification cover+title follow auto-advance.
    _player.currentIndexStream.listen((index) {
      final q = queue.value;
      if (index != null && index >= 0 && index < q.length) {
        mediaItem.add(q[index]);
      }
    });
  }

  // ── Public API called by AudioPlayerService ───────────────────────────────

  /// Replace the whole queue and start playing [initialIndex]. This is the
  /// gapless path: the entire queue is one ConcatenatingAudioSource.
  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int initialIndex = 0,
    double speed = 1.0,
    LoopMode loopMode = LoopMode.off,
  }) async {
    if (tracks.isEmpty) return;
    final items = tracks.map(_mediaItemFor).toList();
    queue.add(items);
    _trackOrder
      ..clear()
      ..addAll(tracks.map((t) => t.id));
    _playlist = ConcatenatingAudioSource(
      children: tracks.map(_sourceFor).toList(),
    );
    final idx = initialIndex.clamp(0, tracks.length - 1);
    // Push the active item up-front: currentIndexStream does not re-emit when a
    // new source starts at the same index, which would otherwise leave the OS
    // media session showing the previous track.
    mediaItem.add(items[idx]);
    await _player.setLoopMode(loopMode);
    await _player.setAudioSource(
      _playlist!,
      initialIndex: idx,
      initialPosition: Duration.zero,
    );
    await _player.setSpeed(speed);
    await _player.play();
  }

  /// Append a track to the live queue — gapless, no playback interruption.
  Future<void> addToQueue(AudioTrack track) async {
    if (_playlist == null) {
      await setQueue(
        [track],
        speed: _player.speed,
        loopMode: _player.loopMode,
      );
      return;
    }
    await _playlist!.add(_sourceFor(track));
    _trackOrder.add(track.id);
    queue.add([...queue.value, _mediaItemFor(track)]);
  }

  /// Reorder the live queue to match [targetIds] using in-place move
  /// operations so the currently-playing track keeps playing without a gap.
  Future<void> reorder(List<String> targetIds) async {
    if (_playlist == null) return;
    _reordering = true;
    try {
      final current = List<String>.from(_trackOrder);
      for (var i = 0; i < targetIds.length && i < current.length; i++) {
        if (current[i] == targetIds[i]) continue;
        final from = current.indexOf(targetIds[i], i);
        if (from <= i) continue;
        await _playlist!.move(from, i);
        final v = current.removeAt(from);
        current.insert(i, v);
      }
      _trackOrder
        ..clear()
        ..addAll(current);
      final byId = {for (final m in queue.value) m.id: m};
      queue.add([for (final id in _trackOrder) if (byId[id] != null) byId[id]!]);
    } finally {
      _reordering = false;
    }
  }

  /// Убрать трек из живой очереди. Нужен настоящий remove: [reorder] только
  /// переставляет, и «удалённый» трек всё равно доиграл бы свою очередь.
  Future<void> removeAt(int index) async {
    if (_playlist == null) return;
    if (index < 0 || index >= _trackOrder.length) return;
    _reordering = true;
    try {
      await _playlist!.removeAt(index);
      _trackOrder.removeAt(index);
      final items = List<MediaItem>.from(queue.value)..removeAt(index);
      queue.add(items);
    } finally {
      _reordering = false;
    }
  }

  /// Отрезать хвост очереди, начиная с [from]. Играющий трек не трогаем.
  Future<void> removeRange(int from) async {
    if (_playlist == null) return;
    if (from < 0 || from >= _trackOrder.length) return;
    _reordering = true;
    try {
      await _playlist!.removeRange(from, _trackOrder.length);
      _trackOrder.removeRange(from, _trackOrder.length);
      final items = List<MediaItem>.from(queue.value)
        ..removeRange(from, queue.value.length);
      queue.add(items);
    } finally {
      _reordering = false;
    }
  }

  Future<void> seekToIndex(int index) async {
    await _player.seek(Duration.zero, index: index);
  }

  Future<void> seekToNext() => _player.seekToNext();
  Future<void> seekToPrevious() => _player.seekToPrevious();

  Future<void> setLoopMode(LoopMode mode) => _player.setLoopMode(mode);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  // ── BaseAudioHandler overrides ────────────────────────────────────────────

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (onSkipToNext != null) {
      await onSkipToNext!.call();
    } else {
      await _player.seekToNext();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (onSkipToPrevious != null) {
      await onSkipToPrevious!.call();
    } else {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) => seekToIndex(index);

  @override
  Future<void> stop() async {
    await _player.stop();
    _playlist = null;
    _trackOrder.clear();
    queue.add(const []);
    mediaItem.add(null);
    await super.stop();
  }

  // ── Streams / state forwarded to AudioPlayerService ──────────────────────

  Stream<bool> get playingStream => _player.playingStream;
  Stream<Duration?> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;
  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  double get speed => _player.speed;

  // ── Private helpers ───────────────────────────────────────────────────────

  AudioSource _sourceFor(AudioTrack track) {
    final url =
        track.playbackUrl.isNotEmpty ? track.playbackUrl : track.audioUrl;
    return AudioSource.uri(Uri.parse(url), tag: _mediaItemFor(track));
  }

  MediaItem _mediaItemFor(AudioTrack track) => MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist.isNotEmpty ? track.artist : 'SeeU',
        artUri: track.coverUrl.isNotEmpty ? Uri.tryParse(track.coverUrl) : null,
        duration: track.durationSeconds > 0
            ? Duration(seconds: track.durationSeconds)
            : null,
      );

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }

  Future<void> _configureSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}
  }
}
