// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
// Conditional import: only loaded on web. dart:html is the most direct way to
// trigger a browser download. Migrate to package:web when stable.

import 'dart:html' as html;
import 'dart:typed_data';

/// Triggers a browser download by creating an anchor with a Blob URL.
Future<void> saveExport({required List<int> bytes, required String filename}) async {
  final blob = html.Blob([Uint8List.fromList(bytes)], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
