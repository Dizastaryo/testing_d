import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';

class StickerModel {
  final String id;
  final String url;
  final DateTime createdAt;

  const StickerModel({
    required this.id,
    required this.url,
    required this.createdAt,
  });

  factory StickerModel.fromJson(Map<String, dynamic> j) {
    return StickerModel(
      id: j['id']?.toString() ?? '',
      url: j['url']?.toString() ?? '',
      createdAt: j['created_at'] != null
          ? DateTime.tryParse(j['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class StickerListNotifier
    extends StateNotifier<AsyncValue<List<StickerModel>>> {
  final ApiClient _api;

  StickerListNotifier(this._api) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final resp = await _api.get(ApiEndpoints.stickers);
      final list = (resp.data['data'] as List? ?? [])
          .map((e) => StickerModel.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(list);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  /// Upload [bytes] to remove-bg endpoint. Returns the processed image URL.
  Future<String> removeBg(Uint8List bytes) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: 'source.png',
        contentType: MediaType('image', 'png'),
      ),
    });
    final resp = await _api.post(
      ApiEndpoints.stickerRemoveBg,
      data: formData,
      options: Options(
        receiveTimeout: const Duration(seconds: 75),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    return resp.data['data']['url'] as String;
  }

  /// Upload composited PNG [bytes] to media, then register as sticker.
  Future<StickerModel> saveSticker(Uint8List bytes) async {
    final uploadForm = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: 'sticker.png',
        contentType: MediaType('image', 'png'),
      ),
    });
    final uploadResp =
        await _api.post(ApiEndpoints.mediaUpload, data: uploadForm);
    final mediaUrl = uploadResp.data['data']['url'] as String;

    final stickerResp = await _api.post(
      ApiEndpoints.stickers,
      data: {'url': mediaUrl},
    );
    final sticker = StickerModel.fromJson(
      stickerResp.data['data'] as Map<String, dynamic>,
    );

    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([sticker, ...current]);
    return sticker;
  }

  Future<void> deleteSticker(String id) async {
    await _api.delete(ApiEndpoints.stickerById(id));
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.where((s) => s.id != id).toList());
  }
}

final stickerListProvider =
    StateNotifierProvider<StickerListNotifier, AsyncValue<List<StickerModel>>>(
  (ref) => StickerListNotifier(ref.watch(apiClientProvider)),
);
