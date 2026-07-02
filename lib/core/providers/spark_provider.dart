import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/spark.dart';

/// Отправляет Spark получателю [receiverId]. [proofDeviceHash] — public_id_hex
/// браслета получателя, который отправитель видит в BLE-эфире (доказательство
/// близости). Бросает [SparkError] при бизнес-ошибках (нет браслета рядом,
/// лимит на сегодня, себе нельзя).
Future<void> sendSpark(
  WidgetRef ref, {
  required String receiverId,
  required String proofDeviceHash,
}) async {
  final api = ref.read(apiClientProvider);
  try {
    await api.post(ApiEndpoints.sparksSend, data: {
      'receiver_id': receiverId,
      'proof_device_hash': proofDeviceHash,
    });
  } on DioException catch (e) {
    final msg = e.response?.data?['error']?.toString() ?? 'Не удалось отправить Spark';
    throw SparkError(msg);
  }
}

class SparkError implements Exception {
  final String message;
  const SparkError(this.message);
  @override
  String toString() => message;
}

/// Список людей, отправивших Spark текущему пользователю (только владельцу).
final sparkSendersProvider =
    FutureProvider.autoDispose<List<SparkSender>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get(ApiEndpoints.sparksSenders);
  final data = res.data is Map ? (res.data['data'] ?? res.data) : res.data;
  return (data['items'] as List? ?? [])
      .whereType<Map<String, dynamic>>()
      .map(SparkSender.fromJson)
      .toList();
});
