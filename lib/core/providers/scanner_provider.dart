import '../api/api_client.dart';
import '../api/api_endpoints.dart';

// ── ScanProfile — real user account resolved from BLE device hash ─────────────

class ScanProfile {
  final String deviceHash;
  final String userId;
  final String username;
  final String fullName;
  final String avatarUrl;
  final bool isVerified;

  const ScanProfile({
    required this.deviceHash,
    this.userId = '',
    this.username = '',
    this.fullName = '',
    this.avatarUrl = '',
    this.isVerified = false,
  });

  factory ScanProfile.fromJson(Map<String, dynamic> j) => ScanProfile(
        deviceHash: j['device_hash']?.toString() ?? '',
        userId: j['user_id']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        fullName: j['full_name']?.toString() ?? '',
        avatarUrl: j['avatar_url']?.toString() ?? '',
        isVerified: (j['is_verified'] as bool?) ?? false,
      );
}

// ── Batch resolve device hashes → real user accounts ─────────────────────────

Future<Map<String, ScanProfile>> resolveScanProfiles(
    ApiClient api, List<String> deviceHashes) async {
  if (deviceHashes.isEmpty) return {};
  try {
    final res = await api.post(
      ApiEndpoints.scannerResolve,
      data: {'device_hashes': deviceHashes},
    );
    final raw = res.data;
    final data =
        (raw is Map ? (raw['data'] ?? raw) : raw) as Map<String, dynamic>? ?? {};
    final profiles = (data['profiles'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ScanProfile.fromJson)
        .toList();
    return {for (final p in profiles) p.deviceHash: p};
  } catch (_) {
    return {};
  }
}
