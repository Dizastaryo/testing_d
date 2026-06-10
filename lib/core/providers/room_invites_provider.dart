import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/room.dart';
import 'realtime_provider.dart';

class RoomInvitesNotifier extends StateNotifier<AsyncValue<List<RoomInvite>>> {
  final ApiClient _api;
  final Ref _ref;
  ProviderSubscription<AsyncValue<RealtimeEvent>>? _wsSub;

  RoomInvitesNotifier(this._api, this._ref) : super(const AsyncValue.loading()) {
    load();
    _wsSub = _ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (_, next) {
      next.whenData((evt) {
        if (evt.type == 'room.invite_received') load();
      });
    });
  }

  @override
  void dispose() {
    _wsSub?.close();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await _api.get(ApiEndpoints.roomInvitesMe);
      final data = r.data is Map && (r.data as Map).containsKey('data')
          ? r.data['data']
          : r.data;
      final list = (data as List? ?? [])
          .map((e) => RoomInvite.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> accept(String inviteId) async {
    await _api.post(ApiEndpoints.roomInviteAccept(inviteId));
    _removeById(inviteId);
  }

  Future<void> decline(String inviteId) async {
    await _api.post(ApiEndpoints.roomInviteDecline(inviteId));
    _removeById(inviteId);
  }

  void _removeById(String inviteId) {
    state.whenData((list) {
      state = AsyncValue.data(list.where((i) => i.id != inviteId).toList());
    });
  }

  int get pendingCount => state.valueOrNull?.length ?? 0;
}

final roomInvitesProvider =
    StateNotifierProvider<RoomInvitesNotifier, AsyncValue<List<RoomInvite>>>(
  (ref) => RoomInvitesNotifier(ref.read(apiClientProvider), ref),
);
