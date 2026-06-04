import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:record/record.dart';

import '../../../core/design/design.dart';

enum _RecState { recording, preview }

/// Inline recorder bar — заменяет input-bar во время записи голосового.
///
/// Поток:
///  1. Показывается сразу с началом записи.
///  2. Запись: [🗑 отменить] [● таймер ~~~waveform~~~] [✓ остановить]
///  3. Preview: [✕ отменить] [▶ play] [~~~waveform~~~ длит.] [🔄 перезаписать] [➤ отправить]
///     — юзер может сразу нажать ➤ без прослушивания, либо прослушать ▶ затем ➤.
///  4. onSubmit(filePath, durationSec, samples) → родитель грузит на сервер.
///  5. onCancel() → возврат к обычному input.
class VoiceRecorderBar extends StatefulWidget {
  final VoidCallback onCancel;
  final void Function(String path, int durationSec, List<double> samples)
      onSubmit;

  const VoiceRecorderBar({
    super.key,
    required this.onCancel,
    required this.onSubmit,
  });

  @override
  State<VoiceRecorderBar> createState() => _VoiceRecorderBarState();
}

class _VoiceRecorderBarState extends State<VoiceRecorderBar> {
  final _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _tick;
  Duration _elapsed = Duration.zero;
  String? _path;
  final List<double> _samples = [];
  final List<double> _liveWindow = [];

  _RecState _recState = _RecState.recording;
  AudioPlayer? _previewPlayer;
  String? _previewPath;
  int _previewDurationSec = 0;
  List<double> _previewSamples = [];
  bool _previewPlaying = false;

  static const _maxDuration = Duration(seconds: 60);
  static const _liveWindowSize = 32;
  static const _finalSampleCount = 48;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      _fail('нет разрешения на микрофон');
      return;
    }
    final filePath = await _buildFilePath();
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
        ),
        path: filePath,
      );
      _path = filePath;
      HapticFeedback.mediumImpact();
      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen(_onAmp);
      _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        setState(() {
          _elapsed += const Duration(milliseconds: 200);
        });
        if (_elapsed >= _maxDuration) _stopToPreview();
      });
    } catch (e) {
      _fail('не удалось начать запись: $e');
    }
  }

  Future<String> _buildFilePath() async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    if (kIsWeb) return 'voice_$ts.webm';
    final dir = await getTemporaryDirectory();
    return '${dir.path}/voice_$ts.m4a';
  }

  void _onAmp(Amplitude a) {
    final db = a.current;
    final normalized = ((db.clamp(-50.0, 0.0) + 50.0) / 50.0).clamp(0.0, 1.0);
    _samples.add(normalized);
    _liveWindow.add(normalized);
    if (_liveWindow.length > _liveWindowSize) {
      _liveWindow.removeAt(0);
    }
    if (mounted) setState(() {});
  }

  /// Останавливает запись и переходит в preview-режим.
  /// Кнопка ✓ (checkmark) — не отправка, а завершение записи.
  Future<void> _stopToPreview() async {
    final p = await _recorder.stop();
    _ampSub?.cancel();
    _tick?.cancel();
    final pathFinal = p ?? _path;
    if (pathFinal == null || pathFinal.isEmpty) {
      widget.onCancel();
      return;
    }
    final dur = _elapsed.inSeconds;
    if (dur < 1) {
      _deleteFile(pathFinal);
      widget.onCancel();
      return;
    }
    HapticFeedback.heavyImpact();

    _previewPath = pathFinal;
    _previewDurationSec = dur;
    _previewSamples = _downsample(_samples, _finalSampleCount);

    _previewPlayer = AudioPlayer();
    _previewPlayer!.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _previewPlayer?.seek(Duration.zero);
        if (mounted) setState(() => _previewPlaying = false);
      } else {
        if (mounted) setState(() => _previewPlaying = s.playing);
      }
    });
    if (!kIsWeb) {
      try {
        await _previewPlayer!.setFilePath(pathFinal);
      } catch (_) {}
    }
    if (mounted) setState(() => _recState = _RecState.preview);
  }

  /// Отправляет записанный файл сразу без ожидания.
  void _sendNow() {
    HapticFeedback.heavyImpact();
    _previewPlayer?.stop();
    _previewPlayer?.dispose();
    _previewPlayer = null;
    widget.onSubmit(_previewPath!, _previewDurationSec, _previewSamples);
  }

  Future<void> _reRecord() async {
    await _previewPlayer?.stop();
    _previewPlayer?.dispose();
    _previewPlayer = null;
    _deleteFile(_previewPath);
    _previewPath = null;
    _previewSamples = [];
    _previewPlaying = false;
    _elapsed = Duration.zero;
    _samples.clear();
    _liveWindow.clear();
    _path = null;
    setState(() => _recState = _RecState.recording);
    await _start();
  }

  Future<void> _togglePreviewPlay() async {
    if (_previewPlayer == null) return;
    if (_previewPlaying) {
      await _previewPlayer!.pause();
    } else {
      await _previewPlayer!.play();
    }
  }

  /// Отмена из режима ЗАПИСИ — удаляем временный файл.
  Future<void> _cancelRecording() async {
    HapticFeedback.lightImpact();
    await _recorder.stop();
    _ampSub?.cancel();
    _tick?.cancel();
    _deleteFile(_path);
    widget.onCancel();
  }

  /// Отмена из режима PREVIEW — удаляем файл, возвращаем к обычному вводу.
  Future<void> _discardPreview() async {
    HapticFeedback.lightImpact();
    await _previewPlayer?.stop();
    _previewPlayer?.dispose();
    _previewPlayer = null;
    _deleteFile(_previewPath);
    widget.onCancel();
  }

  void _deleteFile(String? path) {
    if (path == null || kIsWeb) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  void _fail(String reason) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(reason)));
    widget.onCancel();
  }

  List<double> _downsample(List<double> input, int target) {
    if (input.isEmpty) return List.filled(target, 0.4);
    if (input.length <= target) {
      final out = List<double>.from(input);
      while (out.length < target) { out.add(0.0); }
      return out;
    }
    final out = <double>[];
    final step = input.length / target;
    for (var i = 0; i < target; i++) {
      final start = (i * step).floor();
      final end = math.min(input.length, ((i + 1) * step).ceil());
      var sum = 0.0;
      for (var j = start; j < end; j++) { sum += input[j]; }
      out.add(sum / (end - start));
    }
    return out;
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _ampSub?.cancel();
    _tick?.cancel();
    _recorder.dispose();
    _previewPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: _recState == _RecState.preview
            ? _buildPreviewRow(c)
            : GestureDetector(
                onHorizontalDragEnd: (details) {
                  if ((details.primaryVelocity ?? 0) < -200) _cancelRecording();
                },
                child: _buildRecordingRow(c),
              ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Режим записи: [🗑] [● 00:15 ~~~waveform~~~] [✓]
  // ---------------------------------------------------------------------------
  Widget _buildRecordingRow(SeeUThemeColors c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Отмена записи — иконка корзины
        GestureDetector(
          onTap: _cancelRecording,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              PhosphorIcons.trash(),
              color: SeeUColors.error,
              size: 22,
            ),
          ),
        ),
        // Пульсирующая красная точка
        const _PulsingDot(),
        const SizedBox(width: 6),
        // Таймер
        Text(
          _fmtDuration(_elapsed),
          style: TextStyle(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: c.ink,
          ),
        ),
        const SizedBox(width: 8),
        // Живая waveform
        Expanded(
          child: SizedBox(
            height: 36,
            child: CustomPaint(
              painter: _LiveWavePainter(_liveWindow),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Остановить запись → перейти в preview (✓ checkmark)
        GestureDetector(
          onTap: _stopToPreview,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SeeUGradients.heroOrange,
            ),
            child: const Icon(
              PhosphorIconsBold.check,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Режим preview: [✕] [▶] [~~~waveform~~~ длит.] [🔄] [➤]
  // ---------------------------------------------------------------------------
  Widget _buildPreviewRow(SeeUThemeColors c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Отменить и выбросить запись
        GestureDetector(
          onTap: _discardPreview,
          child: SizedBox(
            width: 40,
            height: 44,
            child: Icon(PhosphorIcons.x(), color: c.ink3, size: 20),
          ),
        ),
        const SizedBox(width: 4),
        // Play / pause для прослушивания перед отправкой
        GestureDetector(
          onTap: _togglePreviewPlay,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SeeUColors.accent.withValues(alpha: 0.12),
            ),
            child: Icon(
              _previewPlaying
                  ? PhosphorIcons.pause(PhosphorIconsStyle.fill)
                  : PhosphorIcons.play(PhosphorIconsStyle.fill),
              color: SeeUColors.accent,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Waveform + длительность
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 32,
                child: CustomPaint(
                  painter: _LiveWavePainter(_previewSamples),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _fmtDuration(Duration(seconds: _previewDurationSec)),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: c.ink2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        // Перезаписать (иконка стрелки-перезагрузки)
        GestureDetector(
          onTap: _reRecord,
          child: SizedBox(
            width: 40,
            height: 44,
            child: Icon(
              PhosphorIcons.arrowCounterClockwise(),
              color: c.ink2,
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Отправить сразу — paper plane, не стрелка вверх
        GestureDetector(
          onTap: _sendNow,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SeeUGradients.heroOrange,
            ),
            child: const Icon(
              PhosphorIconsFill.paperPlaneRight,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Live waveform painter
// ---------------------------------------------------------------------------

class _LiveWavePainter extends CustomPainter {
  final List<double> samples;
  _LiveWavePainter(this.samples);

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final paint = Paint()
      ..color = SeeUColors.accent
      ..style = PaintingStyle.fill;
    const barW = 3.0;
    const gap = 2.0;
    final centerY = size.height / 2;
    final n = ((size.width + gap) / (barW + gap)).floor();
    final start = math.max(0, samples.length - n);
    final visible = samples.sublist(start);
    final pad = n - visible.length;
    for (var i = 0; i < n; i++) {
      final v = i < pad ? 0.05 : visible[i - pad];
      final h = math.max(2.0, v * size.height * 0.9);
      final x = i * (barW + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(x + barW / 2, centerY), width: barW, height: h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  // Всегда перерисовываем — живая waveform меняется постоянно.
  // (Старый код проверял samples.length, что замораживало картинку когда
  // окно из 32 баров было заполнено — длина не менялась.)
  bool shouldRepaint(covariant _LiveWavePainter old) => true;
}

// ---------------------------------------------------------------------------
// Pulsing red dot
// ---------------------------------------------------------------------------

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.25, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: SeeUColors.error,
        ),
      ),
    );
  }
}
