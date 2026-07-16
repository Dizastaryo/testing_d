import '../api/api_endpoints.dart';

String _absUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('/')) {
    return ApiEndpoints.baseUrl.replaceAll('/api/v1', '') + url;
  }
  return url;
}

/// Отправитель Spark 🔥 — виден получателю ПО СВОЕЙ КАРТОЧКЕ (не по реальному
/// имени/профилю, п.3). GET /sparks/senders.
class SparkSender {
  final String ownerId;
  final String deviceHash;
  final String nickname;
  final String photoUrl;
  final String text;
  final DateTime sentAt;

  const SparkSender({
    required this.ownerId,
    this.deviceHash = '',
    this.nickname = '',
    this.photoUrl = '',
    this.text = '',
    required this.sentAt,
  });

  String get displayName => nickname.isNotEmpty ? nickname : 'Карточка';

  factory SparkSender.fromJson(Map<String, dynamic> j) => SparkSender(
        ownerId: j['owner_id']?.toString() ?? '',
        deviceHash: j['device_hash']?.toString() ?? '',
        nickname: j['nickname']?.toString() ?? '',
        photoUrl: _absUrl(j['photo_url']?.toString()),
        text: j['text']?.toString() ?? '',
        sentAt: j['sent_at'] != null
            ? DateTime.tryParse(j['sent_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );
}
