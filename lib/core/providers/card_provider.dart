import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import 'scanner_provider.dart';

// Карточка/Сканер: просмотры (view-as-event), симметрия видимости (кто смотрел /
// кто спаркнул), card-level блокировка. Все объекты «другого» человека —
// это его КАРТОЧКА (ScanProfile), никогда реальная личность.

/// Запись в списке «кто смотрел / кто отправил Spark» (симметрия видимости).
class CardAudienceEntry {
  final ScanProfile card;
  final int viewCount;
  final DateTime? lastViewedAt;
  final bool sparked;
  final DateTime? lastSparkedAt;

  const CardAudienceEntry({
    required this.card,
    this.viewCount = 0,
    this.lastViewedAt,
    this.sparked = false,
    this.lastSparkedAt,
  });

  factory CardAudienceEntry.fromJson(Map<String, dynamic> j) {
    final cardJson = (j['card'] as Map?)?.cast<String, dynamic>() ?? {};
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return CardAudienceEntry(
      card: ScanProfile.fromJson(cardJson),
      viewCount: (j['view_count'] as num?)?.toInt() ?? 0,
      lastViewedAt: parse(j['last_viewed_at']),
      sparked: (j['sparked'] as bool?) ?? false,
      lastSparkedAt: parse(j['last_sparked_at']),
    );
  }
}

/// Статистика карточки — «тебя посмотрели N раз».
class CardStats {
  final int viewsTotal;
  final int viewersCount;
  final int sparksCount;

  /// Просмотры за последние 7 дней (от старого к новому) — для бар-чарта.
  final List<int> days;

  const CardStats({
    this.viewsTotal = 0,
    this.viewersCount = 0,
    this.sparksCount = 0,
    this.days = const [],
  });

  factory CardStats.fromJson(Map<String, dynamic> j) => CardStats(
        viewsTotal: (j['views_total'] as num?)?.toInt() ?? 0,
        viewersCount: (j['viewers_count'] as num?)?.toInt() ?? 0,
        sparksCount: (j['sparks_count'] as num?)?.toInt() ?? 0,
        days: (j['days'] as List?)
                ?.map((e) => (e as num?)?.toInt() ?? 0)
                .toList() ??
            const [],
      );
}

Map<String, dynamic> _unwrap(dynamic raw) =>
    (raw is Map ? (raw['data'] ?? raw) : raw) as Map<String, dynamic>? ?? {};

/// Открыть чужую карточку — фиксирует просмотр (событие, видимое владельцу) и
/// возвращает саму карточку. Требует браслета; при блокировке вернёт null.
Future<ScanProfile?> openCard(ApiClient api, String ownerId) async {
  final res = await api.post(ApiEndpoints.cardOpen(ownerId));
  final data = _unwrap(res.data);
  if (data.isEmpty) return null;
  return ScanProfile.fromJson(data);
}

/// «Кто смотрел / кто отправил Spark» — список карточек (симметрия п.4).
Future<List<CardAudienceEntry>> fetchCardAudience(ApiClient api,
    {int limit = 50, int offset = 0}) async {
  final res = await api.get(ApiEndpoints.cardAudience,
      queryParameters: {'limit': limit, 'offset': offset});
  final data = _unwrap(res.data);
  return (data['items'] as List? ?? [])
      .whereType<Map<String, dynamic>>()
      .map(CardAudienceEntry.fromJson)
      .toList();
}

/// Статистика карточки.
Future<CardStats> fetchCardStats(ApiClient api) async {
  final res = await api.get(ApiEndpoints.cardStats);
  return CardStats.fromJson(_unwrap(res.data));
}

/// Заблокировать человека по его карточке (бессрочно). true — успех.
Future<bool> blockCard(ApiClient api, String ownerId) async {
  try {
    await api.post(ApiEndpoints.cardBlock, data: {'owner_id': ownerId});
    return true;
  } on DioException {
    return false;
  }
}

/// Снять блокировку (может только заблокировавший).
Future<void> unblockCard(ApiClient api, String ownerId) async {
  await api.delete(ApiEndpoints.cardUnblock(ownerId));
}

/// Карточки заблокированных владельцем.
Future<List<CardAudienceEntry>> fetchCardBlocks(ApiClient api,
    {int limit = 50, int offset = 0}) async {
  final res = await api.get(ApiEndpoints.cardBlocks,
      queryParameters: {'limit': limit, 'offset': offset});
  final data = _unwrap(res.data);
  return (data['items'] as List? ?? [])
      .whereType<Map<String, dynamic>>()
      .map((m) => CardAudienceEntry.fromJson({'card': m['card'] ?? m}))
      .toList();
}
