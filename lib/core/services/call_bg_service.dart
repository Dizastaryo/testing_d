import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'logger.dart';

// ignore_for_file: avoid_void_async

/// Управляет двумя вещами:
/// 1. AVAudioSession — переключение между режимами «рингтон» и «звонок» (iOS).
/// 2. Android ForegroundService — держит процесс живым пока экран заблокирован.
///
/// На Android без ForegroundService ОС убивает WebRTC через ~60 с после
/// перехода приложения в background.
/// На iOS достаточно AVAudioSession с .playAndRecord + UIBackgroundModes:audio.
class CallBgService {
  CallBgService._();
  static final CallBgService instance = CallBgService._();

  static const _ch    = MethodChannel('seeu/call_fg');
  static const _pipCh = MethodChannel('seeu/pip');

  /// true когда Activity находится в режиме PiP (Android).
  /// Flutter переключается на минимальный UI.
  final ValueNotifier<bool> pipMode = ValueNotifier(false);

  // ── AudioSession ──────────────────────────────────────────────────────────

  /// Режим активного звонка / голосового канала:
  /// - iOS: .playAndRecord + .voiceChat — захватывает микрофон и работает
  ///   в background'е (UIBackgroundModes:audio уже задан в Info.plist).
  /// - Android: фокус gain (долгосрочный захват) + voiceCommunication.
  Future<void> configureForCall() async {
    try {
      final s = await AudioSession.instance;
      await s.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      await s.setActive(true);
      appLog('[CallBgService] audio → voiceChat');
    } catch (e, st) {
      appLog.error('[CallBgService] configureForCall failed', e, st);
    }
  }

  /// Режим рингтона: .playback + .voicePrompt — громкий сигнал через speaker.
  Future<void> configureForRingtone() async {
    try {
      final s = await AudioSession.instance;
      await s.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.duckOthers,
        avAudioSessionMode: AVAudioSessionMode.voicePrompt,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.audibilityEnforced,
          usage: AndroidAudioUsage.notificationRingtone,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
        androidWillPauseWhenDucked: true,
      ));
      await s.setActive(true);
      appLog('[CallBgService] audio → ringtone');
    } catch (e, st) {
      appLog.error('[CallBgService] configureForRingtone failed', e, st);
    }
  }

  // ── Android ForegroundService ─────────────────────────────────────────────

  /// Запустить ForegroundService с persistent-нотификацией.
  /// На iOS — no-op: background audio держится через AVAudioSession.
  Future<void> startForeground({
    required String title,
    required String body,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _ch.invokeMethod<void>(
          'startForeground', {'title': title, 'body': body});
      appLog('[CallBgService] FG started: $title');
    } catch (e, st) {
      appLog.error('[CallBgService] startForeground failed', e, st);
    }
  }

  /// Остановить ForegroundService (при завершении звонка / выходе из канала).
  Future<void> stopForeground() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _ch.invokeMethod<void>('stopForeground');
      appLog('[CallBgService] FG stopped');
    } catch (e, st) {
      appLog.error('[CallBgService] stopForeground failed', e, st);
    }
  }

  // ── PiP ───────────────────────────────────────────────────────────────────

  /// Активировать PiP-режим.
  /// Android: Activity входит в PiP.
  /// iOS: запустить нативный AVPictureInPicture немедленно (floating overlay).
  Future<void> enterPip({
    String avatarUrl = '',
    String username  = '',
    String kind      = 'voice',
  }) async {
    try {
      await _pipCh.invokeMethod<void>('enterPip', {
        'avatarUrl': avatarUrl,
        'username' : username,
        'kind'     : kind,
      });
      appLog('[CallBgService] PiP entered');
    } catch (e, st) {
      appLog.error('[CallBgService] enterPip failed', e, st);
    }
  }

  /// iOS: подготовить данные звонка для нативного PiP.
  /// PiP запустится автоматически когда приложение уходит в фон,
  /// и погасится когда вернётся. Внутри приложения — только Flutter overlay.
  Future<void> prepareCallPip({
    String avatarUrl = '',
    String username  = '',
    String kind      = 'voice',
  }) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _pipCh.invokeMethod<void>('prepareCallPip', {
        'avatarUrl': avatarUrl,
        'username' : username,
        'kind'     : kind,
      });
      appLog('[CallBgService] PiP prepared (ios)');
    } catch (e, st) {
      appLog.error('[CallBgService] prepareCallPip failed', e, st);
    }
  }

  /// iOS: завершить PiP и снять lifecycle-наблюдатели (вызывается при окончании звонка).
  Future<void> clearCallPip() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _pipCh.invokeMethod<void>('clearCallPip');
      appLog('[CallBgService] PiP cleared (ios)');
    } catch (e, st) {
      appLog.error('[CallBgService] clearCallPip failed', e, st);
    }
  }

  /// Завершить PiP (iOS: скрыть нативное окно, не снимая lifecycle-наблюдатели).
  Future<void> exitPip() async {
    try {
      await _pipCh.invokeMethod<void>('exitPip');
      appLog('[CallBgService] PiP exited');
    } catch (e, st) {
      appLog.error('[CallBgService] exitPip failed', e, st);
    }
  }

  /// Сообщить Android, что активный звонок начался/закончился.
  /// Используется в onUserLeaveHint для авто-входа в PiP при нажатии «Домой».
  Future<void> setCallActive(bool active) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _ch.invokeMethod<void>('setCallActive', {'active': active});
    } catch (e, st) {
      appLog.error('[CallBgService] setCallActive failed', e, st);
    }
  }
}
