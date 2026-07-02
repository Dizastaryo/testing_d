import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Настраивает общий AudioSession под воспроизведение видео так, чтобы звук
/// продолжал играть при блокировке экрана / уходе приложения в фон (как у
/// музыкального плеера). Категория `.music()` = playback на iOS. Безопасно при
/// ошибках — просто no-op. Вызывается из экранов видео при старте плеера.
Future<void> configureVideoBackgroundAudio() async {
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (_) {}
}

// ── Video info stored while video is active / in PiP ────────────────────────

class VideoInfo {
  final String videoId;
  final String url;
  final String title;
  final String thumbnailUrl;
  final int positionMs;
  // Пропорции видео (для корректного PiP-окна на Android). По умолчанию 16:9.
  final int aspectWidth;
  final int aspectHeight;

  const VideoInfo({
    required this.videoId,
    required this.url,
    required this.title,
    required this.thumbnailUrl,
    required this.positionMs,
    this.aspectWidth = 16,
    this.aspectHeight = 9,
  });

  VideoInfo withPosition(int ms) => VideoInfo(
        videoId: videoId,
        url: url,
        title: title,
        thumbnailUrl: thumbnailUrl,
        positionMs: ms,
        aspectWidth: aspectWidth,
        aspectHeight: aspectHeight,
      );
}

// ── State ────────────────────────────────────────────────────────────────────

class VideoPipState {
  final bool pipActive;
  final bool showMiniPlayer;
  final VideoInfo? video;

  const VideoPipState({
    this.pipActive = false,
    this.showMiniPlayer = false,
    this.video,
  });

  VideoPipState copyWith({
    bool? pipActive,
    bool? showMiniPlayer,
    VideoInfo? video,
    bool clearVideo = false,
  }) =>
      VideoPipState(
        pipActive: pipActive ?? this.pipActive,
        showMiniPlayer: showMiniPlayer ?? this.showMiniPlayer,
        video: clearVideo ? null : (video ?? this.video),
      );
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class VideoPipNotifier extends StateNotifier<VideoPipState> {
  static const _ch = MethodChannel('seeu/video_pip');

  VideoPipNotifier() : super(const VideoPipState()) {
    _ch.setMethodCallHandler(_onNativeCall);
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      // Android: Activity entered / exited PiP mode.
      case 'pipModeChanged':
        final active = call.arguments as bool;
        if (!active && state.pipActive) {
          // PiP exited — keep mini player visible on iOS (Android Activity
          // is typically destroyed on '×', so showMiniPlayer is harmless there).
          state = state.copyWith(pipActive: false, showMiniPlayer: state.video != null);
        } else {
          state = state.copyWith(pipActive: active);
        }

      // iOS: PiP window closed via '×' — carry the final position.
      case 'videoPipStopped':
        final posMs = (call.arguments as int?) ?? (state.video?.positionMs ?? 0);
        final updated = state.video?.withPosition(posMs);
        state = state.copyWith(
          pipActive: false,
          showMiniPlayer: updated != null,
          video: updated,
        );

      // iOS: user tapped 'Expand' — app will come to foreground, no mini needed.
      case 'videoPipReturn':
        state = state.copyWith(pipActive: false, showMiniPlayer: false);
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Called when a video screen opens (active=true) or closes (active=false).
  Future<void> setActive({
    required bool active,
    String videoId = '',
    String url = '',
    String title = '',
    String thumbnailUrl = '',
    int positionMs = 0,
    int aspectWidth = 16,
    int aspectHeight = 9,
  }) async {
    if (active) {
      state = state.copyWith(
        video: VideoInfo(
          videoId: videoId,
          url: url,
          title: title,
          thumbnailUrl: thumbnailUrl,
          positionMs: positionMs,
          aspectWidth: aspectWidth,
          aspectHeight: aspectHeight,
        ),
        showMiniPlayer: false,
      );
    } else if (!state.pipActive) {
      // Only clear when NOT in PiP — PiP still needs the info.
      state = state.copyWith(clearVideo: true, showMiniPlayer: false);
    }
    try {
      await _ch.invokeMethod('setVideoActive', {
        'active': active,
        'url': url,
        'aspectW': aspectWidth,
        'aspectH': aspectHeight,
      });
    } catch (_) {}
  }

  /// Periodic update from video player so position is current when PiP starts.
  void updatePosition(int positionMs) {
    if (state.video != null) {
      state = state.copyWith(video: state.video!.withPosition(positionMs));
    }
  }

  /// iOS-only: app is going to background with video active → start native PiP.
  Future<void> startIosPip() async {
    final v = state.video;
    if (v == null) return;
    try {
      await _ch.invokeMethod('startVideoPip', {
        'url': v.url,
        'positionMs': v.positionMs,
      });
    } catch (_) {}
  }

  /// Android-only: app is going to background with video active → request the
  /// system to enter Activity-level Picture-in-Picture. The native side already
  /// auto-enters on Home/gesture (onUserLeaveHint + autoEnter on Android 12+);
  /// this is the explicit fallback for the Flutter lifecycle path. Graceful —
  /// if the device can't enter PiP, the native handler swallows it and audio
  /// keeps playing in the background.
  Future<void> startAndroidPip() async {
    final v = state.video;
    if (v == null) return;
    try {
      await _ch.invokeMethod('startVideoPip', {
        'url': v.url,
        'positionMs': v.positionMs,
        'aspectW': v.aspectWidth,
        'aspectH': v.aspectHeight,
      });
    } catch (_) {}
  }

  /// Dismiss the mini player overlay and clear video state.
  void dismissMiniPlayer() {
    state = state.copyWith(showMiniPlayer: false, clearVideo: true);
    try {
      _ch.invokeMethod('setVideoActive', {'active': false, 'url': ''});
    } catch (_) {}
  }
}

final videoPipProvider =
    StateNotifierProvider<VideoPipNotifier, VideoPipState>((ref) {
  return VideoPipNotifier();
});
