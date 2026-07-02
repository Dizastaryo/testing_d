import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/user.dart';
import 'auth_provider.dart';

/// Following list of the current user, excluding self.
/// Used by chat-list "new chat" sheet, create-group, and add-members screens.
final followingCandidatesProvider =
    FutureProvider.autoDispose<List<User>>((ref) async {
  final me = ref.read(authProvider).user;
  if (me == null) return [];
  final api = ref.read(apiClientProvider);
  final r = await api.get(ApiEndpoints.userFollowing(me.username),
      queryParameters: {'limit': 100});
  final data =
      r.data is Map && (r.data as Map).containsKey('data') ? r.data['data'] : r.data;
  if (data is! List) return [];
  return data
      .map((e) => User.fromJson(e as Map<String, dynamic>))
      .where((u) => u.id != me.id)
      .toList();
});
