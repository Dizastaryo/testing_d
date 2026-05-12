import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/audio_track.dart';
import '../providers/realtime_provider.dart';

/// Один процесс — один [AudioPlayer]. Живёт за provider'ом и переживает любые
/// навигации между screens, поэтому музыка играет, пока юзер ходит по фиду /
/// сторис / профилям. Music screen перестаёт владеть собственным плеером —
/// дёргает этот сервис.
class AudioPlayerService {
  AudioPlayerService() : _player = AudioPlayer();

  final AudioPlayer _player;

  AudioPlayer get raw => _player;

  AudioTrack? _current;
  AudioTrack? get current => _current;

  Stream<bool> get playingStream => _player.playingStream;
  Stream<Duration?> get positionStream => _player.positionStream.map((p) => p);
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;

  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;

  Future<void> playTrack(AudioTrack track) async {
    if (_current?.id == track.id) {
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
      return;
    }
    _current = track;
    await _player.setUrl(track.audioUrl);
    await _player.play();
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_current != null) await _player.play();
    }
  }

  Future<void> seek(Duration pos) => _player.seek(pos);

  Future<void> stop() async {
    await _player.stop();
    _current = null;
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}

/// Singleton-провайдер аудио-сервиса. Никогда не должен пересоздаваться —
/// тогда плеер потеряет state. Поэтому его хранит [Provider], не [StateProvider].
final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  final s = AudioPlayerService();
  ref.onDispose(s.dispose);
  return s;
});

/// State для UI. [AudioTrack?] currentTrack меняется когда юзер переключает
/// трек, [bool] playing — реактивный sync с реальным плеером.
class MiniPlayerState {
  final AudioTrack? track;
  final bool playing;
  final Duration position;
  final Duration? duration;

  const MiniPlayerState({
    this.track,
    this.playing = false,
    this.position = Duration.zero,
    this.duration,
  });

  MiniPlayerState copyWith({
    AudioTrack? track,
    bool? clearTrack,
    bool? playing,
    Duration? position,
    Duration? duration,
    bool? clearDuration,
  }) {
    return MiniPlayerState(
      track: (clearTrack ?? false) ? null : (track ?? this.track),
      playing: playing ?? this.playing,
      position: position ?? this.position,
      duration:
          (clearDuration ?? false) ? null : (duration ?? this.duration),
    );
  }
}

class MiniPlayerNotifier extends StateNotifier<MiniPlayerState> {
  MiniPlayerNotifier(this._service, this._ref) : super(const MiniPlayerState()) {
    _service.playingStream.listen((p) {
      state = state.copyWith(playing: p);
      // MUSIC-1: при pause шлём music.stopped — followers убирают нас из
      // «Слушают сейчас» секции без ожидания TTL.
      if (!p && state.track != null) {
        _ref.read(realtimeSenderProvider).send('music.stopped', {});
      }
    });
    _service.positionStream.listen((p) {
      state = state.copyWith(position: p ?? Duration.zero);
    });
    _service.durationStream.listen((d) {
      state = state.copyWith(duration: d);
    });
  }

  final AudioPlayerService _service;
  final Ref _ref;

  Future<void> play(AudioTrack track) async {
    state = state.copyWith(track: track);
    await _service.playTrack(track);
    // MUSIC-1: фан-аут к followers — backend обогатит payload title/artist.
    _ref.read(realtimeSenderProvider).send('music.now_playing', {
      'track_id': track.id,
    });
    // MUSIC-3: record play для smart-playlists (Recent + Daily Mix).
    // Fire-and-forget; ошибки не прерывают воспроизведение.
    try {
      await _ref
          .read(apiClientProvider)
          .post(ApiEndpoints.audioTrackPlay(track.id));
    } catch (_) {}
  }

  Future<void> toggle() => _service.togglePlayPause();
  Future<void> seek(Duration p) => _service.seek(p);

  Future<void> close() async {
    await _service.stop();
    state = state.copyWith(clearTrack: true, clearDuration: true);
    _ref.read(realtimeSenderProvider).send('music.stopped', {});
  }
}

final miniPlayerProvider =
    StateNotifierProvider<MiniPlayerNotifier, MiniPlayerState>((ref) {
  return MiniPlayerNotifier(ref.watch(audioPlayerServiceProvider), ref);
});

/// MUSIC-1: «слушают сейчас» — snapshot `Map<userId, NowPlayingInfo>`.
/// Subscribe в music-screen; auto-GC через 90с (если друг перестал слать).
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

  NowPlayingFriendsNotifier(this._ref) : super(const {}) {
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
          // GC старых entries (TTL).
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
    _sub?.close();
    super.dispose();
  }
}
