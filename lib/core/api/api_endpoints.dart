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
  static const String search = '/search';
  static const String searchHistory = '/search/history';

  // Audio tracks
  static const String audioTracks = '/audio-tracks';
  static const String myAudioTracks = '/audio-tracks/me';

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

  // Chats
  static const String chats = '/chats';
  static String chatMessages(String id) => '/chats/$id/messages';
  static String chatRead(String id) => '/chats/$id/read';
  static String chatMessageReact(String messageId) =>
      '/chat-messages/$messageId/react';

  // === Video Service endpoints ===
  static const String videos = '/videos';
  static const String videosFeatured = '/videos/featured';
  static const String videosCategories = '/videos/categories';
  static String videoById(String id) => '/videos/$id';
  static String videoView(String id) => '/videos/$id/view';
  static String videoLike(String id) => '/videos/$id/like';
  static String userVideos(String userId) => '/users/$userId/videos';

  // Reels
  static const String reelsFeed = '/reels/feed';
  static String reelById(String id) => '/reels/$id';
  static String reelView(String id) => '/reels/$id/view';
  static String reelLike(String id) => '/reels/$id/like';
  static String reelShare(String id) => '/reels/$id/share';
  static String userReels(String userId) => '/users/$userId/reels';
  static const String reels = '/reels';

  // === Library Service endpoints ===
  static const String files = '/files';
  static const String filesCategories = '/files/categories';
  static String fileById(String id) => '/files/$id';
  static String fileDownload(String id) => '/files/$id/download';
  static String filePreview(String id) => '/files/$id/preview';
  static String userFiles(String userId) => '/users/$userId/files';
}
