import '../config/server_config.dart';

class ApiEndpoints {
  ApiEndpoints._();

  // Base URLs come from ServerConfig (runtime, persisted in SharedPreferences).
  // Default falls back to compile-time AppConfig values.
  static String get baseUrl => ServerConfig.apiBaseUrl;
  static String get libraryBaseUrl => ServerConfig.libraryBaseUrl;

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
  static String savePost(String id) => '/posts/$id/save';
  static String postPollVote(String id) => '/posts/$id/poll/vote';
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
  static const String myScanProfile = '/users/me/scan-profile';
  // Консентный резолв владельца браслета по ФИЗИЧЕСКОМУ NFC-касанию (мост в
  // Профиль). Отличается от анонимного ambient-скана /scanner/resolve.
  static String userByDevice(String publicId) => '/users/by-device/$publicId';

  // Scanner (BLE — resolve ANONYMOUS cards, never real accounts)
  static const String scannerResolve = '/scanner/resolve';
  static String scannerResolveOne(String deviceHash) => '/scanner/resolve/$deviceHash';

  // Карточка: открыть чужую (фиксирует просмотр), аудитория/статистика,
  // card-level блокировка, библиотека кастомизации.
  static String cardOpen(String ownerId) => '/scanner/cards/$ownerId/open';
  static const String cardAudience = '/scanner/card/audience';
  static const String cardStats = '/scanner/card/stats';
  static const String cardBlock = '/scanner/card/block';
  static String cardUnblock(String ownerId) => '/scanner/card/block/$ownerId';
  static const String cardBlocks = '/scanner/card/blocks';
  static const String cardLibrary = '/scanner/library';

  // Access system (closed messaging: request→accept; bracelet QR = /users/me/device)
  static String accessCheck(String userId) => '/access/check/$userId';
  static String accessRevoke(String userId) => '/access/$userId';
  static const String accessList = '/access/list';
  // Access requests (request → accept/reject)
  static String accessRequest(String userId) => '/access/request/$userId';
  static const String accessRequestsIncoming = '/access/requests/incoming';
  static const String accessRequestsSent = '/access/requests/sent';
  static String accessRequestAccept(String id) => '/access/requests/$id/accept';
  static String accessRequestReject(String id) => '/access/requests/$id/reject';
  static String accessRequestCancel(String id) => '/access/requests/$id';

  // Restrictions (ограничение комментариев пользователя)
  static const String myRestrictions = '/users/me/restrictions';
  static String restrictUser(String username) => '/users/$username/restrict';

  // Контакты телефона: приватный матчинг по SHA-256 хэшам (Фаза 2)
  static const String contactsSync = '/contacts/sync';

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
  // Post-shaped Explore feed for the full-screen vertical viewer (returns full
  // Post objects with media). Supports ?media_type=video|image + ?page.
  static const String postsExplore = '/posts/explore';
  static const String interestEvents = '/interest/events';
  static const String leaderboard = '/leaderboard';
  static const String dailyPrompt = '/daily-prompt';
  static const String search = '/search';
  static const String searchHistory = '/search/history';

  // Audio tracks
  static const String audioTracks = '/audio-tracks';
  static const String myAudioTracks = '/audio-tracks/me';
  static const String recentAudioTracks = '/audio-tracks/recent'; // MUSIC-3
  static const String likedAudioTracks = '/audio-tracks/liked'; // MUSIC-3
  static const String dailyMixTracks = '/audio-tracks/daily-mix'; // MUSIC-4
  // Позиция прослушивания (миграция 000143): «Продолжить» и режимы Книга/Разговор.
  static const String continueListening = '/audio-tracks/continue';
  static String audioTrackPosition(String id) => '/audio-tracks/$id/position';
  static String audioTrackById(String id) => '/audio-tracks/$id';
  static String audioTrackPlay(String id) =>
      '/audio-tracks/$id/play'; // MUSIC-3 record
  static const String audioTracksUpload = '/audio-tracks/upload';
  static String audioTrackUpdate(String id) => '/audio-tracks/$id';
  static String audioTrackDelete(String id) => '/audio-tracks/$id';
  static String audioTrackLike(String id) => '/audio-tracks/$id/like';
  static String audioTrackSave(String id) => '/audio-tracks/$id/save';
  static const String savedAudioTracks = '/audio-tracks/saved';
  static const String trendingAudioTracks = '/audio-tracks/trending';
  static const String audioDiscovery = '/audio-tracks/discovery';
  static const String audioOriginalSounds = '/audio-tracks/original-sounds';
  static const String audioBrowseCategories = '/audio-tracks/browse/categories';
  static String audioBrowseCategoryDetail(String cat) =>
      '/audio-tracks/browse/categories/$cat';
  static const String audioSearch = '/audio-tracks/search';

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

  // Gifs
  static const String gifs = '/gifs';
  static const String gifCategories = '/gifs/categories';

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

  // === Video endpoints ===
  // The long-video "Видеотека" section was removed. The vertical Shorts
  // viewer fetches its single video by id from the main API (`baseUrl`,
  // see singleVideoProvider) — the standalone video service (`videoBaseUrl`,
  // port 8002) is no longer required for this.

  // Reels
  // Reels endpoints removed (migration 23 unified them with posts).

  // Сборы
  static const String sbory = '/sbory';
  static const String mySbory = '/sbory/me';
  static const String mySboryHistory = '/sbory/me?past=true';
  static const String bookmarkedSbory = '/sbory/bookmarked';
  static String sborById(String id) => '/sbory/$id';
  static String sborMembers(String id) => '/sbory/$id/members';
  // Вступление — только через заявку (POST /sbory/:id/requests → одобрение
  // организатора). Прямой POST /:id/join удалён как обход гейта. Осталось лишь
  // DELETE /sbory/:id/join — покинуть сбор.
  static String leaveSbor(String id) => '/sbory/$id/join';
  static String cancelSbor(String id) => '/sbory/$id';
  static String bookmarkSbor(String id) => '/sbory/$id/bookmark';
  // Request flow
  static String sborRequests(String id) => '/sbory/$id/requests';
  static String approveSborRequest(String sborId, String reqId) => '/sbory/$sborId/requests/$reqId/approve';
  static String rejectSborRequest(String sborId, String reqId) => '/sbory/$sborId/requests/$reqId/reject';
  static String leaveGroupChat(String id) => '/chats/$id/leave';

  // Rooms (voice + text channels). Вход по коду вместо приглашений.
  static const String rooms = '/rooms';
  static const String roomJoinByCode = '/rooms/join'; // POST {code}
  static String roomById(String id) => '/rooms/$id';
  static String leaveRoom(String id) => '/rooms/$id/join';
  static String muteRoom(String id) => '/rooms/$id/mute';
  static String roomVoice(String id) => '/rooms/$id/voice';
  static String roomMessages(String id) => '/rooms/$id/messages';
  static String roomMessageReact(String roomId, String msgId) => '/rooms/$roomId/messages/$msgId/react';
  static String roomMessageEdit(String roomId, String msgId) => '/rooms/$roomId/messages/$msgId';
  static String roomMessageDelete(String roomId, String msgId) => '/rooms/$roomId/messages/$msgId';
  static String roomPin(String id) => '/rooms/$id/pin';
  static String roomRead(String id) => '/rooms/$id/read';
  static String roomMembers(String id) => '/rooms/$id/members';
  static String roomMember(String id, String userId) => '/rooms/$id/members/$userId';
  static String roomAdmin(String id, String userId) => '/rooms/$id/admins/$userId';

  // === Library Service endpoints ===
  static const String files = '/files';
  static const String filesCategories = '/files/categories';
  static const String filesUpload = '/files/upload';
  static const String filesTrending = '/files/trending';
  static const String filesPopularAuthors = '/files/authors/popular';
  static const String filesFormatStats = '/files/stats/formats';
  static const String myRecommendations = '/users/me/recommendations';
  static String fileById(String id) => '/files/$id';
  static String fileDownload(String id) => '/files/$id/download';
  static String fileView(String id) => '/files/$id/view';
  static String fileRating(String id) => '/files/$id/rating';
  static String fileReviews(String id) => '/files/$id/reviews';
  static String fileRelated(String id) => '/files/$id/related';
  static String fileNotes(String id) => '/files/$id/notes';
  static const String filesSocialPicks = '/files/social-picks';
  static String fileLike(String id) => '/files/$id/like';
  static String fileText(String id) => '/files/$id/text';
  static String filePdf(String id) => '/files/$id/pdf';
  static String filePdfStatus(String id) => '/files/$id/pdf-status';
  static String fileReExtract(String id) => '/files/$id/re-extract';
  static String fileProgress(String id) => '/files/$id/progress';
  static String filePagesProgress(String id) => '/files/$id/pages-progress';
  static String fileBookmarks(String id) => '/files/$id/bookmarks';
  static String bookmarkById(String id) => '/files/bookmarks/$id';
  static String fileReadingStatus(String id) => '/files/$id/reading-status';
  static String fileStats(String id) => '/files/$id/stats';
  static String userFiles(String userId) => '/users/$userId/files';
  static const String myBookmarks = '/users/me/bookmarks';
  static const String myReadingStats = '/users/me/reading-stats';
  static const String myReadingList = '/users/me/reading-list';
  static const String myRecentlyRead = '/users/me/recently-read';
  static const String myReadingGoal = '/users/me/reading-goal';
  static const String readingLeaderboard = '/reading/leaderboard';
  static const String readingActivity = '/reading/activity';
  static const String collections = '/collections';
  static String collectionById(String id) => '/collections/$id';
  static String collectionFiles(String id) => '/collections/$id/files';
  static String collectionFile(String id, String fileId) => '/collections/$id/files/$fileId';

  // Live streams
  static const String streams = '/streams';
  static String streamById(String id) => '/streams/$id';
  static String streamJoin(String id) => '/streams/$id/join';

  // Spark 🔥 — единый сигнал тепла по BLE-близости (Фаза 3, заменил монеты)
  static const String sparksSend = '/sparks/send';
  static const String sparksSenders = '/sparks/senders';

  // Pair 🔥🔥 — статус «Пара» через двойное NFC-касание (Фаза 5)
  static const String pairsTap = '/pairs/tap';
  static const String pairsPrompts = '/pairs/prompts';
  static String pairsRespond(String id) => '/pairs/prompts/$id/respond';
  static String pairsCheck(String userId) => '/pairs/check/$userId';
}
