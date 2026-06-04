import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../../../core/utils/format.dart';
import '../../../core/providers/chat_provider.dart';

/// Voice-message bubble — обёртка вокруг play/pause-кнопки + waveform-prerender'а.
///
/// Получает [audioUrl] (full URL до ogg/m4a/webm), [durationSec] (от сервера —
/// уже probed ffprobe'ом или клиентом до отправки) и опциональный
/// [waveformSamples] (список 0..1, длиной около 48). Если samples нет —
/// рисуется ровная полоска.
///
/// Если переданы [chatId] и [messageId], bubble участвует в auto-next-play
/// (CHAT-7): после завершения текущего voice'а через `chatMessagesProvider`
/// ищется следующий voice-message в том же чате, его id кладётся в
/// `voiceAutoPlayQueueProvider`, и соответствующий bubble стартует play.
class VoiceBubble extends ConsumerStatefulWidget {
  final String audioUrl;
  final int durationSec;
  final List<double>? waveformSamples;
  final bool isMine;
  final String? chatId;
  final String? messageId;
  /// Время отправки в формате "HH:MM" для отображения внутри бабла.
  final String? sentTimeLabel;
  final bool isRead;
  final bool isDelivered;

  const VoiceBubble({
    super.key,
    required this.audioUrl,
    required this.durationSec,
    this.waveformSamples,
    required this.isMine,
    this.chatId,
    this.messageId,
    this.sentTimeLabel,
    this.isRead = false,
    this.isDelivered = false,
  });

  @override
  ConsumerState<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends ConsumerState<VoiceBubble> {
  // Один shared плеер для всех VoiceBubble не делаем — у каждой своя
  // позиция, и чаще нужен только один играющий за раз. Если будет issue
  // с одновременным воспроизведением — добавим coordinator-провайдер.
  final _player = AudioPlayer();
  bool _loaded = false;
  bool _loading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  // Playback rate цикл: 1.0 → 1.5 → 2.0 → 1.0. Тап на pill справа.
  // just_audio поддерживает stable до 2.0× без артефактов pitch'а.
  double _speed = 1.0;
  static const _speedCycle = [1.0, 1.5, 2.0];
  double? _seekIndicator; // 0..1, normalised drag position

  ProviderSubscription<String?>? _queueSub;
  ProviderSubscription<String?>? _coordinatorSub;

  @override
  void initState() {
    super.initState();
    _duration = Duration(seconds: widget.durationSec);
    _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.durationStream.listen((d) {
      if (d != null && mounted) setState(() => _duration = d);
    });
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        // По окончанию — сбрасываем позицию + pause для возможности replay
        // и триггерим auto-next (CHAT-7). Также освобождаем coordinator —
        // следующий voice claim'ит сам (CHAT-6.1).
        _player.seek(Duration.zero);
        _player.pause();
        _releaseCoordinatorIfMine();
        _triggerAutoNext();
      }
      if (mounted) setState(() {});
    });

    // Слушаем queue — если pushнули наш id, автозапуск (CHAT-7).
    if (widget.chatId != null && widget.messageId != null) {
      _queueSub = ref.listenManual<String?>(
        voiceAutoPlayQueueProvider,
        (prev, next) {
          if (next != null && next == widget.messageId) {
            ref.read(voiceAutoPlayQueueProvider.notifier).state = null;
            _autoPlay();
          }
        },
      );

      // CHAT-6.1: coordinator — если кто-то другой claim'нул playback,
      // pause'имся (если играли). Идемпотент: own claim не триггерит
      // self-pause (next == widget.messageId).
      _coordinatorSub = ref.listenManual<String?>(
        currentlyPlayingVoiceProvider,
        (prev, next) {
          if (next != widget.messageId && _player.playing) {
            _player.pause();
          }
        },
      );
    }
  }

  /// Помечает voice как прослушанный (CHAT-7.1) — auto-next пропустит его.
  /// No-op если widget без messageId (legacy/single-message сценарий).
  void _markListened() {
    final mid = widget.messageId;
    if (mid == null) return;
    final cur = ref.read(listenedVoiceIdsProvider);
    if (cur.contains(mid)) return;
    ref.read(listenedVoiceIdsProvider.notifier).state = {...cur, mid};
  }

  /// Claim'им экcклюзивный playback (CHAT-6.1) — другие voice-bubble'ы
  /// получат event и pause'ятся.
  void _claimCoordinator() {
    final mid = widget.messageId;
    if (mid == null) return;
    ref.read(currentlyPlayingVoiceProvider.notifier).state = mid;
  }

  /// Отпускаем coordinator если он сейчас на нас. Вызывается при manual
  /// pause + при playback-completed. Идемпотент.
  void _releaseCoordinatorIfMine() {
    final mid = widget.messageId;
    if (mid == null) return;
    final cur = ref.read(currentlyPlayingVoiceProvider);
    if (cur == mid) {
      ref.read(currentlyPlayingVoiceProvider.notifier).state = null;
    }
  }

  /// Поиск next voice-message в чате и установка его id в queue.
  /// Используется при completion текущего voice'а. CHAT-7.1: пропускаем
  /// voice'ы которые юзер уже слушал в этой сессии (filter через
  /// `listenedVoiceIdsProvider`).
  void _triggerAutoNext() {
    final cid = widget.chatId;
    final mid = widget.messageId;
    if (cid == null || mid == null) return;
    final messages = ref.read(chatMessagesProvider(cid)).messages;
    final idx = messages.indexWhere((m) => m.id == mid);
    if (idx < 0) return;
    final listened = ref.read(listenedVoiceIdsProvider);
    for (var i = idx + 1; i < messages.length; i++) {
      final m = messages[i];
      if (m.kind != 'voice' && m.kind != 'audio') continue;
      if (listened.contains(m.id)) continue; // CHAT-7.1: skip прослушанные
      ref.read(voiceAutoPlayQueueProvider.notifier).state = m.id;
      return;
    }
  }

  /// Like _toggle but always starts play (used by auto-next).
  Future<void> _autoPlay() async {
    await _ensureLoaded();
    if (!_player.playing) {
      _claimCoordinator();
      _markListened();
      await _player.play();
    }
  }

  Future<void> _ensureLoaded() async {
    if (_loaded || _loading) return;
    setState(() => _loading = true);
    try {
      await _player.setUrl(widget.audioUrl);
      if (_speed != 1.0) {
        try { await _player.setSpeed(_speed); } catch (_) {}
      }
      _loaded = true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось загрузить аудио'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();
    await _ensureLoaded();
    if (_player.playing) {
      await _player.pause();
      _releaseCoordinatorIfMine();
    } else {
      // CHAT-6.1: claim перед play — другие voice'ы получат event и pause'ятся.
      // CHAT-7.1: помечаем как прослушанный — auto-next пропустит при возврате.
      _claimCoordinator();
      _markListened();
      await _player.play();
    }
  }

  Future<void> _cycleSpeed() async {
    HapticFeedback.selectionClick();
    final idx = _speedCycle.indexOf(_speed);
    final next = _speedCycle[(idx + 1) % _speedCycle.length];
    setState(() => _speed = next);
    try {
      await _player.setSpeed(next);
    } catch (_) {
      // На некоторых платформах setSpeed может бросать до первого load'а.
      // Игнорируем — следующий load применит сохранённый _speed (см.
      // _ensureLoaded ниже).
    }
  }

  /// Форматирование label'а: "1×" / "1.5×" / "2×". Без trailing ".0".
  String _fmtSpeed(double s) {
    final n = s.toInt();
    return s == n.toDouble() ? '$n×' : '$s×';
  }

  @override
  void dispose() {
    _queueSub?.close();
    _coordinatorSub?.close();
    _releaseCoordinatorIfMine();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final progress =
        _duration.inMilliseconds == 0 ? 0.0 : _position.inMilliseconds / _duration.inMilliseconds;
    return Container(
      // #23: уменьшили minWidth 200→160 — меньше overflow на узких экранах
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 260),
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: BoxDecoration(
        gradient: widget.isMine ? SeeUGradients.heroOrange : null,
        color: widget.isMine ? null : c.surface2,
        // #37: асимметричный radius как у текстовых баблов — «хвост» указывает
        // на отправителя (правый нижний для своих, левый нижний для чужих)
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(widget.isMine ? 20 : 8),
          bottomRight: Radius.circular(widget.isMine ? 8 : 20),
        ),
      ),
      child: Row(
        children: [
          // Play/pause
          GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isMine
                    ? Colors.white.withValues(alpha: 0.20)
                    : SeeUColors.accent.withValues(alpha: 0.10),
              ),
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color:
                            widget.isMine ? Colors.white : SeeUColors.accent,
                      ),
                    )
                  : Icon(
                      _player.playing
                          ? PhosphorIcons.pause(PhosphorIconsStyle.fill)
                          : PhosphorIcons.play(PhosphorIconsStyle.fill),
                      color:
                          widget.isMine ? Colors.white : SeeUColors.accent,
                      size: 18,
                    ),
            ),
          ),
          const SizedBox(width: 10),
          // Waveform + duration
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (_, constraints) {
                    final w = constraints.maxWidth;
                    return GestureDetector(
                      onTapUp: (details) {
                        final ratio =
                            (details.localPosition.dx / w).clamp(0.0, 1.0);
                        _player.seek(Duration(
                            milliseconds:
                                (_duration.inMilliseconds * ratio).round()));
                        if (mounted) setState(() => _seekIndicator = null);
                      },
                      onHorizontalDragUpdate: (details) {
                        final ratio =
                            (details.localPosition.dx / w).clamp(0.0, 1.0);
                        if (mounted) setState(() => _seekIndicator = ratio);
                      },
                      onHorizontalDragEnd: (_) {
                        if (_seekIndicator != null) {
                          _player.seek(Duration(
                              milliseconds: (_duration.inMilliseconds *
                                      _seekIndicator!)
                                  .round()));
                          if (mounted) setState(() => _seekIndicator = null);
                        }
                      },
                      child: SizedBox(
                        height: 36,
                        child: CustomPaint(
                          painter: _StaticWavePainter(
                            samples: widget.waveformSamples ?? const [],
                            progress: _seekIndicator ?? progress,
                            colorBase: widget.isMine
                                ? Colors.white.withValues(alpha: 0.45)
                                : c.ink3,
                            colorPlayed: widget.isMine
                                ? Colors.white
                                : SeeUColors.accent,
                            seekIndicator: _seekIndicator,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    // Длительность / позиция воспроизведения
                    Text(
                      _player.playing || _position > Duration.zero
                          ? formatDuration(_position)
                          : formatDuration(_duration),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: widget.isMine ? Colors.white70 : c.ink2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Spacer(),
                    // Speed pill
                    GestureDetector(
                      onTap: _cycleSpeed,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _speed == 1.0
                              ? (widget.isMine
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : SeeUColors.accent.withValues(alpha: 0.10))
                              : (widget.isMine
                                  ? Colors.white
                                  : SeeUColors.accent),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          _fmtSpeed(_speed),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _speed == 1.0
                                ? (widget.isMine
                                    ? Colors.white
                                    : SeeUColors.accent)
                                : (widget.isMine
                                    ? SeeUColors.accent
                                    : Colors.white),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    // Время отправки + галочки прочтения
                    if (widget.sentTimeLabel != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        widget.sentTimeLabel!,
                        style: TextStyle(
                          fontSize: 10,
                          color: widget.isMine
                              ? Colors.white.withValues(alpha: 0.6)
                              : c.ink3,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (widget.isMine) ...[
                        const SizedBox(width: 3),
                        Icon(
                          (widget.isRead || widget.isDelivered)
                              ? PhosphorIconsBold.checks
                              : PhosphorIconsRegular.check,
                          size: 12,
                          color: widget.isRead
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.65),
                        ),
                      ],
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StaticWavePainter extends CustomPainter {
  final List<double> samples;
  final double progress; // 0..1, played-portion
  final Color colorBase;
  final Color colorPlayed;
  final double? seekIndicator; // 0..1, drag seek line

  _StaticWavePainter({
    required this.samples,
    required this.progress,
    required this.colorBase,
    required this.colorPlayed,
    this.seekIndicator,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // #33: унифицировали с рекордером — было 2px, стало 3px
    const barW = 3.0;
    const gap = 2.0;
    final n = ((size.width + gap) / (barW + gap)).floor();
    final centerY = size.height / 2;
    final total = n;
    final playedBars = (progress * total).round();
    for (var i = 0; i < n; i++) {
      // Если samples длинее n — берём ближайший downsample. Если меньше —
      // зацикливаем для bar-плейсхолдера.
      double v;
      if (samples.isEmpty) {
        // Плоская линия вместо фейкового синуса — не вводим юзера в заблуждение.
        v = 0.35;
      } else {
        final idx = ((i / n) * samples.length).floor().clamp(0, samples.length - 1);
        v = samples[idx];
      }
      final h = math.max(3.0, v * size.height * 0.95);
      final x = i * (barW + gap);
      final paint = Paint()
        ..color = i < playedBars ? colorPlayed : colorBase
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(x + barW / 2, centerY), width: barW, height: h),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
    // Seek drag indicator line
    if (seekIndicator != null) {
      final x = seekIndicator! * size.width;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = colorPlayed
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StaticWavePainter old) =>
      old.progress != progress ||
      old.samples.length != samples.length ||
      old.colorPlayed != colorPlayed ||
      old.seekIndicator != seekIndicator;
}
