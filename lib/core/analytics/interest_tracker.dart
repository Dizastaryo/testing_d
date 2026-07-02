import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';

/// Posts one interest event. Injected so the tracker can be unit-tested without
/// a live network. Production wiring delegates to [ApiClient.post].
typedef InterestPoster = Future<void> Function(
    String path, Map<String, dynamic> body);

/// Best-effort, fire-and-forget capture of user-interest signals that the
/// backend uses to rank Интересное (Explore).
///
/// Hard rules (see Task B):
///   * NEVER throws into the UI and NEVER blocks navigation/playback — every
///     send is unawaited and wrapped; failures are swallowed (debug-logged).
///   * Impressions are de-duped per screen session and capped, so scrolling a
///     grid can't spam the endpoint.
class InterestTracker {
  InterestTracker(ApiClient api)
      : _post = ((path, body) => api.post(path, data: body));

  /// Test seam: inject a fake poster (e.g. one that throws or records calls).
  @visibleForTesting
  InterestTracker.withPoster(this._post);

  final InterestPoster _post;

  // De-dup impressions within one Explore screen session.
  final Set<String> _impressed = <String>{};
  static const int _impressionCap = 80;

  /// Call when a fresh Explore screen session starts (e.g. initState) so
  /// impressions are counted per visit, not for the whole app lifetime.
  void resetImpressions() => _impressed.clear();

  /// Records [eventType]. Returns immediately; the network write runs detached.
  void track({
    required String eventType,
    required String entityType,
    String? entityId,
    String? source,
    String? authorId,
    String? categoryId,
    int? durationMs,
    int? position,
    Map<String, dynamic>? metadata,
  }) {
    unawaited(_send(
      eventType: eventType,
      entityType: entityType,
      entityId: entityId,
      source: source,
      authorId: authorId,
      categoryId: categoryId,
      durationMs: durationMs,
      position: position,
      metadata: metadata,
    ));
  }

  /// Records an `explore_impression` once per (entityType,entityId) per session,
  /// capped at [_impressionCap]. No-ops on duplicates / over cap.
  void impression({
    required String entityType,
    required String entityId,
    String? authorId,
    String source = 'explore',
    Map<String, dynamic>? metadata,
  }) {
    if (entityId.isEmpty) return;
    if (_impressed.length >= _impressionCap) return;
    if (!_impressed.add('$entityType:$entityId')) return;
    track(
      eventType: 'explore_impression',
      entityType: entityType,
      entityId: entityId,
      authorId: authorId,
      source: source,
      metadata: metadata,
    );
  }

  Future<void> _send({
    required String eventType,
    required String entityType,
    String? entityId,
    String? source,
    String? authorId,
    String? categoryId,
    int? durationMs,
    int? position,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _post(ApiEndpoints.interestEvents, {
        'event_type': eventType,
        'entity_type': entityType,
        if (entityId != null && entityId.isNotEmpty) 'entity_id': entityId,
        if (source != null && source.isNotEmpty) 'source': source,
        if (authorId != null && authorId.isNotEmpty) 'author_id': authorId,
        if (categoryId != null && categoryId.isNotEmpty)
          'category_id': categoryId,
        if (durationMs != null && durationMs > 0) 'duration_ms': durationMs,
        if (position != null && position > 0) 'position': position,
        if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
      });
    } catch (e) {
      // Best-effort: an interest signal must never break the app.
      if (kDebugMode) debugPrint('[interest] dropped $eventType: $e');
    }
  }
}

final interestTrackerProvider = Provider<InterestTracker>((ref) {
  return InterestTracker(ref.watch(apiClientProvider));
});
