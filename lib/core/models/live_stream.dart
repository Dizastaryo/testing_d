class LiveStream {
  final String id;
  final String userId;
  final String username;
  final String fullName;
  final String avatarUrl;
  final String title;
  final String status;
  final int viewerCount;
  final DateTime startedAt;
  final DateTime? endedAt;

  const LiveStream({
    required this.id,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.title,
    required this.status,
    required this.viewerCount,
    required this.startedAt,
    this.endedAt,
  });

  bool get isLive => status == 'live';

  factory LiveStream.fromJson(Map<String, dynamic> j) => LiveStream(
        id: j['id']?.toString() ?? '',
        userId: j['user_id']?.toString() ?? '',
        username: j['username'] as String? ?? '',
        fullName: j['full_name'] as String? ?? '',
        avatarUrl: j['avatar_url'] as String? ?? '',
        title: j['title'] as String? ?? '',
        status: j['status'] as String? ?? 'live',
        viewerCount: (j['viewer_count'] as num?)?.toInt() ?? 0,
        startedAt: DateTime.tryParse(j['started_at'] as String? ?? '') ?? DateTime.now(),
        endedAt: j['ended_at'] != null
            ? DateTime.tryParse(j['ended_at'] as String)
            : null,
      );
}

class LiveStreamViewer {
  final String userId;
  final String username;
  final String fullName;
  final String avatarUrl;

  const LiveStreamViewer({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
  });

  factory LiveStreamViewer.fromJson(Map<String, dynamic> j) => LiveStreamViewer(
        userId: j['user_id']?.toString() ?? '',
        username: j['username'] as String? ?? '',
        fullName: j['full_name'] as String? ?? '',
        avatarUrl: j['avatar_url'] as String? ?? '',
      );
}
