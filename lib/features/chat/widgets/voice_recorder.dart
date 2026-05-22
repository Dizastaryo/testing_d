import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:record/record.dart';

import '../../../core/design/design.dart';

/// Inline recorder. Hold-to-record поведение через `_active` флаг,
/// рендерится поверх обычного input-bar'а как replacement когда юзер
/// начал запись.
///
/// Поток:
///  1. Юзер тапает mic-кнопку → `start()` callback родителя; родитель
///     заменяет input на этот widget (или показывает overlay).
///  2. Идёт запись с amplitude-stream — рисуется живой mini-waveform.
///  3. Юзер тапает «✓» → `onSubmit(filePath, durationSec, samples)` →
///     родитель грузит на сервер.
///  4. Юзер тапает «✕» → `onCancel()` — файл удаляется.
///
/// На вебе `record` пишет webm/opus; на iOS/Android — m4a/aac. Backend
/// принимает audio/* в media-handler'е (после `audio` MIME-фикса от seed-pipeline'а).
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
  // Накопленные amplitude-сэмплы для отрисовки во время записи + для
  // финальной превью-волны на bubble. Сэмплируем раз в ~100ms.
  final List<double> _samples = [];
  // Окно из последних 32 сэмплов для живой визуализации.
  final List<double> _liveWindow = [];

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
    // BUG-FIX: раньше `_tempDir()` возвращал пустую строку → filePath
    // получался '/voice_NNN.m4a' (absolute root, не writeable). Теперь
    // используем path_provider.getTemporaryDirectory() для real temp-dir.
    // Web: record сам создаёт blob, path игнорируется.
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
        if (_elapsed >= _maxDuration) _submit();
      });
    } catch (e) {
      _fail('не удалось начать запись: $e');
    }
  }

  Future<String> _buildFilePath() async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    if (kIsWeb) {
      // Web — record создаёт blob, path-параметр игнорируется. Возвращаем
      // что-нибудь чтобы start() не падал на null-arg.
      return 'voice_$ts.webm';
    }
    final dir = await getTemporaryDirectory();
    return '${dir.path}/voice_$ts.m4a';
  }

  void _onAmp(Amplitude a) {
    // Amplitude.current в dBFS, диапазон ~ -60..0 dB. Нормализуем в 0..1.
    final db = a.current;
    final normalized = ((db.clamp(-50.0, 0.0) + 50.0) / 50.0).clamp(0.0, 1.0);
    _samples.add(normalized);
    _liveWindow.add(normalized);
    if (_liveWindow.length > _liveWindowSize) {
      _liveWindow.removeAt(0);
    }
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
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
      // Слишком короткое нажатие — отмена, не отправляем.
      widget.onCancel();
      return;
    }
    HapticFeedback.heavyImpact();
    widget.onSubmit(pathFinal, dur, _downsample(_samples, _finalSampleCount));
  }

  Future<void> _cancel() async {
    HapticFeedback.lightImpact();
    await _recorder.stop();
    _ampSub?.cancel();
    _tick?.cancel();
    widget.onCancel();
  }

  void _fail(String reason) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(reason)));
    widget.onCancel();
  }

  /// Сжимаем длинный список сэмплов до фиксированного N.
  List<double> _downsample(List<double> input, int target) {
    if (input.isEmpty) return List.filled(target, 0.4);
    if (input.length <= target) {
      final out = List<double>.from(input);
      while (out.length < target) {
        out.add(0.0);
      }
      return out;
    }
    final out = <double>[];
    final step = input.length / target;
    for (var i = 0; i < target; i++) {
      final start = (i * step).floor();
      final end = math.min(input.length, ((i + 1) * step).ceil());
      var sum = 0.0;
      for (var j = start; j < end; j++) {
        sum += input[j];
      }
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: GestureDetector(
          // Slide left to cancel (WhatsApp-style)
          onHorizontalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < -200) _cancel();
          },
          child: Row(
            children: [
              // Cancel — text button for clarity
              GestureDetector(
                onTap: _cancel,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  child: Text(
                    'Отмена',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: SeeUColors.error,
                    ),
                  ),
                ),
              ),
              // Pulsing red dot + timer
              const _PulsingDot(),
              const SizedBox(width: 6),
              Text(
                _fmtDuration(_elapsed),
                style: TextStyle(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(width: 12),
              // Live waveform
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: CustomPaint(
                    painter: _LiveWavePainter(_liveWindow),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Submit
              GestureDetector(
                onTap: _submit,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SeeUGradients.heroOrange,
                  ),
                  child: Icon(PhosphorIconsBold.arrowUp, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    // Last n samples (или меньше).
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
  bool shouldRepaint(covariant _LiveWavePainter old) =>
      old.samples.length != samples.length;
}

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
