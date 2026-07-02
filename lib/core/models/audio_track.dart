import '../api/api_endpoints.dart';

List<double>? _parseWaveform(dynamic raw) {
  if (raw == null) return null;
  if (raw is! List) return null;
  if (raw.isEmpty) return null;
  final result = <double>[];
  for (final v in raw) {
    final d = (v as num?)?.toDouble() ?? 0.0;
    result.add(d.clamp(0.0, 1.0));
  }
  return result.isEmpty ? null : result;
}

String _absUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('http')) return url;
  if (url.startsWith('/')) {
    return ApiEndpoints.baseUrl.replaceAll('/api/v1', '') + url;
  }
  return url;
}

class AudioTrack {
  final String id;
  final String title;
  final String artist;
  final String coverUrl;
  final String audioUrl;
  /// Backend-provided playback URL (preferred over audioUrl).
  final String playbackUrl;
  final int durationSeconds;
  final int usesCount;
  final String genre;
  final String userId;
  /// "pending" | "approved" | "rejected" — empty for legacy seed rows.
  final String status;
  final String rejectionReason;
  /// MUSIC-2: LRC-формат текст.
  final String lyricsLrc;

  // Production fields (migration 000067)
  final String visibility;  // "public" | "private" | "unlisted"
  final String category;
  final String subcategory;
  final String album;
  final String description;
  final String genre2;      // kept for compat — same as genre
  final String mood;
  final String mimeType;
  final String extension;
  final int sizeBytes;

  // Phase 8: origin tracking (migration 000069).
  final bool isOriginalSound;
  final String sourceType;     // "uploaded" | "original_video_audio"
  final String? sourceVideoId; // set when isOriginalSound==true

  // Phase 9: technical metadata (migration 000072).
  final int bitrate;           // kbps; 0 = unknown
  final int sampleRate;        // Hz; 0 = unknown
  final int channels;          // 0 = unknown
  final List<double>? waveformData; // 100 normalized peaks [0.0–1.0]; null = not available

  // Phase 3: engagement counters and viewer-contextual state.
  final int likesCount;
  final int playsCount;
  final bool isLikedByMe;
  final bool isSavedByMe;

  AudioTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.coverUrl,
    required this.audioUrl,
    this.playbackUrl = '',
    required this.durationSeconds,
    this.usesCount = 0,
    this.genre = '',
    this.userId = '',
    this.status = 'approved',
    this.rejectionReason = '',
    this.lyricsLrc = '',
    this.visibility = 'public',
    this.category = 'music',
    this.subcategory = '',
    this.album = '',
    this.description = '',
    this.genre2 = '',
    this.mood = '',
    this.mimeType = '',
    this.extension = '',
    this.sizeBytes = 0,
    this.isOriginalSound = false,
    this.sourceType = 'uploaded',
    this.sourceVideoId,
    this.bitrate = 0,
    this.sampleRate = 0,
    this.channels = 0,
    this.waveformData,
    this.likesCount = 0,
    this.playsCount = 0,
    this.isLikedByMe = false,
    this.isSavedByMe = false,
  });

  factory AudioTrack.fromJson(Map<String, dynamic> j) {
    final rawPlaybackUrl = j['playback_url']?.toString() ?? '';
    final rawAudioUrl = j['audio_url']?.toString() ?? '';
    final resolvedPlayback = rawPlaybackUrl.isNotEmpty
        ? _absUrl(rawPlaybackUrl)
        : _absUrl(rawAudioUrl);
    return AudioTrack(
      id: j['id'] ?? '',
      title: j['title'] ?? '',
      artist: j['artist'] ?? '',
      coverUrl: _absUrl(j['cover_url']),
      audioUrl: _absUrl(rawAudioUrl),
      playbackUrl: resolvedPlayback,
      durationSeconds: j['duration_seconds'] ?? 0,
      usesCount: (j['uses_count'] as num?)?.toInt() ?? 0,
      genre: j['genre'] ?? '',
      userId: j['user_id']?.toString() ?? '',
      status: j['status']?.toString() ?? 'approved',
      rejectionReason: j['rejection_reason']?.toString() ?? '',
      lyricsLrc: j['lyrics_lrc']?.toString() ?? '',
      visibility: j['visibility']?.toString() ?? 'public',
      category: j['category']?.toString() ?? 'music',
      subcategory: j['subcategory']?.toString() ?? '',
      album: j['album']?.toString() ?? '',
      description: j['description']?.toString() ?? '',
      genre2: j['genre']?.toString() ?? '',
      mood: j['mood']?.toString() ?? '',
      mimeType: j['mime_type']?.toString() ?? '',
      extension: j['extension']?.toString() ?? '',
      sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
      isOriginalSound: j['is_original_sound'] == true,
      sourceType: j['source_type']?.toString() ?? 'uploaded',
      sourceVideoId: j['source_video_id']?.toString(),
      bitrate: (j['bitrate'] as num?)?.toInt() ?? 0,
      sampleRate: (j['sample_rate'] as num?)?.toInt() ?? 0,
      channels: (j['channels'] as num?)?.toInt() ?? 0,
      waveformData: _parseWaveform(j['waveform_data']),
      likesCount: (j['likes_count'] as num?)?.toInt() ?? 0,
      playsCount: (j['plays_count'] as num?)?.toInt() ?? 0,
      isLikedByMe: j['is_liked_by_me'] == true,
      isSavedByMe: j['is_saved_by_me'] == true,
    );
  }

  /// Returns a copy with updated engagement state.
  AudioTrack copyWith({bool? isLikedByMe, bool? isSavedByMe, int? likesCount}) => AudioTrack(
        id: id, title: title, artist: artist, coverUrl: coverUrl, audioUrl: audioUrl,
        playbackUrl: playbackUrl, durationSeconds: durationSeconds, usesCount: usesCount,
        genre: genre, userId: userId, status: status, rejectionReason: rejectionReason,
        lyricsLrc: lyricsLrc, visibility: visibility, category: category,
        subcategory: subcategory, album: album, description: description,
        genre2: genre2, mood: mood, mimeType: mimeType, extension: extension,
        sizeBytes: sizeBytes,
        isOriginalSound: isOriginalSound, sourceType: sourceType, sourceVideoId: sourceVideoId,
        bitrate: bitrate, sampleRate: sampleRate, channels: channels, waveformData: waveformData,
        likesCount: likesCount ?? this.likesCount,
        playsCount: playsCount,
        isLikedByMe: isLikedByMe ?? this.isLikedByMe,
        isSavedByMe: isSavedByMe ?? this.isSavedByMe,
      );

  bool get isReady => status == 'approved';
  bool get isPending => status == 'pending';
  bool get isPublic => visibility == 'public';

  String get durationFormatted {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get sizeFormatted {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get displayArtist => artist.isNotEmpty ? artist : 'Неизвестный артист';

  /// e.g. "128 kbps · 44100 Hz · стерео"
  String get technicalSummary {
    final parts = <String>[];
    if (bitrate > 0) parts.add('$bitrate kbps');
    if (sampleRate > 0) {
      parts.add(sampleRate >= 1000 ? '${sampleRate ~/ 1000} kHz' : '$sampleRate Hz');
    }
    if (channels == 1) parts.add('моно');
    if (channels == 2) parts.add('стерео');
    if (channels > 2) parts.add('$channels ch');
    return parts.join(' · ');
  }
}

/// MUSIC-2: одна строка LRC-lyrics с timestamp'ом в миллисекундах.
class LyricLine {
  final int timeMs;
  final String text;
  const LyricLine(this.timeMs, this.text);
}

/// Парсит LRC-формат «[mm:ss.xx]Line\n[mm:ss.xx]Next line\n...».
/// Игнорирует metadata lines («[ar:Artist]», «[ti:Title]» etc).
/// Возвращает sorted-by-time список или пустой если parse failed.
List<LyricLine> parseLrc(String lrc) {
  if (lrc.isEmpty) return const [];
  final regex = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]([^\[]*)');
  final out = <LyricLine>[];
  for (final m in regex.allMatches(lrc)) {
    final mm = int.tryParse(m.group(1) ?? '0') ?? 0;
    final ss = int.tryParse(m.group(2) ?? '0') ?? 0;
    final centi = int.tryParse(m.group(3) ?? '0') ?? 0;
    final text = (m.group(4) ?? '').trim();
    if (text.isEmpty) continue;
    final timeMs = mm * 60000 + ss * 1000 + centi * 10;
    out.add(LyricLine(timeMs, text));
  }
  out.sort((a, b) => a.timeMs.compareTo(b.timeMs));
  return out;
}

/// Memoised [parseLrc] keyed by track id so synced-lyrics widgets that rebuild
/// every position tick (mini-player subtitle, lyrics screen) parse the LRC
/// once per track instead of once per frame.
final Map<String, List<LyricLine>> _lrcCache = {};
List<LyricLine> parseLrcCached(String trackId, String lrc) {
  if (lrc.isEmpty) return const [];
  return _lrcCache.putIfAbsent('$trackId|${lrc.length}', () => parseLrc(lrc));
}

/// Текущая строка lyrics для player position. Берёт последнюю с timestamp
/// `<= positionMs`. null если до первой строки.
LyricLine? currentLyricAt(List<LyricLine> lines, int positionMs) {
  if (lines.isEmpty) return null;
  LyricLine? cur;
  for (final l in lines) {
    if (l.timeMs <= positionMs) {
      cur = l;
    } else {
      break;
    }
  }
  return cur;
}
