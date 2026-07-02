import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/audio_category.dart';
import '../models/audio_track.dart';

// ── Discovery home ────────────────────────────────────────────────────────────

class DiscoveryData {
  final List<AudioTrack> trendingTracks;
  final List<AudioTrack> newTracks;
  final List<AudioTrack> recentlyPlayed;
  final List<AudioTrack> savedPreview;
  final List<AudioTrack> memeSounds;
  final List<AudioTrack> videoSounds;
  final List<AudioTrack> originalSounds;
  final List<AudioCategoryModel> popularCategories;

  const DiscoveryData({
    this.trendingTracks = const [],
    this.newTracks = const [],
    this.recentlyPlayed = const [],
    this.savedPreview = const [],
    this.memeSounds = const [],
    this.videoSounds = const [],
    this.originalSounds = const [],
    this.popularCategories = const [],
  });

  factory DiscoveryData.fromJson(Map<String, dynamic> j) {
    List<AudioTrack> parseTracks(String key) =>
        (j[key] as List? ?? [])
            .map((e) => AudioTrack.fromJson(e as Map<String, dynamic>))
            .toList();

    List<AudioCategoryModel> parseCats(String key) =>
        (j[key] as List? ?? [])
            .map((e) => AudioCategoryModel.fromJson(e as Map<String, dynamic>))
            .toList();

    return DiscoveryData(
      trendingTracks: parseTracks('trending_tracks'),
      newTracks: parseTracks('new_tracks'),
      recentlyPlayed: parseTracks('recently_played'),
      savedPreview: parseTracks('saved_preview'),
      memeSounds: parseTracks('meme_sounds'),
      videoSounds: parseTracks('video_sounds'),
      originalSounds: parseTracks('original_sounds'),
      popularCategories: parseCats('popular_categories'),
    );
  }
}

final audioDiscoveryProvider =
    FutureProvider.autoDispose<DiscoveryData>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final r = await api.get(ApiEndpoints.audioDiscovery);
    final data = r.data['data'] as Map<String, dynamic>? ?? {};
    return DiscoveryData.fromJson(data);
  } on DioException catch (e) {
    debugPrint('[audioDiscoveryProvider] DioException: ${e.message}');
    rethrow;
  }
});

// ── Browse categories ─────────────────────────────────────────────────────────

final audioCategoriesProvider =
    FutureProvider.autoDispose<List<AudioCategoryModel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final r = await api.get(ApiEndpoints.audioBrowseCategories);
    final data = r.data['data'] as Map<String, dynamic>? ?? {};
    final list = data['categories'] as List? ?? [];
    return list
        .map((e) => AudioCategoryModel.fromJson(e as Map<String, dynamic>))
        .toList();
  } on DioException catch (e) {
    debugPrint('[audioCategoriesProvider] DioException: ${e.message}');
    // Fallback to static list when offline or backend unavailable.
    return kAudioCategories;
  }
});

// ── Category tracks ───────────────────────────────────────────────────────────

class CategoryTracksParams {
  final String category;
  final String subcategory;
  final String sort;

  const CategoryTracksParams({
    required this.category,
    this.subcategory = '',
    this.sort = 'trending',
  });

  @override
  bool operator ==(Object other) =>
      other is CategoryTracksParams &&
      other.category == category &&
      other.subcategory == subcategory &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(category, subcategory, sort);
}

class CategoryTracksData {
  final AudioCategoryModel category;
  final List<AudioTrack> tracks;
  final int total;
  final bool hasNextPage;

  const CategoryTracksData({
    required this.category,
    required this.tracks,
    this.total = 0,
    this.hasNextPage = false,
  });

  factory CategoryTracksData.fromJson(
      Map<String, dynamic> j, AudioCategoryModel fallback) {
    final catJson = j['category'] as Map<String, dynamic>?;
    final cat = catJson != null
        ? AudioCategoryModel.fromJson(catJson)
        : fallback;
    final tracks = (j['tracks'] as List? ?? [])
        .map((e) => AudioTrack.fromJson(e as Map<String, dynamic>))
        .toList();
    return CategoryTracksData(
      category: cat,
      tracks: tracks,
      total: (j['total'] as num?)?.toInt() ?? tracks.length,
      hasNextPage: j['has_next_page'] == true,
    );
  }
}

final audioCategoryTracksProvider =
    FutureProvider.autoDispose.family<CategoryTracksData, CategoryTracksParams>(
        (ref, params) async {
  final api = ref.watch(apiClientProvider);
  final fallback = findCategory(params.category) ??
      AudioCategoryModel(
        id: params.category,
        titleRu: params.category,
        titleEn: params.category,
        description: '',
        icon: 'music_note',
      );
  try {
    final r = await api.get(
      ApiEndpoints.audioBrowseCategoryDetail(params.category),
      queryParameters: {
        if (params.subcategory.isNotEmpty) 'subcategory': params.subcategory,
        'sort': params.sort,
        'limit': '20',
      },
    );
    final data = r.data['data'] as Map<String, dynamic>? ?? {};
    return CategoryTracksData.fromJson(data, fallback);
  } on DioException catch (e) {
    debugPrint('[audioCategoryTracksProvider] DioException: ${e.message}');
    rethrow;
  }
});

// ── Search ────────────────────────────────────────────────────────────────────

class AudioSearchResult {
  final List<AudioTrack> tracks;
  final int total;

  const AudioSearchResult({required this.tracks, this.total = 0});
}

class AudioSearchParams {
  final String query;
  final String category;
  final String sort;

  const AudioSearchParams({
    this.query = '',
    this.category = '',
    this.sort = 'trending',
  });

  @override
  bool operator ==(Object other) =>
      other is AudioSearchParams &&
      other.query == query &&
      other.category == category &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(query, category, sort);
}

final audioSearchProvider =
    FutureProvider.autoDispose.family<AudioSearchResult, AudioSearchParams>(
        (ref, params) async {
  // Require at least 2 chars or a category.
  if (params.query.length < 2 && params.category.isEmpty) {
    return const AudioSearchResult(tracks: []);
  }
  final api = ref.watch(apiClientProvider);
  try {
    final r = await api.get(
      ApiEndpoints.audioSearch,
      queryParameters: {
        if (params.query.isNotEmpty) 'q': params.query,
        if (params.category.isNotEmpty) 'category': params.category,
        'sort': params.sort,
        'limit': '30',
      },
    );
    final data = r.data['data'] as Map<String, dynamic>? ?? {};
    final tracks = (data['tracks'] as List? ?? [])
        .map((e) => AudioTrack.fromJson(e as Map<String, dynamic>))
        .toList();
    return AudioSearchResult(
      tracks: tracks,
      total: (data['total'] as num?)?.toInt() ?? tracks.length,
    );
  } on DioException catch (e) {
    debugPrint('[audioSearchProvider] DioException: ${e.message}');
    rethrow;
  }
});
