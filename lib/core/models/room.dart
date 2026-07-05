/// Full member record returned by GET /rooms/:id/members.
class RoomMember {
  final String userId;
  final String fullName;
  final String username;
  final String? avatarUrl;
  final bool isMuted;
  final bool isCreator;
  final bool isAdmin;
  final DateTime joinedAt;

  const RoomMember({
    required this.userId,
    required this.fullName,
    required this.username,
    this.avatarUrl,
    this.isMuted = false,
    this.isCreator = false,
    this.isAdmin = false,
    required this.joinedAt,
  });

  factory RoomMember.fromJson(Map<String, dynamic> j) => RoomMember(
        userId: j['user_id'] as String,
        fullName: j['full_name'] as String? ?? '',
        username: j['username'] as String? ?? '',
        avatarUrl: j['avatar_url'] as String?,
        isMuted: j['is_muted'] as bool? ?? false,
        isCreator: j['is_creator'] as bool? ?? false,
        isAdmin: j['is_admin'] as bool? ?? false,
        joinedAt: DateTime.tryParse(j['joined_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class RoomInvite {
  final String id;
  final String roomId;
  final String roomName;
  final String roomCover;
  final String inviterName;
  final String inviterUsername;
  final String inviterAvatar;
  final DateTime createdAt;

  const RoomInvite({
    required this.id,
    required this.roomId,
    required this.roomName,
    this.roomCover = '',
    required this.inviterName,
    required this.inviterUsername,
    this.inviterAvatar = '',
    required this.createdAt,
  });

  factory RoomInvite.fromJson(Map<String, dynamic> j) => RoomInvite(
        id: j['id'] as String,
        roomId: j['room_id'] as String,
        roomName: j['room_name'] as String? ?? '',
        roomCover: j['room_cover'] as String? ?? '',
        inviterName: j['inviter_name'] as String? ?? '',
        inviterUsername: j['inviter_username'] as String? ?? '',
        inviterAvatar: j['inviter_avatar'] as String? ?? '',
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
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

/// Compact pinned-message summary embedded in [Room] (mirrors chat's
/// `ReplyPreview`) — just enough to render a pin banner without a second
/// round-trip for the full message.
class RoomMessagePreview {
  final String id;
  final String senderId;
  final String senderUsername;
  final String text;
  final String kind;

  const RoomMessagePreview({
    required this.id,
    required this.senderId,
    required this.senderUsername,
    required this.text,
    required this.kind,
  });

  factory RoomMessagePreview.fromJson(Map<String, dynamic> j) => RoomMessagePreview(
        id: j['id'] as String? ?? '',
        senderId: j['sender_id'] as String? ?? '',
        senderUsername: j['sender_username'] as String? ?? '',
        text: j['text'] as String? ?? '',
        kind: j['kind'] as String? ?? 'text',
      );
}

class Room {
  final String id;
  final String creatorId;
  final String type; // 'text' | 'voice'
  final String name;
  final String? description;
  final String? coverUrl;
  final bool isActive;
  final String? creatorName;
  final int participantCount;
  final List<RoomParticipant> participants;
  final String? lastMessage;
  final String lastSenderUsername;
  final DateTime? lastMessageAt;
  final bool isJoined;
  final bool isMuted;
  final bool isAdmin;
  // Voice channel (explicit opt-in)
  final int voiceCount;
  final List<RoomParticipant> voiceParticipants;
  final bool isInVoice;
  // BUGS_AUDIT #11 parity — one pinned message per room.
  final String? pinnedMessageId;
  final RoomMessagePreview? pinnedMessage;

  const Room({
    required this.id,
    required this.creatorId,
    required this.type,
    required this.name,
    this.description,
    this.coverUrl,
    this.isActive = true,
    this.creatorName,
    this.participantCount = 0,
    this.participants = const [],
    this.lastMessage,
    this.lastSenderUsername = '',
    this.lastMessageAt,
    this.isJoined = false,
    this.isMuted = false,
    this.isAdmin = false,
    this.voiceCount = 0,
    this.voiceParticipants = const [],
    this.isInVoice = false,
    this.pinnedMessageId,
    this.pinnedMessage,
  });

  bool get isVoice => type == 'voice';

  factory Room.fromJson(Map<String, dynamic> j) => Room(
        id: j['id'] as String,
        creatorId: j['creator_id'] as String,
        type: j['type'] as String? ?? 'text',
        name: j['name'] as String,
        description: j['description'] as String?,
        coverUrl: j['cover_url'] as String?,
        isActive: j['is_active'] as bool? ?? true,
        creatorName: j['creator_name'] as String?,
        participantCount: j['participant_count'] as int? ?? 0,
        participants: (j['participants'] as List<dynamic>?)
                ?.map((e) => RoomParticipant.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        lastMessage: j['last_message'] as String?,
        lastSenderUsername: j['last_sender_username'] as String? ?? '',
        lastMessageAt: j['last_message_at'] != null
            ? DateTime.tryParse(j['last_message_at'] as String)
            : null,
        isJoined: j['is_joined'] as bool? ?? false,
        isMuted: j['is_muted'] as bool? ?? false,
        isAdmin: j['is_admin'] as bool? ?? false,
        voiceCount: j['voice_count'] as int? ?? 0,
        voiceParticipants: (j['voice_participants'] as List<dynamic>?)
                ?.map((e) => RoomParticipant.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        isInVoice: j['is_in_voice'] as bool? ?? false,
        pinnedMessageId: j['pinned_message_id'] as String?,
        pinnedMessage: j['pinned_message'] is Map<String, dynamic>
            ? RoomMessagePreview.fromJson(j['pinned_message'] as Map<String, dynamic>)
            : null,
      );

  Room copyWith({
    int? participantCount,
    List<RoomParticipant>? participants,
    bool? isJoined,
    bool? isMuted,
    bool? isActive,
    bool? isAdmin,
    String? lastMessage,
    String? lastSenderUsername,
    DateTime? lastMessageAt,
    String? name,
    String? description,
    String? coverUrl,
    int? voiceCount,
    List<RoomParticipant>? voiceParticipants,
    bool? isInVoice,
    String? pinnedMessageId,
    RoomMessagePreview? pinnedMessage,
    bool clearPinnedMessage = false,
  }) =>
      Room(
        id: id,
        creatorId: creatorId,
        type: type,
        name: name ?? this.name,
        description: description ?? this.description,
        coverUrl: coverUrl ?? this.coverUrl,
        isActive: isActive ?? this.isActive,
        creatorName: creatorName,
        participantCount: participantCount ?? this.participantCount,
        participants: participants ?? this.participants,
        lastMessage: lastMessage ?? this.lastMessage,
        lastSenderUsername: lastSenderUsername ?? this.lastSenderUsername,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        isJoined: isJoined ?? this.isJoined,
        isMuted: isMuted ?? this.isMuted,
        isAdmin: isAdmin ?? this.isAdmin,
        voiceCount: voiceCount ?? this.voiceCount,
        voiceParticipants: voiceParticipants ?? this.voiceParticipants,
        isInVoice: isInVoice ?? this.isInVoice,
        pinnedMessageId: clearPinnedMessage ? null : (pinnedMessageId ?? this.pinnedMessageId),
        pinnedMessage: clearPinnedMessage ? null : (pinnedMessage ?? this.pinnedMessage),
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
  final String kind;
  final String? attachedMediaUrl;
  final String? attachedMediaType;
  final DateTime createdAt;
  /// Агрегированные реакции: emoji → count.
  final Map<String, int> reactions;
  /// Реакция текущего пользователя (пустая строка = нет реакции).
  final String myReaction;

  // BUGS_AUDIT #11 parity fields (mirror ChatMessage).
  final bool isDeletedForAll;
  final String? forwardedFromMessageId;
  final String forwardedFromSender;
  final bool isRead;
  final bool isDelivered;
  final int deliveredCount;
  final int readCount;
  final int recipientsCount;

  const RoomMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderName,
    required this.senderUsername,
    this.senderAvatar,
    required this.text,
    this.kind = 'text',
    this.attachedMediaUrl,
    this.attachedMediaType,
    required this.createdAt,
    this.reactions = const {},
    this.myReaction = '',
    this.isDeletedForAll = false,
    this.forwardedFromMessageId,
    this.forwardedFromSender = '',
    this.isRead = false,
    this.isDelivered = false,
    this.deliveredCount = 0,
    this.readCount = 0,
    this.recipientsCount = 0,
  });

  RoomMessage copyWith({
    String? text,
    String? kind,
    Map<String, int>? reactions,
    String? myReaction,
    bool? isDeletedForAll,
    bool? isRead,
    bool? isDelivered,
    int? deliveredCount,
    int? readCount,
    int? recipientsCount,
  }) => RoomMessage(
    id: id,
    roomId: roomId,
    senderId: senderId,
    senderName: senderName,
    senderUsername: senderUsername,
    senderAvatar: senderAvatar,
    text: text ?? this.text,
    kind: kind ?? this.kind,
    attachedMediaUrl: attachedMediaUrl,
    attachedMediaType: attachedMediaType,
    createdAt: createdAt,
    reactions: reactions ?? this.reactions,
    myReaction: myReaction ?? this.myReaction,
    isDeletedForAll: isDeletedForAll ?? this.isDeletedForAll,
    forwardedFromMessageId: forwardedFromMessageId,
    forwardedFromSender: forwardedFromSender,
    isRead: isRead ?? this.isRead,
    isDelivered: isDelivered ?? this.isDelivered,
    deliveredCount: deliveredCount ?? this.deliveredCount,
    readCount: readCount ?? this.readCount,
    recipientsCount: recipientsCount ?? this.recipientsCount,
  );

  factory RoomMessage.fromJson(Map<String, dynamic> j) {
    final rawReactions = j['reactions'];
    final Map<String, int> reactions = {};
    if (rawReactions is Map) {
      rawReactions.forEach((k, v) {
        if (v is int) {
          reactions[k.toString()] = v;
        } else if (v is num) {
          reactions[k.toString()] = v.toInt();
        }
      });
    }
    return RoomMessage(
      id: j['id'] as String,
      roomId: j['room_id'] as String,
      senderId: j['sender_id'] as String,
      senderName: j['sender_name'] as String? ?? '',
      senderUsername: j['sender_username'] as String? ?? '',
      senderAvatar: j['sender_avatar_url'] as String?,
      text: j['text'] as String? ?? '',
      kind: j['kind'] as String? ?? 'text',
      attachedMediaUrl: j['attached_media_url'] as String?,
      attachedMediaType: j['attached_media_type'] as String?,
      createdAt: DateTime.parse(j['created_at'] as String),
      reactions: reactions,
      myReaction: j['my_reaction'] as String? ?? '',
      isDeletedForAll: j['is_deleted_for_all'] as bool? ?? false,
      forwardedFromMessageId: j['forwarded_from_message_id'] as String?,
      forwardedFromSender: j['forwarded_from_sender'] as String? ?? '',
      isRead: j['is_read'] as bool? ?? false,
      isDelivered: j['is_delivered'] as bool? ?? false,
      deliveredCount: (j['delivered_count'] as num?)?.toInt() ?? 0,
      readCount: (j['read_count'] as num?)?.toInt() ?? 0,
      recipientsCount: (j['recipients_count'] as num?)?.toInt() ?? 0,
    );
  }
}
