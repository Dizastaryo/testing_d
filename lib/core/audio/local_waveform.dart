import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Что мы узнали о файле, ещё не загрузив его.
class LocalAudioInfo {
  /// 100 нормализованных пиков — настоящая осциллограмма файла.
  final List<double>? peaks;

  /// Длительность в секундах. 0 — не удалось определить.
  final int durationSeconds;

  const LocalAudioInfo({this.peaks, this.durationSeconds = 0});
}

/// Считает волну и длительность **на устройстве**, до отправки файла.
///
/// Зачем не ждать бэкенд: волну там считает отдельный процесс `media_worker`
/// (ему нужен ffmpeg). Если он не поднят, задача висит в очереди и
/// `waveform_data` остаётся пустым навсегда — а весь несущий мотив Аудиотеки
/// в том, что волна настоящая. Считая её здесь, мы и показываем честную волну
/// в форме загрузки, и гарантируем, что у трека она вообще будет.
///
/// Работает только на реальном устройстве: ffmpeg_kit не собирается под web.
class LocalWaveform {
  LocalWaveform._();

  /// Сколько столбиков в волне — столько же, сколько считает бэкенд.
  static const _peakCount = 100;

  static Future<LocalAudioInfo> analyze(String path) async {
    if (kIsWeb) return const LocalAudioInfo();

    final duration = await _probeDuration(path);
    final peaks = await _extractPeaks(path);
    return LocalAudioInfo(peaks: peaks, durationSeconds: duration);
  }

  static Future<int> _probeDuration(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      final raw = info?.getDuration();
      if (raw == null) return 0;
      return (double.tryParse(raw) ?? 0).round();
    } catch (e) {
      debugPrint('[waveform] probe failed: $e');
      return 0;
    }
  }

  /// Декодируем в моно-PCM 8 кГц и берём максимум по окнам.
  ///
  /// 8 кГц и моно — этого с запасом хватает для картинки в 100 столбиков, зато
  /// декодирование быстрое и временный файл маленький: у пятиминутного трека
  /// это меньше пяти мегабайт вместо сотни.
  static Future<List<double>?> _extractPeaks(String path) async {
    File? pcm;
    try {
      final dir = await getTemporaryDirectory();
      final out =
          '${dir.path}/wf_${DateTime.now().microsecondsSinceEpoch}.pcm';

      final session = await FFmpegKit.execute(
        '-hide_banner -loglevel error -i "$path" '
        '-ac 1 -ar 8000 -f s16le -acodec pcm_s16le "$out"',
      );
      final code = await session.getReturnCode();
      if (!ReturnCode.isSuccess(code)) {
        debugPrint('[waveform] ffmpeg failed: ${await session.getOutput()}');
        return null;
      }

      pcm = File(out);
      if (!await pcm.exists()) return null;
      final bytes = await pcm.readAsBytes();
      return _peaksFromPcm(bytes);
    } catch (e) {
      debugPrint('[waveform] extract failed: $e');
      return null;
    } finally {
      // Временный PCM не нужен ни секунды дольше — он большой.
      try {
        await pcm?.delete();
      } catch (_) {}
    }
  }

  /// PCM signed 16-bit little-endian → [_peakCount] нормализованных пиков.
  @visibleForTesting
  static List<double>? peaksFromPcm(Uint8List bytes) => _peaksFromPcm(bytes);

  static List<double>? _peaksFromPcm(Uint8List bytes) {
    final samples = bytes.lengthInBytes ~/ 2;
    if (samples < _peakCount) return null;

    final view = ByteData.sublistView(bytes);
    final window = samples / _peakCount;

    final peaks = <double>[];
    var maxPeak = 0.0;

    for (var i = 0; i < _peakCount; i++) {
      final from = (i * window).floor();
      final to = math.min(samples, ((i + 1) * window).ceil());

      var peak = 0;
      for (var s = from; s < to; s++) {
        final v = view.getInt16(s * 2, Endian.little).abs();
        if (v > peak) peak = v;
      }
      final v = peak / 32768.0;
      peaks.add(v);
      if (v > maxPeak) maxPeak = v;
    }

    // Тихий трек не должен выглядеть плоским: нормируем по собственному
    // максимуму, а не по абсолютному потолку формата.
    if (maxPeak <= 0.001) return null;
    return [for (final p in peaks) (p / maxPeak).clamp(0.02, 1.0)];
  }
}
