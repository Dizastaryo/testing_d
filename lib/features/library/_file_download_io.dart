import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mobile: скачивает файл через Dio с отслеживанием прогресса.
/// Сохраняет в applicationDocumentsDirectory.
/// onProgress(received, total) — вызывается по мере скачивания.
///
/// Возвращает `true`, только если файл реально лёг на устройство; `false` —
/// если пришлось открыть оригинал в браузере (скачивание не удалось). Раньше
/// оба исхода выглядели одинаково успешными, и вызывающий показывал «Файл
/// сохранён» даже когда ничего не сохранилось.
Future<bool> saveDownload({
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

    if (await File(savePath).exists()) {
      // Файл на диске — это успех. Открыть системным обработчиком пробуем, но
      // неудача открытия НЕ отменяет факт сохранения.
      await launchUrl(Uri.file(savePath),
          mode: LaunchMode.externalApplication);
      return true;
    }
    // download вернулся, но файла нет — уходим в браузерный fallback.
  } catch (_) {
    // Скачать не удалось — ниже пробуем открыть оригинал в браузере.
  }

  // Fallback: открыть оригинальный URL в браузере (локально НЕ сохранено).
  if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
    throw 'Не удалось открыть файл';
  }
  return false;
}
