import 'dart:io';

/// Mobile / desktop fallback. Writes to the documents directory.
/// TODO: integrate share_plus + path_provider when we ship mobile.
Future<void> saveExport({required List<int> bytes, required String filename}) async {
  final dir = Directory.systemTemp;
  final f = File('${dir.path}/$filename');
  await f.writeAsBytes(bytes);
}
