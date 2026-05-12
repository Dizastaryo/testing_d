/// Запись о звонке (C-1 история звонков). Соответствует backend'у
/// `call_invitations` row, hydrated peer-fields.
class Call {
  final String id;
  final String fromUserId;
  final String toUserId;
  /// 'video' | 'voice' — для иконки и фильтрации.
  final String kind;
  /// 'pending' | 'accepted' | 'declined' | 'missed' | 'ended'.
  final String status;
  final DateTime startedAt;
  final DateTime? acceptedAt;
  final DateTime? endedAt;
  final int? durationSeconds;
  final String peerUsername;
  final String peerFullName;
  final String peerAvatarUrl;

  const Call({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.kind,
    required this.status,
    required this.startedAt,
    this.acceptedAt,
    this.endedAt,
    this.durationSeconds,
    this.peerUsername = '',
    this.peerFullName = '',
    this.peerAvatarUrl = '',
  });

  /// True если currentUserId был получателем (т.е. ему позвонили).
  bool isIncoming(String currentUserId) => toUserId == currentUserId;

  /// True для missed либо declined на стороне callee — фронт подсвечивает
  /// красным.
  bool get isMissed => status == 'missed';

  factory Call.fromJson(Map<String, dynamic> j) => Call(
        id: j['id']?.toString() ?? '',
        fromUserId: j['from_user_id']?.toString() ?? '',
        toUserId: j['to_user_id']?.toString() ?? '',
        kind: j['kind']?.toString() ?? 'video',
        status: j['status']?.toString() ?? 'ended',
        startedAt: j['started_at'] != null
            ? DateTime.tryParse(j['started_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        acceptedAt: j['accepted_at'] != null
            ? DateTime.tryParse(j['accepted_at'].toString())
            : null,
        endedAt: j['ended_at'] != null
            ? DateTime.tryParse(j['ended_at'].toString())
            : null,
        durationSeconds: (j['duration_seconds'] as num?)?.toInt(),
        peerUsername: j['peer_username']?.toString() ?? '',
        peerFullName: j['peer_full_name']?.toString() ?? '',
        peerAvatarUrl: j['peer_avatar_url']?.toString() ?? '',
      );
}
