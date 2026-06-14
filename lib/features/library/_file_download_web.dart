// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
// Conditional import: only loaded on web. Triggers a browser download via
// an invisible anchor with a download attribute.

import 'dart:html' as html;

Future<void> saveDownload({
  required String url,
  required String filename,
  void Function(int received, int total)? onProgress,
}) async {
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..target = '_blank'
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
