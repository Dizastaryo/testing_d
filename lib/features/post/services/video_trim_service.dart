import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Обёртка над ffmpeg для подготовки видео при создании постов: обрезка по
/// диапазону, удаление аудиодорожки и склейка нескольких клипов.
///
/// Каждый метод возвращает путь к новому файлу либо null при ошибке — вызывающий
/// код в этом случае откатывается к исходному файлу.
class VideoTrimService {
  VideoTrimService._();

  static Future<String> _outPath(String suffix) async {
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().microsecondsSinceEpoch;
    return '${dir.path}/vts_${ts}_$suffix.mp4';
  }

  static Future<bool> _run(String command) async {
    final session = await FFmpegKit.execute(command);
    final rc = await session.getReturnCode();
    final ok = ReturnCode.isSuccess(rc);
    if (!ok) {
      debugPrint('VideoTrimService: ffmpeg failed rc=$rc cmd=$command');
    }
    return ok;
  }

  /// Обрезает [inputPath] до [startSec, endSec]. Перекодирует ради кадровой
  /// точности. Возвращает путь к результату либо null.
  static Future<String?> trim({
    required String inputPath,
    required double startSec,
    required double endSec,
  }) async {
    final duration = endSec - startSec;
    if (duration <= 0) return null;

    final out = await _outPath('trim');
    final ok = await _run(
      '-y -ss $startSec -i "$inputPath" -t $duration '
      '-c:v libx264 -preset veryfast -c:a aac -movflags +faststart "$out"',
    );
    if (!ok) return null;
    return File(out).existsSync() ? out : null;
  }

  /// Удаляет аудиодорожку из [inputPath] (видео копируется без перекодирования).
  /// Возвращает путь к результату либо null.
  static Future<String?> stripAudio(String inputPath) async {
    final out = await _outPath('noaudio');
    final ok = await _run('-y -i "$inputPath" -an -c:v copy "$out"');
    if (!ok) return null;
    return File(out).existsSync() ? out : null;
  }

  /// Отражает [inputPath] по горизонтали. Используется для фронтальной камеры:
  /// нативный camera-плагин зеркалит только live-превью, сохранённые байты —
  /// никогда, так что без этого шага селфи-видео выглядит "перевёрнутым".
  /// Возвращает путь к результату либо null.
  static Future<String?> hflip(String inputPath) async {
    final out = await _outPath('hflip');
    final ok = await _run(
      '-y -i "$inputPath" -vf hflip '
      '-c:v libx264 -preset veryfast -c:a copy -movflags +faststart "$out"',
    );
    if (!ok) return null;
    return File(out).existsSync() ? out : null;
  }

  /// Запекает цветокоррекцию (brightness/contrast/saturation/warmth — те же
  /// параметры, что и `FilterState`/пресеты камеры) в видео через ffmpeg.
  /// Живой `ColorFiltered`/`FilterOverlay` работает только для превью — у
  /// видео нет эквивалента "compose" для фото, так что без этого прохода
  /// пресеты и слайдеры цвета не долетают до сохранённого файла.
  /// Значения параметров — как в `FilterState`: -1..+1 (0 = identity).
  /// Возвращает путь к результату либо null (в т.ч. если все параметры нулевые).
  static Future<String?> applyColorGrade({
    required String inputPath,
    double brightness = 0,
    double contrast = 0,
    double saturation = 0,
    double warmth = 0,
  }) async {
    if (brightness == 0 && contrast == 0 && saturation == 0 && warmth == 0) {
      return null;
    }
    final out = await _outPath('grade');
    // eq: brightness ∈ [-1..1], contrast ∈ [-2..2] (1.0 = identity),
    // saturation ∈ [0..3] (1.0 = identity) — те же диапазоны, что и в
    // FilterState.toMatrix(), просто в терминах ffmpeg.
    final eqB = brightness.clamp(-1.0, 1.0);
    final eqC = (contrast + 1.0).clamp(0.0, 2.0);
    final eqS = (saturation + 1.0).clamp(0.0, 3.0);
    // warmth не имеет прямого аналога в eq — приближаем через colorbalance
    // (сдвиг красного вверх / синего вниз в мидтонах), как в _warmthMatrix.
    final wr = (warmth * 0.30).clamp(-1.0, 1.0);
    final wb = (-warmth * 0.30).clamp(-1.0, 1.0);
    final vf = 'eq=brightness=$eqB:contrast=$eqC:saturation=$eqS'
        '${warmth != 0 ? ',colorbalance=rm=$wr:bm=$wb' : ''}';
    final ok = await _run(
      '-y -i "$inputPath" -vf "$vf" '
      '-c:v libx264 -preset veryfast -c:a copy -movflags +faststart "$out"',
    );
    if (!ok) return null;
    return File(out).existsSync() ? out : null;
  }

  /// Склеивает [paths] в один файл. Один путь возвращается как есть. При ошибке —
  /// null. Перекодирует, чтобы корректно склеить клипы с разными кодеками.
  static Future<String?> concat(List<String> paths) async {
    if (paths.isEmpty) return null;
    if (paths.length == 1) return paths.first;

    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().microsecondsSinceEpoch;
    final listFile = File('${dir.path}/vts_concat_$ts.txt');
    final buffer = StringBuffer();
    for (final p in paths) {
      // Экранируем одинарные кавычки для concat-демультиплексора ffmpeg.
      final escaped = p.replaceAll("'", r"'\''");
      buffer.writeln("file '$escaped'");
    }
    await listFile.writeAsString(buffer.toString());

    final out = await _outPath('concat');
    final ok = await _run(
      '-y -f concat -safe 0 -i "${listFile.path}" '
      '-c:v libx264 -preset veryfast -c:a aac -movflags +faststart "$out"',
    );

    try {
      if (listFile.existsSync()) listFile.deleteSync();
    } catch (_) {}

    if (!ok) return null;
    return File(out).existsSync() ? out : null;
  }
}
