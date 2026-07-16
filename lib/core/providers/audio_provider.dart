import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/audio_track.dart';

// ── Feed providers ──────────────────────────────────────────────────────────

/// Public approved audio feed.
final audioFeedProvider = FutureProvider.autoDispose<List<AudioTrack>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final r = await api.get(ApiEndpoints.audioTracks, queryParameters: {'limit': '50', 'page': '1'});
  final data = r.data['data'];
  final list = data is List ? data : (data as Map?)?.values.first as List? ?? [];
  return list.map((e) => AudioTrack.fromJson(e as Map<String, dynamic>)).toList();
});

/// Current user's own tracks (any status/visibility).
final myTracksProvider = FutureProvider.autoDispose<List<AudioTrack>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final r = await api.get(ApiEndpoints.myAudioTracks);
  final data = r.data['data'];
  final list = data is List ? data : <dynamic>[];
  return list.map((e) => AudioTrack.fromJson(e as Map<String, dynamic>)).toList();
});

/// Tracks saved by the current user.
final savedTracksProvider = FutureProvider.autoDispose<List<AudioTrack>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final r = await api.get(ApiEndpoints.savedAudioTracks);
  final data = r.data['data'];
  final list = data is List ? data : <dynamic>[];
  return list.map((e) => AudioTrack.fromJson(e as Map<String, dynamic>)).toList();
});

/// «Недавно искали» — хранится на устройстве: серверу история запросов
/// Аудиотеки не нужна, а человеку удобно вернуться к своему же запросу.
class AudioSearchHistoryNotifier extends StateNotifier<List<String>> {
  static const _key = 'audio_search_history';
  static const _max = 8;

  AudioSearchHistoryNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getStringList(_key) ?? [];
  }

  Future<void> add(String query) async {
    final q = query.trim();
    if (q.length < 2) return;
    final updated = [q, ...state.where((s) => s != q)];
    if (updated.length > _max) updated.removeRange(_max, updated.length);
    state = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, updated);
  }

  Future<void> clear() async {
    state = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

final audioSearchHistoryProvider =
    StateNotifierProvider<AudioSearchHistoryNotifier, List<String>>(
  (ref) => AudioSearchHistoryNotifier(),
);

/// «Продолжить» на главной: недослушанные книги и подкасты, свежее сверху.
/// Пусто — это нормальное состояние, а не ошибка: блок просто не рисуется.
final continueListeningProvider =
    FutureProvider.autoDispose<List<AudioTrack>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final r = await api.get(ApiEndpoints.continueListening,
        queryParameters: {'limit': '10'});
    final data = r.data['data'];
    final list = data is List ? data : <dynamic>[];
    return list
        .map((e) => AudioTrack.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
});

/// Сохранение позиции прослушивания. Зовётся периодически во время
/// воспроизведения и на паузе/выходе — чтобы книгу можно было продолжить.
Future<void> saveAudioPosition(
  ApiClient api, {
  required String trackId,
  required int positionSeconds,
  required int durationSeconds,
  bool completed = false,
}) async {
  try {
    await api.put(ApiEndpoints.audioTrackPosition(trackId), data: {
      'position_seconds': positionSeconds,
      'duration_seconds': durationSeconds,
      'completed': completed,
    });
  } catch (_) {
    // Позиция — не критично: потеряли одно сохранение, следующее догонит.
  }
}

/// С какой секунды продолжать этот трек. 0 — начинать сначала.
Future<int> fetchAudioPosition(ApiClient api, String trackId) async {
  try {
    final r = await api.get(ApiEndpoints.audioTrackPosition(trackId));
    final data = r.data?['data'];
    if (data is! Map) return 0;
    if (data['completed'] == true) return 0; // дослушал — начинаем заново
    return (data['position_seconds'] as num?)?.toInt() ?? 0;
  } catch (_) {
    return 0;
  }
}

/// «Недавнее» — история прослушивания вместе с временем (`played_at`),
/// чтобы её можно было сгруппировать по дням: «Сегодня / Вчера / На неделе».
final recentTracksProvider =
    FutureProvider.autoDispose<List<AudioTrack>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final r = await api.get(ApiEndpoints.recentAudioTracks,
      queryParameters: {'limit': '50'});
  final data = r.data['data'];
  final list = data is List ? data : <dynamic>[];
  return list
      .map((e) => AudioTrack.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Trending tracks (sorted by engagement score).
final trendingTracksProvider = FutureProvider.autoDispose<List<AudioTrack>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final r = await api.get(ApiEndpoints.trendingAudioTracks, queryParameters: {'limit': '20'});
  final data = r.data['data'];
  final list = data is List ? data : <dynamic>[];
  return list.map((e) => AudioTrack.fromJson(e as Map<String, dynamic>)).toList();
});

// ── Upload state ─────────────────────────────────────────────────────────────

class AudioUploadState {
  final bool isUploading;
  final double progress; // 0.0 – 1.0
  final String? error;
  final AudioTrack? uploaded;

  const AudioUploadState({
    this.isUploading = false,
    this.progress = 0,
    this.error,
    this.uploaded,
  });

  AudioUploadState copyWith({
    bool? isUploading,
    double? progress,
    String? error,
    AudioTrack? uploaded,
  }) =>
      AudioUploadState(
        isUploading: isUploading ?? this.isUploading,
        progress: progress ?? this.progress,
        error: error,
        uploaded: uploaded ?? this.uploaded,
      );
}

class AudioUploadNotifier extends StateNotifier<AudioUploadState> {
  final ApiClient _api;

  AudioUploadNotifier(this._api) : super(const AudioUploadState());

  Future<AudioTrack?> upload({
    required File file,
    required String title,
    String artist = '',
    String album = '',
    String description = '',
    String genre = '',
    String category = 'music',
    String subcategory = '',
    String mood = '',
    String visibility = 'public',

    /// Волна и длительность, посчитанные на устройстве до отправки.
    /// Нужны потому, что серверную волну считает отдельный процесс
    /// media_worker: если он не поднят, трек остался бы без волны навсегда.
    List<double>? waveform,
    int durationSeconds = 0,
  }) async {
    state = const AudioUploadState(isUploading: true, progress: 0);
    try {
      final formData = FormData.fromMap({
        if (waveform != null && waveform.isNotEmpty)
          'waveform': jsonEncode(
            // Два знака после запятой — картинке хватает, а тело запроса
            // втрое меньше.
            [for (final p in waveform) double.parse(p.toStringAsFixed(2))],
          ),
        if (durationSeconds > 0) 'duration_seconds': '$durationSeconds',
        'file': await MultipartFile.fromFile(file.path, filename: file.path.split('/').last),
        'title': title,
        'artist': artist,
        'album': album,
        'description': description,
        'genre': genre,
        'category': category,
        'subcategory': subcategory,
        'mood': mood,
        'visibility': visibility,
      });

      // Use Dio directly so we can track sendProgress.
      // The underlying Dio instance is accessible via the ApiClient wrapper.
      final dio = Dio(BaseOptions(
        baseUrl: ApiEndpoints.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/json'},
      ));
      final token = await _api.getAccessToken();
      if (token != null && token.isNotEmpty) {
        dio.options.headers['Authorization'] = 'Bearer $token';
      }

      final resp = await dio.post(
        ApiEndpoints.audioTracksUpload,
        data: formData,
        onSendProgress: (sent, total) {
          if (total > 0 && mounted) {
            state = state.copyWith(isUploading: true, progress: sent / total);
          }
        },
        options: Options(
          sendTimeout: const Duration(minutes: 10),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );

      final track = AudioTrack.fromJson(resp.data['data']);
      if (mounted) {
        state = AudioUploadState(isUploading: false, progress: 1.0, uploaded: track);
      }
      return track;
    } on DioException catch (e) {
      final raw = e.response?.data?['error']?.toString() ?? e.message ?? '';
      debugPrint('[AudioUpload] DioException: $raw');
      if (mounted) state = AudioUploadState(error: _friendlyError(raw, e));
      return null;
    } catch (e) {
      debugPrint('[AudioUpload] error: $e');
      if (mounted) {
        state = AudioUploadState(error: 'Не удалось загрузить трек. Проверьте файл и попробуйте ещё раз.');
      }
      return null;
    }
  }

  void reset() => state = const AudioUploadState();

  static String _friendlyError(String raw, DioException e) {
    if (raw.contains('file too large') || raw.contains('too large')) {
      return 'Файл слишком большой. Максимальный размер — 100 МБ.';
    }
    if (raw.contains('unsupported format')) {
      return 'Неподдерживаемый формат. Поддерживаются MP3, M4A, AAC, WAV, OGG.';
    }
    if (raw.contains('audio file is required')) {
      return 'Выберите аудиофайл.';
    }
    if (raw.contains('title is required') || raw.contains('Title')) {
      return 'Введите название трека.';
    }
    if (raw.contains('currently unavailable') || raw.contains('not configured')) {
      return 'Сервис загрузки временно недоступен. Попробуйте позже.';
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Время ожидания истекло. Проверьте интернет-соединение и попробуйте ещё раз.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Нет соединения с сервером. Проверьте интернет.';
    }
    return 'Не удалось загрузить трек. Проверьте файл и попробуйте ещё раз.';
  }
}

final audioUploadProvider =
    StateNotifierProvider.autoDispose<AudioUploadNotifier, AudioUploadState>((ref) {
  return AudioUploadNotifier(ref.watch(apiClientProvider));
});
