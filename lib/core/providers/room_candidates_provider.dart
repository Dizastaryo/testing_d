import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/user.dart';

/// All mutual followers of the current user (no room filter).
/// Used in the room create screen (before room exists).
final mutualFollowersProvider =
    FutureProvider.autoDispose<List<User>>((ref) async {
  final api = ref.read(apiClientProvider);
  final r = await api.get('/users/me/mutuals');
  final data =
      r.data is Map && (r.data as Map).containsKey('data') ? r.data['data'] : r.data;
  if (data is! List) return [];
  return data.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
});

/// Mutual followers NOT already members of [roomId] and without pending invite.
/// Used in the room members invite picker.
final roomCandidatesProvider =
    FutureProvider.autoDispose.family<List<User>, String>((ref, roomId) async {
  final api = ref.read(apiClientProvider);
  final r = await api.get(ApiEndpoints.roomCandidates(roomId));
  final data =
      r.data is Map && (r.data as Map).containsKey('data') ? r.data['data'] : r.data;
  if (data is! List) return [];
  return data.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
});
