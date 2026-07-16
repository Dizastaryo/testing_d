import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/sbor.dart';

/// Ближайший предстоящий сбор — живая строка на карточке «Сервисы» (§06):
/// время · место · сколько идут. Бэк (`GET /sbory/nearest`) отдаёт `data:null`,
/// когда впереди ничего нет — тогда карточка показывает обычный CTA.
final nearestSborProvider = FutureProvider.autoDispose<Sbor?>((ref) async {
  final api = ref.watch(apiClientProvider);
  final r = await api.get('/sbory/nearest');
  final data = (r.data is Map) ? (r.data as Map)['data'] : null;
  if (data is Map) {
    return Sbor.fromJson(data.cast<String, dynamic>());
  }
  return null;
});
