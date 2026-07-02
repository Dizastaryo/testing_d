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
