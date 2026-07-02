import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/contact.dart';
import '../utils/phone.dart';

/// Матчинг контактов телефона по приватным SHA-256 хэшам (Фаза 2).
///
/// Чтение самой адресной книги (нативный пакет) делается в UI-слое и передаёт
/// сюда уже список сырых номеров — провайдер только нормализует, хэширует и
/// отправляет ХЭШИ на сервер. Сырые номера наружу не уходят.
class ContactsNotifier extends StateNotifier<AsyncValue<List<ContactMatch>>> {
  final ApiClient _api;

  ContactsNotifier(this._api) : super(const AsyncValue.data([]));

  /// Принимает сырые номера из книги, шлёт их хэши на /contacts/sync и
  /// сохраняет найденных пользователей SeeU.
  Future<void> sync(List<String> rawPhones) async {
    state = const AsyncValue.loading();
    try {
      final hashes = <String>{};
      for (final p in rawPhones) {
        final h = PhoneUtil.normalizeAndHash(p);
        if (h.isNotEmpty) hashes.add(h);
      }

      if (hashes.isEmpty) {
        state = const AsyncValue.data([]);
        return;
      }

      final res = await _api.post(
        ApiEndpoints.contactsSync,
        data: {'hashes': hashes.toList()},
      );
      final data = res.data is Map ? (res.data['data'] ?? res.data) : res.data;
      final items = (data['items'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ContactMatch.fromJson)
          .toList();
      state = AsyncValue.data(items);
    } on DioException catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final contactsProvider =
    StateNotifierProvider<ContactsNotifier, AsyncValue<List<ContactMatch>>>(
  (ref) => ContactsNotifier(ref.read(apiClientProvider)),
);
