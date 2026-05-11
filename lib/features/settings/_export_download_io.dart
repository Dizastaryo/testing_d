import 'dart:io';

import 'package:share_plus/share_plus.dart';

/// Mobile / desktop fallback. Сохраняем во временную директорию + сразу
/// открываем системный share-sheet, чтобы юзер сохранил/переслал куда нужно.
/// На Android — Files / Drive / Gmail; на iOS — Files / AirDrop / Mail.
Future<void> saveExport({required List<int> bytes, required String filename}) async {
  final dir = Directory.systemTemp;
  final f = File('${dir.path}/$filename');
  await f.writeAsBytes(bytes);
  // share_plus сам резолвит правильный share-action на mobile vs desktop.
  await Share.shareXFiles(
    [XFile(f.path, name: filename)],
    subject: 'SeeU export',
  );
}
