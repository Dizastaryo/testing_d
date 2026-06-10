import '../config/app_config.dart';

class ApiEndpoints {
  ApiEndpoints._();

  // Base URLs come from build-time config (--dart-define).
  // Defaults target localhost; production builds pass real URLs.
  static String get baseUrl => AppConfig.apiBaseUrl;
  static String get videoBaseUrl => AppConfig.videoBaseUrl;
  static String get libraryBaseUrl => AppConfig.libraryBaseUrl;

  // Auth (phone + OTP)
  static const String sendOtp = '/auth/send-otp';
  static const String verifyOtp = '/auth/verify-otp';
  static const String refreshToken = '/auth/refresh';
  static const String logout = '/auth/logout';

  // Feed
  static const String feed = '/feed';

  // Posts
  static const String posts = '/posts';
  static String postById(String id) => '/posts/$id';
  static String likePost(String id) => '/posts/$id/like';
  static String reactPost(String id) => '/posts/$id/react';
  static String savePost(String id) => '/posts/$id/save';
  static String postComments(String id) => '/posts/$id/comments';
  static String commentReplies(String commentId) => '/comments/$commentId/replies';
  static String deleteComment(String id) => '/comments/$id';
  static String likeComment(String id) => '/comments/$id/like';

  // Stories
  static const String stories = '/stories';
  static const String storyFeed = '/stories/feed';
  static String storyById(String id) => '/stories/$id';
  static String viewStory(String id) => '/stories/$id/view';
  static String storyViewers(String id) => '/stories/$id/viewers';
  static String userStories(String username) => '/stories/$username';
  static String likeStory(String id) => '/stories/$id/like';
  static String reactStory(String id) => '/stories/$id/react';
  static String storyPollVote(String id) => '/stories/$id/poll-vote';

  // Users
  static const String me = '/users/me';
  static const String deleteMe = '/users/me';
  static const String exportMe = '/users/me/export';
  static const String myBlocks = '/users/me/blocks';
  static String blockUser(String username) => '/users/$username/block';

  // Invites
  static const String invites = '/invites';
  static const String myInvites = '/invites/me/list';
  static String inviteByCode(String code) => '/invites/$code';

  // Device binding (BLE chip)
  static const String myDevice = '/users/me/device';

  // Follow requests (private accounts)
  static const String myFollowRequests = '/users/me/follow-requests';
  static String acceptFollowRequest(String id) =>
      '/follow-requests/$id/accept';
  static String declineFollowRequest(String id) =>
      '/follow-requests/$id/decline';

  static String userProfile(String username) => '/users/$username';
  static String userPosts(String username) => '/users/$username/posts';
  static String userSavedPosts(String username) => '/users/$username/saved';
  static String followUser(String username) => '/users/$username/follow';
  static String userFollowers(String username) => '/users/$username/followers';
  static String userFollowing(String username) => '/users/$username/following';

  // Highlights
  static const String highlights = '/highlights';
  static String userHighlights(String username) => '/highlights/$username';
  static String highlightById(String id) => '/highlights/$id';

  // Explore
  static const String explore = '/explore';
  static const String dailyPrompt = '/daily-prompt';
  static const String search = '/search';
  static const String searchHistory = '/search/history';

  // Audio tracks
  static const String audioTracks = '/audio-tracks';
  static const String myAudioTracks = '/audio-tracks/me';
  static const String recentAudioTracks = '/audio-tracks/recent'; // MUSIC-3
  static const String likedAudioTracks = '/audio-tracks/liked'; // MUSIC-3
  static const String dailyMixTracks = '/audio-tracks/daily-mix'; // MUSIC-4
  static String audioTrackById(String id) => '/audio-tracks/$id';
  static String audioTrackPlay(String id) =>
      '/audio-tracks/$id/play'; // MUSIC-3 record

  // Playlists (Music v2)
  static const String myPlaylists = '/playlists/me';
  static const String createPlaylist = '/playlists/';
  static String playlistById(String id) => '/playlists/$id';
  static String playlistTracks(String id) => '/playlists/$id/tracks';
  static String playlistTrackById(String id, String trackId) =>
      '/playlists/$id/tracks/$trackId';

  // Tags
  static const String trendingTags = '/tags/trending';

  // Notifications
  static const String notifications = '/notifications';
  static const String markAllRead = '/notifications/read';
  static String markRead(String id) => '/notifications/$id/read';

  // Upload
  static const String mediaUpload = '/media/upload';

  // Stickers
  static const String stickers = '/stickers';
  static const String stickerRemoveBg = '/stickers/remove-bg';
  static String stickerById(String id) => '/stickers/$id';

  // Chats
  static const String chats = '/chats';
  static String chatMessages(String id) => '/chats/$id/messages';
  static String chatMessageEdit(String chatId, String messageId) => '/chats/$chatId/messages/$messageId';
  static String chatRead(String id) => '/chats/$id/read';
  static String chatMessageReact(String messageId) =>
      '/chat-messages/$messageId/react';
  static String chatMessageDelete(String messageId) =>
      '/chat-messages/$messageId';
  // Group chats
  static String chatGroup(String id) => '/chats/$id';
  static String chatMembers(String id) => '/chats/$id/members';
  static String chatMember(String chatId, String userId) =>
      '/chats/$chatId/members/$userId';
  static String chatMemberRole(String chatId, String userId) =>
      '/chats/$chatId/members/$userId/role';
  static String chatPin(String chatId) => '/chats/$chatId/pin';
  static String chatUserPin(String chatId) => '/chats/$chatId/user-pin';
  static String chatArchive(String chatId) => '/chats/$chatId/archive';
  static String chatMute(String chatId) => '/chats/$chatId/mute';
  static String chatHide(String chatId) => '/chats/$chatId';
  static const String myCalls = '/users/me/calls'; // C-1 история звонков
  static String viewPost(String id) => '/posts/$id/view'; // FEED-5

  // === Video Service endpoints ===
  static const String videos = '/videos';
  static const String videosFeatured = '/videos/featured';
  static const String videosCategories = '/videos/categories';
  static String videoById(String id) => '/videos/$id';
  static String videoView(String id) => '/videos/$id/view';
  static String videoLike(String id) => '/videos/$id/like';
  static String userVideos(String userId) => '/users/$userId/videos';

  // Reels
  // Reels endpoints removed (migration 23 unified them with posts).

  // Сборы
  static const String sbory = '/sbory';
  static const String mySbory = '/sbory/me';
  static const String mySboryHistory = '/sbory/me?past=true';
  static const String bookmarkedSbory = '/sbory/bookmarked';
  static String sborById(String id) => '/sbory/$id';
  // POST /sbory/:id/join → join; DELETE /sbory/:id/join → leave (same path, different method)
  static String joinSbor(String id) => '/sbory/$id/join';
  static String leaveSbor(String id) => '/sbory/$id/join';
  static String cancelSbor(String id) => '/sbory/$id';
  static String bookmarkSbor(String id) => '/sbory/$id/bookmark';
  // Request flow
  static String sborRequests(String id) => '/sbory/$id/requests';
  static String approveSborRequest(String sborId, String reqId) => '/sbory/$sborId/requests/$reqId/approve';
  static String rejectSborRequest(String sborId, String reqId) => '/sbory/$sborId/requests/$reqId/reject';
  static String leaveGroupChat(String id) => '/chats/$id/leave';

  // Rooms (private voice + text channels)
  static const String rooms = '/rooms';
  static String roomById(String id) => '/rooms/$id';
  static String joinRoom(String id) => '/rooms/$id/join';
  static String leaveRoom(String id) => '/rooms/$id/join';
  static String muteRoom(String id) => '/rooms/$id/mute';
  static String roomVoice(String id) => '/rooms/$id/voice';
  static String roomMessages(String id) => '/rooms/$id/messages';
  static String roomMembers(String id) => '/rooms/$id/members';
  static String roomInvite(String id) => '/rooms/$id/invite';
  static String roomCandidates(String id) => '/rooms/$id/candidates';
  static String roomMember(String id, String userId) => '/rooms/$id/members/$userId';
  static String roomAdmin(String id, String userId) => '/rooms/$id/admins/$userId';
  static const String roomInvitesMe = '/rooms/invites/me';
  static String roomInviteAccept(String id) => '/rooms/invites/$id/accept';
  static String roomInviteDecline(String id) => '/rooms/invites/$id/decline';

  // === Library Service endpoints ===
  static const String files = '/files';
  static const String filesCategories = '/files/categories';
  static String fileById(String id) => '/files/$id';
  static String fileDownload(String id) => '/files/$id/download';
  static String filePreview(String id) => '/files/$id/preview';
  static String fileLike(String id) => '/files/$id/like';
  static String userFiles(String userId) => '/users/$userId/files';
}
