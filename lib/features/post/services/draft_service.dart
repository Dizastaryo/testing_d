import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Metadata saved to SharedPreferences. Bytes go to a temp file.
class DraftData {
  final Uint8List? bytes;      // photo bytes (null for video drafts)
  final int publishMode;       // 0 = story, 1 = post
  final bool isVideo;
  final String caption;
  final String location;
  final List<String> tags;
  final String? audioTrackId;
  final bool closeFriendsOnly;
  final DateTime savedAt;

  const DraftData({
    this.bytes,
    required this.publishMode,
    required this.isVideo,
    this.caption = '',
    this.location = '',
    this.tags = const [],
    this.audioTrackId,
    this.closeFriendsOnly = false,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
    'publishMode': publishMode,
    'isVideo': isVideo,
    'caption': caption,
    'location': location,
    'tags': tags,
    'audioTrackId': audioTrackId,
    'closeFriendsOnly': closeFriendsOnly,
    'savedAt': savedAt.toIso8601String(),
  };

  factory DraftData.fromJson(Map<String, dynamic> json, Uint8List? loadedBytes) =>
      DraftData(
        bytes: loadedBytes,
        publishMode: json['publishMode'] as int? ?? 1,
        isVideo: json['isVideo'] as bool? ?? false,
        caption: json['caption'] as String? ?? '',
        location: json['location'] as String? ?? '',
        tags: (json['tags'] as List?)?.cast<String>() ?? [],
        audioTrackId: json['audioTrackId'] as String?,
        closeFriendsOnly: json['closeFriendsOnly'] as bool? ?? false,
        savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class DraftService {
  static const _metaKey = 'seeu_media_draft_meta';
  static const _bytesFileName = 'seeu_draft_photo.png';

  static Future<String> get _bytesPath async {
    final dir = kIsWeb
        ? Directory.systemTemp
        : await getTemporaryDirectory();
    return '${dir.path}/$_bytesFileName';
  }

  static Future<void> save(DraftData draft) async {
    final prefs = await SharedPreferences.getInstance();

    // Save bytes to a temp file (avoids SharedPreferences 2 MB limit).
    if (draft.bytes != null && !kIsWeb) {
      final path = await _bytesPath;
      await File(path).writeAsBytes(draft.bytes!);
    }

    await prefs.setString(_metaKey, jsonEncode(draft.toJson()));
  }

  static Future<DraftData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_metaKey);
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      Uint8List? bytes;
      if (!kIsWeb && !(json['isVideo'] as bool? ?? false)) {
        final path = await _bytesPath;
        final file = File(path);
        if (await file.exists()) bytes = await file.readAsBytes();
      }
      return DraftData.fromJson(json, bytes);
    } catch (e) {
      debugPrint('DraftService.load error: $e');
      return null;
    }
  }

  static Future<bool> hasDraft() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_metaKey);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_metaKey);
    if (!kIsWeb) {
      try {
        final path = await _bytesPath;
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}
