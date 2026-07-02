import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mobile: скачивает файл через Dio с отслеживанием прогресса.
/// Сохраняет в applicationDocumentsDirectory.
/// onProgress(received, total) — вызывается по мере скачивания.
Future<void> saveDownload({
  required String url,
  required String filename,
  void Function(int received, int total)? onProgress,
}) async {
  final dir = await getApplicationDocumentsDirectory();
  // Sanitize filename
  final safe = filename.replaceAll(RegExp(r'[/\:*?"<>|]'), '_');
  final savePath = '${dir.path}/$safe';

  final dio = Dio(BaseOptions(
    receiveTimeout: const Duration(minutes: 10),
    connectTimeout: const Duration(seconds: 30),
  ));

  try {
    await dio.download(
      url,
      savePath,
      onReceiveProgress: onProgress,
    );

    // Попытка открыть файл через системный обработчик
    final file = File(savePath);
    if (await file.exists()) {
      final uri = Uri.file(savePath);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw 'Файл сохранён: $savePath';
      }
    }
  } catch (e) {
    // Fallback: открыть оригинальный URL в браузере
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw 'Не удалось открыть файл';
    }
  }
}
