/// Full member record returned by GET /rooms/:id/members.
class RoomMember {
  final String userId;
  final String fullName;
  final String username;
  final String? avatarUrl;
  final bool isMuted;
  final bool isCreator;
  final DateTime joinedAt;

  const RoomMember({
    required this.userId,
    required this.fullName,
    required this.username,
    this.avatarUrl,
    this.isMuted = false,
    this.isCreator = false,
    required this.joinedAt,
  });

  factory RoomMember.fromJson(Map<String, dynamic> j) => RoomMember(
        userId: j['user_id'] as String,
        fullName: j['full_name'] as String? ?? '',
        username: j['username'] as String? ?? '',
        avatarUrl: j['avatar_url'] as String?,
        isMuted: j['is_muted'] as bool? ?? false,
        isCreator: j['is_creator'] as bool? ?? false,
        joinedAt: DateTime.tryParse(j['joined_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class RoomParticipant {
  final String userId;
  final String fullName;
  final String username;
  final String? avatarUrl;
  final bool isMuted;

  const RoomParticipant({
    required this.userId,
    required this.fullName,
    required this.username,
    this.avatarUrl,
    this.isMuted = false,
  });

  factory RoomParticipant.fromJson(Map<String, dynamic> j) => RoomParticipant(
        userId: j['user_id'] as String,
        fullName: j['full_name'] as String? ?? '',
        username: j['username'] as String? ?? '',
        avatarUrl: j['avatar_url'] as String?,
        isMuted: j['is_muted'] as bool? ?? false,
      );

  RoomParticipant copyWith({bool? isMuted}) => RoomParticipant(
        userId: userId,
        fullName: fullName,
        username: username,
        avatarUrl: avatarUrl,
        isMuted: isMuted ?? this.isMuted,
      );
}

class Room {
  final String id;
  final String creatorId;
  final String type; // 'text' | 'voice'
  final String name;
  final String? description;
  final String? coverUrl;
  final bool isPublic;
  final bool isActive;
  final String? creatorName;
  final int participantCount;
  final List<RoomParticipant> participants;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final bool isJoined;
  final bool isMuted;

  const Room({
    required this.id,
    required this.creatorId,
    required this.type,
    required this.name,
    this.description,
    this.coverUrl,
    this.isPublic = true,
    this.isActive = true,
    this.creatorName,
    this.participantCount = 0,
    this.participants = const [],
    this.lastMessage,
    this.lastMessageAt,
    this.isJoined = false,
    this.isMuted = false,
  });

  bool get isVoice => type == 'voice';

  factory Room.fromJson(Map<String, dynamic> j) => Room(
        id: j['id'] as String,
        creatorId: j['creator_id'] as String,
        type: j['type'] as String? ?? 'text',
        name: j['name'] as String,
        description: j['description'] as String?,
        coverUrl: j['cover_url'] as String?,
        isPublic: j['is_public'] as bool? ?? true,
        isActive: j['is_active'] as bool? ?? true,
        creatorName: j['creator_name'] as String?,
        participantCount: j['participant_count'] as int? ?? 0,
        participants: (j['participants'] as List<dynamic>?)
                ?.map((e) => RoomParticipant.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        lastMessage: j['last_message'] as String?,
        lastMessageAt: j['last_message_at'] != null
            ? DateTime.tryParse(j['last_message_at'] as String)
            : null,
        isJoined: j['is_joined'] as bool? ?? false,
        isMuted: j['is_muted'] as bool? ?? false,
      );

  Room copyWith({
    int? participantCount,
    List<RoomParticipant>? participants,
    bool? isJoined,
    bool? isMuted,
    bool? isActive,
    String? lastMessage,
    DateTime? lastMessageAt,
  }) =>
      Room(
        id: id,
        creatorId: creatorId,
        type: type,
        name: name,
        description: description,
        coverUrl: coverUrl,
        isPublic: isPublic,
        isActive: isActive ?? this.isActive,
        creatorName: creatorName,
        participantCount: participantCount ?? this.participantCount,
        participants: participants ?? this.participants,
        lastMessage: lastMessage ?? this.lastMessage,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        isJoined: isJoined ?? this.isJoined,
        isMuted: isMuted ?? this.isMuted,
      );
}

class RoomMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String senderName;
  final String senderUsername;
  final String? senderAvatar;
  final String text;
  final DateTime createdAt;

  const RoomMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderName,
    required this.senderUsername,
    this.senderAvatar,
    required this.text,
    required this.createdAt,
  });

  factory RoomMessage.fromJson(Map<String, dynamic> j) => RoomMessage(
        id: j['id'] as String,
        roomId: j['room_id'] as String,
        senderId: j['sender_id'] as String,
        senderName: j['sender_name'] as String? ?? '',
        senderUsername: j['sender_username'] as String? ?? '',
        senderAvatar: j['sender_avatar_url'] as String?,
        text: j['text'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
