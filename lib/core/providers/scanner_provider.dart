import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../services/logger.dart';

String _absUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('/')) {
    return ApiEndpoints.baseUrl.replaceAll('/api/v1', '') + url;
  }
  return url;
}

// ── ScanProfile — АНОНИМНАЯ карточка, резолвнутая из BLE device hash ──────────
//
// НЕ содержит реального имени/username/профиля. Из карточки нельзя перейти в
// Профиль — это инвариант архитектуры. `ownerId` — непрозрачный идентификатор
// для действий (Spark / просмотр / блокировка), он НЕ раскрывает личность.
class ScanProfile {
  final String deviceHash;
  final String ownerId;
  final String nickname;
  final String photoUrl;
  final String text;
  final String emoji;
  final String style;

  const ScanProfile({
    required this.deviceHash,
    this.ownerId = '',
    this.nickname = '',
    this.photoUrl = '',
    this.text = '',
    this.emoji = '',
    this.style = '',
  });

  /// Имя для показа: никнейм карточки или нейтральная подпись, если он пуст.
  String get displayName => nickname.isNotEmpty ? nickname : 'Карточка';

  /// Карточка считается заполненной, если у неё есть фото (обязательное поле).
  bool get isFilled => photoUrl.isNotEmpty;

  factory ScanProfile.fromJson(Map<String, dynamic> j) => ScanProfile(
        deviceHash: j['device_hash']?.toString() ?? '',
        ownerId: j['owner_id']?.toString() ?? '',
        nickname: j['nickname']?.toString() ?? '',
        photoUrl: _absUrl(j['photo_url']?.toString()),
        text: j['text']?.toString() ?? '',
        emoji: j['emoji']?.toString() ?? '',
        style: j['style']?.toString() ?? '',
      );
}

// ── Batch resolve device hashes → anonymous cards ────────────────────────────

/// Консентный резолв РЕАЛЬНОГО владельца браслета по физическому NFC-касанию —
/// мост в Профиль (Фаза 4/5). Отличается от анонимного ambient-скана: касание =
/// явное согласие. Возвращает username владельца или null. НЕ использовать для
/// ambient-сканера — там только анонимные карточки.
Future<String?> resolveUsernameByDevice(ApiClient api, String deviceHash) async {
  if (deviceHash.isEmpty) return null;
  try {
    final res = await api.get(ApiEndpoints.userByDevice(deviceHash));
    final raw = res.data;
    final data =
        (raw is Map ? (raw['data'] ?? raw) : raw) as Map<String, dynamic>? ?? {};
    final username = data['username']?.toString() ?? '';
    return username.isEmpty ? null : username;
  } catch (e, st) {
    appLog.error('[scanner] resolveUsernameByDevice failed', e, st);
    return null;
  }
}

Future<Map<String, ScanProfile>> resolveScanProfiles(
    ApiClient api, List<String> deviceHashes) async {
  if (deviceHashes.isEmpty) return {};
  try {
    final res = await api.post(
      ApiEndpoints.scannerResolve,
      data: {'device_hashes': deviceHashes},
    );
    final raw = res.data;
    final data =
        (raw is Map ? (raw['data'] ?? raw) : raw) as Map<String, dynamic>? ?? {};
    final profiles = (data['profiles'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ScanProfile.fromJson)
        .toList();
    return {for (final p in profiles) p.deviceHash: p};
  } catch (e, st) {
    appLog.error('[scanner] resolveScanProfiles failed', e, st);
    return {};
  }
}
