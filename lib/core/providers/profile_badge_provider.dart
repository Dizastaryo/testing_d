import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';

/// Счётчик «требует внимания» на своём профиле (§05): входящие запросы доступа
/// + follow-запросы. Питает бейдж на иконке «Профиль» в нижнем меню.
/// Best-effort: любая ошибка → 0 (бейдж просто не показывается).
final profileBadgeProvider = FutureProvider.autoDispose<int>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final r = await api.get('/users/me/badge');
    final data = (r.data is Map) ? (r.data as Map)['data'] : null;
    if (data is Map) {
      return (data['total'] as num?)?.toInt() ?? 0;
    }
  } catch (_) {
    // Бейдж не критичен — молча прячем при любой ошибке.
  }
  return 0;
});

/// Число входящих follow-запросов — для бейджа на пункте «Запросы на подписку»
/// в настройках (раньше пункт был без счётчика). Best-effort → 0.
final followRequestsCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final r = await api.get(ApiEndpoints.myFollowRequests);
    final data =
        r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
    if (data is List) return data.length;
  } catch (_) {}
  return 0;
});
