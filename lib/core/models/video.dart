import '../api/api_endpoints.dart';
import 'user.dart';

String _absUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('/')) {
    return ApiEndpoints.videoBaseUrl.replaceAll('/api/v1', '') + url;
  }
  return url;
}

/// Compact audio summary embedded in video responses.
/// Allows rendering "Музыка: Title — Artist" without a second API call.
class VideoAudioSummary {
  final String id;
  final String title;
  final String artist;
  final String playbackUrl;
  final String coverUrl;
  final String category;
  final bool isOriginalSound;

  const VideoAudioSummary({
    required this.id,
    required this.title,
    required this.artist,
    required this.playbackUrl,
    required this.coverUrl,
    required this.category,
    required this.isOriginalSound,
  });

  factory VideoAudioSummary.fromJson(Map<String, dynamic> j) => VideoAudioSummary(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        artist: j['artist']?.toString() ?? '',
        playbackUrl: j['playback_url']?.toString() ?? '',
        coverUrl: j['cover_url']?.toString() ?? '',
        category: j['category']?.toString() ?? 'music',
        isOriginalSound: j['is_original_sound'] == true,
      );

  String get displayLabel {
    if (artist.isNotEmpty) return '$title — $artist';
    return title;
  }
}

/// One selectable fixed-quality HLS variant (1080p/720p/480p) for the YouTube-
/// style quality picker. Sourced from the GET /videos/:id `renditions` array,
/// ordered highest resolution first. "Авто" is not a rendition — it is the
/// adaptive [Video.hlsMasterUrl].
class VideoRendition {
  final String quality; // 1080p | 720p | 480p
  final String url; // directly-playable variant .m3u8
  final int width;
  final int height;

  const VideoRendition({
    required this.quality,
    required this.url,
    this.width = 0,
    this.height = 0,
  });

  factory VideoRendition.fromJson(Map<String, dynamic> j) => VideoRendition(
        quality: j['quality']?.toString() ?? '',
        url: _absUrl(j['url']),
        width: (j['width'] as num?)?.toInt() ?? 0,
        height: (j['height'] as num?)?.toInt() ?? 0,
      );
}

class VideoCategory {
  final String id;
  final String name;

  VideoCategory({required this.id, required this.name});

  factory VideoCategory.fromJson(Map<String, dynamic> json) => VideoCategory(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
      );
}

class Video {
  final String id;
  final String userId;
  final String title;
  final String description;
  final String videoUrl;
  final String thumbnailUrl;
  final int durationSeconds;
  final String categoryId;
  final String resolution;
  final int viewsCount;
  final int likesCount;
  final int commentsCount;
  final bool isLive;
  final DateTime createdAt;
  final UserShort? user;
  final VideoCategory? category;
  final bool isLiked;
  /// Whether the viewer follows this video's author. Sourced from the
  /// GET /videos/:id response (`is_following`) so the follow button can show
  /// the right initial state without a second profile request.
  final bool isFollowing;
  final String subtitlesUrl;

  // Production fields (migration 066)
  final String status;       // uploading | processing | ready | failed
  final String visibility;   // public | private | unlisted
  final int sizeBytes;
  final String mimeType;
  final String extension;
  final int width;
  final int height;
  final String hlsMasterUrl;
  final String originalFileUrl;

  // Phase 2: attached audio track (migration 069)
  final String? audioTrackId;
  final bool isOriginalAudio;
  final VideoAudioSummary? audioInfo;

  // Phase 10: audio segment metadata (migration 073). No FFmpeg mixing — stored only.
  final int audioStartSeconds;
  final int? audioEndSeconds; // null = play to end
  final double audioVolume; // 0.0–2.0
  final double originalAudioVolume; // 0.0–1.0

  // Phase 8: async original sound extraction status.
  // Values: "queued" | "processing" | "completed" | "failed" | "no_audio" | null
  final String? audioProcessingStatus;

  // Phase 11B: audio/video mix output (migration 000074). No FFmpeg yet — schema only.
  // processedVideoUrl: public URL of the mixed output; null while mixing or not started.
  // mixStatus: null | "queued" | "processing" | "completed" | "failed" | "skipped"
  // mixError: human-readable failure reason; null when not failed.
  final String? processedVideoUrl;
  final String? mixStatus;
  final String? mixError;

  // Phase 12: HLS / quality variants. thumbnailUrl + hlsMasterUrl already exist
  // above; these expose the transcode lifecycle and the qualities that exist.
  // hlsStatus: '' | none | queued | processing | completed | failed | skipped
  final String hlsStatus;
  final List<String> availableQualities; // subset of 1080p/720p/480p

  /// Selectable fixed-quality HLS variants (1080p/720p/480p), highest first.
  /// Only populated on the single-video detail response; empty in list payloads.
  /// Drives the YouTube-style quality picker alongside "Авто" ([hlsMasterUrl]).
  final List<VideoRendition> renditions;

  /// Viewer's saved resume position (seconds). 0 when unwatched.
  final int resumeSeconds;

  Video({
    required this.id,
    required this.userId,
    required this.title,
    this.description = '',
    required this.videoUrl,
    this.thumbnailUrl = '',
    this.durationSeconds = 0,
    this.categoryId = '',
    this.resolution = '',
    this.viewsCount = 0,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.isLive = false,
    required this.createdAt,
    this.user,
    this.category,
    this.isLiked = false,
    this.isFollowing = false,
    this.subtitlesUrl = '',
    this.status = 'ready',
    this.visibility = 'public',
    this.sizeBytes = 0,
    this.mimeType = '',
    this.extension = '',
    this.width = 0,
    this.height = 0,
    this.hlsMasterUrl = '',
    this.originalFileUrl = '',
    this.audioTrackId,
    this.isOriginalAudio = false,
    this.audioInfo,
    this.audioStartSeconds = 0,
    this.audioEndSeconds,
    this.audioVolume = 1.0,
    this.originalAudioVolume = 1.0,
    this.audioProcessingStatus,
    this.processedVideoUrl,
    this.mixStatus,
    this.mixError,
    this.hlsStatus = '',
    this.availableQualities = const [],
    this.renditions = const [],
    this.resumeSeconds = 0,
  });

  factory Video.fromJson(Map<String, dynamic> json) => Video(
        id: json['id'] ?? '',
        userId: json['user_id'] ?? '',
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        videoUrl: _absUrl(json['video_url']),
        thumbnailUrl: _absUrl(json['thumbnail_url']),
        durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
        categoryId: json['category_id'] ?? '',
        resolution: json['resolution'] ?? '',
        viewsCount: (json['views_count'] as num?)?.toInt() ?? 0,
        likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
        commentsCount: (json['comments_count'] as num?)?.toInt() ?? 0,
        isLive: json['is_live'] ?? false,
        createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
        user: json['user'] != null ? UserShort.fromJson(json['user']) : null,
        category: json['category'] != null ? VideoCategory.fromJson(json['category']) : null,
        isLiked: json['is_liked'] ?? false,
        isFollowing: (json['is_following'] as bool?) ?? false,
        subtitlesUrl: _absUrl(json['subtitles_url']),
        status: json['status'] ?? 'ready',
        visibility: json['visibility'] ?? 'public',
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        mimeType: json['mime_type'] ?? '',
        extension: json['extension'] ?? '',
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
        hlsMasterUrl: _absUrl(json['hls_master_url']),
        originalFileUrl: json['original_file_url'] ?? '',
        audioTrackId: json['audio_track_id']?.toString(),
        isOriginalAudio: json['is_original_audio'] == true,
        audioInfo: json['audio'] is Map
            ? VideoAudioSummary.fromJson((json['audio'] as Map).cast<String, dynamic>())
            : null,
        audioStartSeconds: (json['audio_start_seconds'] as num?)?.toInt() ?? 0,
        audioEndSeconds: (json['audio_end_seconds'] as num?)?.toInt(),
        audioVolume: (json['audio_volume'] as num?)?.toDouble() ?? 1.0,
        originalAudioVolume:
            (json['original_audio_volume'] as num?)?.toDouble() ?? 1.0,
        audioProcessingStatus: json['audio_processing_status']?.toString(),
        processedVideoUrl: json['processed_video_url'] as String?,
        mixStatus: json['mix_status'] as String?,
        mixError: json['mix_error'] as String?,
        hlsStatus: json['hls_status']?.toString() ?? '',
        availableQualities: (json['available_qualities'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        renditions: (json['renditions'] as List?)
                ?.whereType<Map>()
                .map((e) => VideoRendition.fromJson(e.cast<String, dynamic>()))
                .where((r) => r.url.isNotEmpty && r.quality.isNotEmpty)
                .toList() ??
            const [],
        resumeSeconds: (json['resume_seconds'] as num?)?.toInt() ?? 0,
      );

  /// Short human-readable segment label for this video's audio selection.
  /// Returns "" when no segment is selected (whole track from start with no end).
  /// Examples: "00:10–00:25", "С 00:10", "Весь трек" (only when info exists).
  String get audioSegmentLabel {
    if (audioTrackId == null) return '';
    final hasStart = audioStartSeconds > 0;
    final hasEnd = audioEndSeconds != null;
    if (!hasStart && !hasEnd) return '';
    if (hasStart && hasEnd) {
      return '${_fmtSec(audioStartSeconds)}–${_fmtSec(audioEndSeconds!)}';
    }
    if (hasStart) return 'С ${_fmtSec(audioStartSeconds)}';
    return 'До ${_fmtSec(audioEndSeconds!)}';
  }

  /// Full segment label for detail view (always shown when audio track present).
  String get audioSegmentDetailLabel {
    if (audioTrackId == null) return '';
    final hasStart = audioStartSeconds > 0;
    final hasEnd = audioEndSeconds != null;
    if (!hasStart && !hasEnd) return 'Весь трек';
    return audioSegmentLabel;
  }

  static String _fmtSec(int s) {
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  /// Best URL for playback.
  /// Priority (Phase 12): completed HLS master (adaptive) → processed mix MP4 →
  /// original MP4. HLS is only preferred once the transcode has actually
  /// finished, so a queued/processing/failed transcode can never break playback.
  /// The HLS master is generated from the processed (mixed) source when a mix
  /// exists, so it already carries the selected audio.
  String get playbackUrl {
    if (hlsStatus == 'completed' && hlsMasterUrl.isNotEmpty) return hlsMasterUrl;
    if (processedVideoUrl != null && processedVideoUrl!.isNotEmpty) return processedVideoUrl!;
    return videoUrl;
  }

  /// True when an adaptive HLS master is ready for playback.
  bool get hasHls => hlsStatus == 'completed' && hlsMasterUrl.isNotEmpty;

  /// True while HD/HLS variants are still being generated.
  bool get isHlsProcessing => hlsStatus == 'queued' || hlsStatus == 'processing';

  /// Passive quality badge text (NOT a selector). 'HD' when a 1080p rung exists,
  /// otherwise '720p' when that rung exists, otherwise '' (no badge).
  String get qualityBadge {
    if (availableQualities.contains('1080p')) return 'HD';
    if (availableQualities.contains('720p')) return '720p';
    return '';
  }

  /// Subtle status line shown while HD versions are generating; null otherwise.
  String? get hlsStatusLabel => isHlsProcessing ? 'HD-версии готовятся' : null;

  /// True when the player should offer a YouTube-style quality picker: an
  /// adaptive HLS master ("Авто") and/or at least one fixed-quality rendition
  /// exists. Hidden only when there is genuinely a single source.
  bool get hasQualityOptions => hasHls || renditions.isNotEmpty;

  /// True when this video looks like a Short: vertical aspect ratio (height > width)
  /// or very short duration (≤ 60 s) when dimensions are unavailable.
  /// NOTE: this is a UI-side classification only. Backend does not yet distinguish
  /// Short vs long-form video. When a proper backend field is added, replace this.
  bool get isShortLike {
    if (width > 0 && height > 0) return height > width; // vertical aspect ratio
    if (durationSeconds > 0) return durationSeconds <= 60;
    return false; // unknown → treat as regular video
  }

  bool get isReady => status == 'ready';
  bool get isProcessing => status == 'uploading' || status == 'processing';
  bool get isPublic => visibility == 'public';

  /// True when original sound extraction is in the queue or actively running.
  bool get isOriginalSoundProcessing =>
      audioInfo == null &&
      (audioProcessingStatus == 'queued' || audioProcessingStatus == 'processing');

  /// True when extraction failed permanently or video has no audio stream.
  bool get originalSoundUnavailable =>
      audioInfo == null &&
      (audioProcessingStatus == 'failed' || audioProcessingStatus == 'no_audio');

  // Phase 11B: mix status convenience getters.
  bool get isMixProcessing => mixStatus == 'queued' || mixStatus == 'processing';
  bool get isMixCompleted  => mixStatus == 'completed';
  bool get isMixFailed     => mixStatus == 'failed';
  bool get isMixSkipped    => mixStatus == 'skipped';

  // Phase 11D: UX helpers.
  /// Short label for feed card audio row; null when no notice needed.
  String? get mixStatusLabel {
    if (mixStatus == 'queued' || mixStatus == 'processing') return 'Звук добавляется';
    if (mixStatus == 'failed') return 'Не удалось добавить звук';
    if (mixStatus == 'skipped') return 'Звук не был добавлен';
    return null;
  }

  /// True when the video has a selected audio track being mixed in the background.
  /// Detail screen shows the original video while displaying a "processing" notice.
  bool get shouldShowMixFallbackNotice => audioTrackId != null && isMixProcessing;

  String get durationFormatted {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get viewsFormatted {
    if (viewsCount >= 1000000) return '${(viewsCount / 1000000).toStringAsFixed(1)}M';
    if (viewsCount >= 1000) return '${(viewsCount / 1000).toStringAsFixed(0)}K';
    return viewsCount.toString();
  }

  String get sizeFormatted {
    if (sizeBytes == 0) return '';
    if (sizeBytes >= 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (sizeBytes >= 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }
}
