import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../models/audio_track.dart';

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
  MiniPlayerNotifier(this._service) : super(const MiniPlayerState()) {
    _service.playingStream.listen((p) {
      state = state.copyWith(playing: p);
    });
    _service.positionStream.listen((p) {
      state = state.copyWith(position: p ?? Duration.zero);
    });
    _service.durationStream.listen((d) {
      state = state.copyWith(duration: d);
    });
  }

  final AudioPlayerService _service;

  Future<void> play(AudioTrack track) async {
    state = state.copyWith(track: track);
    await _service.playTrack(track);
  }

  Future<void> toggle() => _service.togglePlayPause();
  Future<void> seek(Duration p) => _service.seek(p);

  Future<void> close() async {
    await _service.stop();
    state = state.copyWith(clearTrack: true, clearDuration: true);
  }
}

final miniPlayerProvider =
    StateNotifierProvider<MiniPlayerNotifier, MiniPlayerState>((ref) {
  return MiniPlayerNotifier(ref.watch(audioPlayerServiceProvider));
});
