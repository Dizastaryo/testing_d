import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/notification.dart';
import 'realtime_provider.dart';

class NotificationState {
  final List<AppNotification> notifications;
  final bool isLoading;
  final int unreadCount;
  final String? error;

  const NotificationState({
    this.notifications = const [],
    this.isLoading = false,
    this.unreadCount = 0,
    this.error,
  });

  NotificationState copyWith({
    List<AppNotification>? notifications,
    bool? isLoading,
    int? unreadCount,
    String? error,
  }) {
    return NotificationState(
      notifications: notifications ?? this.notifications,
      isLoading: isLoading ?? this.isLoading,
      unreadCount: unreadCount ?? this.unreadCount,
      error: error,
    );
  }
}

class NotificationNotifier extends StateNotifier<NotificationState> {
  final ApiClient _api;
  final Ref _ref;
  ProviderSubscription<AsyncValue<RealtimeEvent>>? _wsSub;

  NotificationNotifier(this._api, this._ref)
      : super(const NotificationState()) {
    loadNotifications();
    _listenRealtime();
  }

  /// Subscribe to the realtime channel so a push from the server prepends
  /// the notification into our state without a manual refresh.
  void _listenRealtime() {
    _wsSub = _ref.listen<AsyncValue<RealtimeEvent>>(
      realtimeEventsProvider,
      (prev, next) {
        next.whenData((evt) {
          if (evt.type != 'notification' || evt.payload is! Map) return;
          try {
            final n = AppNotification.fromJson(
                (evt.payload as Map).cast<String, dynamic>());
            state = state.copyWith(
              notifications: [n, ...state.notifications],
              unreadCount: state.unreadCount + (n.isRead ? 0 : 1),
            );
          } catch (_) {/* malformed payload — ignore */}
        });
      },
    );
  }

  @override
  void dispose() {
    _wsSub?.close();
    super.dispose();
  }

  Future<void> loadNotifications() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final resp = await _api.get(ApiEndpoints.notifications);
      final data = resp.data;
      final listData = data is Map && data.containsKey('data') ? data['data'] : data;
      final notifications = (listData as List)
          .map((j) => AppNotification.fromJson(j as Map<String, dynamic>))
          .toList();
      final unread = notifications.where((n) => !n.isRead).length;
      state = NotificationState(
        notifications: notifications,
        unreadCount: unread,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> markAllRead() async {
    if (state.unreadCount == 0) return; // ничего не помечать, API не дёргать
    final updated = state.notifications
        .map((n) => n.copyWith(isRead: true))
        .toList();
    state = state.copyWith(notifications: updated, unreadCount: 0);
    try {
      await _api.put(ApiEndpoints.markAllRead);
    } catch (_) {}
  }

  Future<void> markRead(String id) async {
    final updated = state.notifications.map((n) {
      if (n.id == id) return n.copyWith(isRead: true);
      return n;
    }).toList();
    final unread = updated.where((n) => !n.isRead).length;
    state = state.copyWith(notifications: updated, unreadCount: unread);
    try {
      await _api.put(ApiEndpoints.markRead(id));
    } catch (_) {}
  }
}

final notificationProvider =
    StateNotifierProvider<NotificationNotifier, NotificationState>((ref) {
  final api = ref.watch(apiClientProvider);
  return NotificationNotifier(api, ref);
});
