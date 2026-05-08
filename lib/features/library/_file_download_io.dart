import 'package:url_launcher/url_launcher.dart';

/// Mobile fallback: open the file URL in the system browser. Real on-device
/// downloads (with progress, scoped storage etc.) require dio + path_provider —
/// will add when the mobile flow is prioritised.
Future<void> saveDownload({required String url, required String filename}) async {
  final uri = Uri.parse(url);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw 'launch failed';
  }
}
