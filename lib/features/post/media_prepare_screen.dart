import 'dart:async' show Timer, unawaited;
import 'dart:io' show File;
import 'dart:math' show sqrt;
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import '../../core/design/design.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/models/story.dart';
import '../../core/providers/feed_provider.dart';
import '../../core/providers/post_compose_provider.dart';
import '../../core/providers/sbory_city_provider.dart' show kKazakhstanCities;
import '../camera/widgets/camera_bottom_panel.dart' show kStoryMaxVideoSeconds;
import '../camera/widgets/camera_ui_kit.dart';
import 'services/draft_service.dart';
import 'services/video_trim_service.dart';
import 'video_trim_screen.dart';
import 'widgets/music_picker_sheet.dart';
import 'widgets/waveform_range_trimmer.dart';

/// Intermediate screen shown after camera capture or gallery pick.
/// Allows user to:
/// 1. Preview media in story (9:16) and post (1:1 / 4:5) formats
/// 2. Choose to publish as Story or Post
/// 3. Add caption, location, tags (for Post)
/// 4. Crop / adjust framing
class MediaPrepareScreen extends ConsumerStatefulWidget {
  final XFile file;
  final bool isVideo;
  /// 0 = История, 1 = Публикация. null → default (1).
  final int? initialPublishMode;
  /// Трек, выбранный на экране камеры — предзаполняется в форме.
  final AudioTrack? preselectedTrack;
  /// Where in the track the music started while recording — pre-fills the trimmer.
  final double initialAudioStartSec;
  /// Pre-loaded bytes (e.g. from camera + editor). Skips re-reading the file.
  final Uint8List? preloadedBytes;
  /// Additional photos for carousel (multi-photo post). Empty for single.
  final List<XFile> extraFiles;
  /// Pre-loaded bytes for extraFiles (parallel list).
  final List<Uint8List> extraBytes;
  /// Hero tag for shared-element transition from camera gallery button.
  final String? heroTag;

  const MediaPrepareScreen({
    super.key,
    required this.file,
    required this.isVideo,
    this.initialPublishMode,
    this.preselectedTrack,
    this.initialAudioStartSec = 0,
    this.preloadedBytes,
    this.extraFiles = const [],
    this.extraBytes = const [],
    this.heroTag,
  });

  @override
  ConsumerState<MediaPrepareScreen> createState() => _MediaPrepareScreenState();
}

class _MediaPrepareScreenState extends ConsumerState<MediaPrepareScreen>
    with SingleTickerProviderStateMixin {
  // 0 = Story, 1 = Post
  int _publishMode = 1;
  _PublishState _publishState = _PublishState.idle;

  // ── Two-step flow ──────────────────────────────────────────────────────────
  _EditStep _step = _EditStep.edit;
  bool _stepForward = true; // direction of AnimatedSwitcher slide

  // ── Photo enhancement ──────────────────────────────────────────────────────
  _EnhanceTool _activeTool = _EnhanceTool.none;
  double _brightness = 0.0;
  double _contrast   = 0.0;
  double _saturation = 0.0;
  double _warmth     = 0.0;

  // ── Story audience ─────────────────────────────────────────────────────────
  bool _closeFriendsOnly = false;

  // Post aspect ratio: 0 = 1:1, 1 = 4:5, 2 = 9:16
  int _aspectIdx = 1;
  static const _aspects = [1.0, 4.0 / 5.0, 9.0 / 16.0];
  static const _aspectLabels = ['1:1', '4:5', '9:16'];

  // Post form
  final _captionCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final List<String> _tags = [];
  double _uploadProgress = 0.0;
  int _uploadedBytes = 0;
  int _totalBytes = 0;
  String? _publishError;
  AudioTrack? _selectedTrack;
  double _audioStartSec = 0; // start of selected audio segment
  // Video + music: when true the video's own audio is stripped so only the
  // chosen track is heard.
  bool _muteOriginal = false;

  // ── Canvas editor state (per-tab, so История and Публикация don't share) ──
  final GlobalKey _storyCanvasKey = GlobalKey();
  final GlobalKey _postCanvasKey  = GlobalKey();

  final List<_CanvasLayer> _storyLayers = [];
  final List<_CanvasLayer> _postLayers  = [];

  // One-level undo per tab (snapshot before last destructive operation).
  List<_CanvasLayer>? _storyUndo;
  List<_CanvasLayer>? _postUndo;

  // Pre-composited bytes captured when user taps "Далее →".
  // Includes enhancement filters + canvas layers baked from RepaintBoundary.
  // Used as the upload payload and the details-step thumbnail.
  Uint8List? _compositedBytes;

  // ── Multi-photo carousel ──────────────────────────────────────────────────
  // Index of active slot in the carousel (0 = primary file, 1+ = extra files)
  int _activeSlot = 0;
  // PageController for swiping between photos in the edit step
  late final PageController _carouselCtrl;

  // ── Video cover frame ─────────────────────────────────────────────────────
  // Selected cover frame time in seconds (null = use first frame)
  double? _coverFrameSec;
  // Thumbnails for the frame picker strip (generated on first open)
  List<Uint8List> _coverFrameThumbs = [];
  bool _coverPickerVisible = false;
  Uint8List? _uploadedCoverBytes; // frame to upload as separate thumbnail

  // ── Video thumbnail for details step ─────────────────────────────────────
  Uint8List? _videoThumbBytes;

  // ── Story details extras ──────────────────────────────────────────────────
  final TextEditingController _storyCaptionCtrl = TextEditingController();
  // 0 = all, 1 = friends only, 2 = nobody
  int _replyAudience = 0;

  // ── Haptic threshold tracking ─────────────────────────────────────────────
  // Last enhancement value bucket to avoid spamming haptics
  int _lastHapticBucket = 0;

  int _stNextId = 1;

  // Per-tab selection (so selecting a layer on one tab doesn't bleed to the other).
  int? _storySelectedLayerId;
  int? _postSelectedLayerId;

  // Per-tab media pinch+pan (so каждая вкладка запоминает своё кадрирование).
  double _storyScale  = 1.0;
  Offset _storyOffset = Offset.zero;
  double _postScale   = 1.0;
  Offset _postOffset  = Offset.zero;

  double _mediaGestureBaseScale    = 1.0;
  Offset _mediaGestureBaseOffset   = Offset.zero;
  Offset _mediaGestureFocalStart   = Offset.zero;

  // Convenience getters/setters — all existing code keeps using _layers /
  // _selectedLayerId / _mediaScale / _mediaOffset without any changes.
  List<_CanvasLayer> get _layers =>
      _publishMode == 0 ? _storyLayers : _postLayers;

  int? get _selectedLayerId =>
      _publishMode == 0 ? _storySelectedLayerId : _postSelectedLayerId;
  set _selectedLayerId(int? v) {
    if (_publishMode == 0) {
      _storySelectedLayerId = v;
    } else {
      _postSelectedLayerId = v;
    }
  }

  double get _mediaScale => _publishMode == 0 ? _storyScale : _postScale;
  set _mediaScale(double v) {
    if (_publishMode == 0) { _storyScale = v; } else { _postScale = v; }
  }

  Offset get _mediaOffset => _publishMode == 0 ? _storyOffset : _postOffset;
  set _mediaOffset(Offset v) {
    if (_publishMode == 0) { _storyOffset = v; } else { _postOffset = v; }
  }

  // per-layer gesture base values (tracked during gesture)
  double _layerGestureBaseScale    = 1.0;
  double _layerGestureBaseRotation = 0.0;

  // ID of the most recently added layer — used for pop-in animation
  int? _lastAddedLayerId;

  // text editor overlay
  bool _isEditingText = false;
  int? _editingLayerId; // null = creating new layer
  final _stTextCtrl = TextEditingController();
  final _stTextFocus = FocusNode();
  Color _editTextColor = Colors.white;
  _BgStyle _editBgStyle = _BgStyle.none;
  Color _editBgColor = Colors.black;
  double _editFontSize = 24.0;
  _TextAlign2 _editAlign = _TextAlign2.center;

  // GPS loading indicator
  bool _gpsLoading = false;

  // Crop frame guide — shown during pan/zoom, fades after 1.8s
  bool _cropGuideVisible = false;
  Timer? _cropGuideTimer;

  // Pinch-to-crop hint — shown once per screen open, disappears after 2.5s
  bool _cropHintVisible = false;
  Timer? _cropHintTimer;

  // Duration of trimmed video (set after VideoTrimScreen returns)
  double _trimmedDurationSec = 0;

  // Video preview
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;
  double _videoDurationSec = 0;
  // Path to a physically trimmed copy (ffmpeg). When set, it replaces the
  // original for preview + upload.
  String? _trimmedVideoPath;

  /// A video longer than 1 minute can't be a Story (only a Reel/post).
  bool get _storyTooLong =>
      widget.isVideo && _videoDurationSec > kStoryMaxVideoSeconds;

  /// Label for the post destination — a video post is a Reel.
  String get _postLabel => widget.isVideo ? 'Рилс' : 'Публикация';

  // Cached bytes for cross-platform image preview and upload (web has no real file path).
  Uint8List? _bytes;
  // Если юзер применил AI-стилизацию — bytes заменены, и filename должен
  // отличаться от исходного (PNG вместо JPG, новое имя).
  String? _stylizedFilename;
  // STORY-3: interactive poll, добавленный в Story Editor. null если poll'я нет.
  StoryPoll? _pendingPoll;

  @override
  void initState() {
    super.initState();
    _carouselCtrl = PageController();
    // Apply params passed from camera screen
    _publishMode = widget.initialPublishMode ?? 1;
    if (widget.preselectedTrack != null) {
      _selectedTrack = widget.preselectedTrack;
      _audioStartSec = widget.initialAudioStartSec;
    }
    // Use preloaded bytes if provided (avoids re-reading file)
    if (widget.preloadedBytes != null) {
      _bytes = widget.preloadedBytes;
    } else if (!widget.isVideo) {
      // Videos can be very large — skip loading into RAM; upload streams from file.
      _loadBytes();
    }

    // Also pick up track from Music screen pendingPostTrackProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = ref.read(pendingPostTrackProvider);
      if (pending != null && widget.isVideo && mounted) {
        setState(() {
          _selectedTrack = pending;
          _publishMode = 1;
        });
        ref.read(pendingPostTrackProvider.notifier).state = null;
      }
    });

    // Show pinch-to-crop hint once per screen open after a short delay
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() => _cropHintVisible = true);
        _cropHintTimer = Timer(const Duration(milliseconds: 2500), () {
          if (mounted) setState(() => _cropHintVisible = false);
        });
      }
    });

    if (widget.isVideo) {
      // На web путь — это blob://, на mobile — реальный путь файла.
      // VideoPlayerController.file использует dart:io.File, на web он валится.
      _videoCtrl = kIsWeb
          ? VideoPlayerController.networkUrl(Uri.parse(widget.file.path))
          : VideoPlayerController.file(File(widget.file.path));
      _videoCtrl!
        ..setLooping(true)
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _videoReady = true;
              _videoDurationSec =
                  _videoCtrl!.value.duration.inMilliseconds / 1000.0;
              // A long video can't be a Story — fall back to a Reel.
              if (_storyTooLong && _publishMode == 0) _publishMode = 1;
            });
            _videoCtrl!.play();
            // Generate a video thumbnail for the details-step preview
            _generateVideoThumb();
          }
        }).catchError((e) {
          debugPrint('media_prepare video init: $e');
        });
    }
  }

  Future<void> _generateVideoThumb() async {
    if (!widget.isVideo || kIsWeb) return;
    try {
      final thumb = await vt.VideoThumbnail.thumbnailData(
        video: widget.file.path,
        imageFormat: vt.ImageFormat.JPEG,
        maxWidth: 300,
        quality: 80,
        timeMs: 0,
      );
      if (thumb != null && mounted) setState(() => _videoThumbBytes = thumb);
    } catch (e) {
      debugPrint('_generateVideoThumb: $e');
    }
  }

  Future<void> _generateCoverFrameThumbs() async {
    if (!widget.isVideo || kIsWeb || _coverFrameThumbs.isNotEmpty) return;
    final dur = _videoDurationSec;
    if (dur <= 0) return;
    // Generate 8 evenly-spaced frames
    const count = 8;
    final results = <Uint8List>[];
    for (int i = 0; i < count; i++) {
      final ms = ((dur / (count - 1)) * i * 1000).round().clamp(0, (dur * 1000).round());
      try {
        final t = await vt.VideoThumbnail.thumbnailData(
          video: widget.file.path,
          imageFormat: vt.ImageFormat.JPEG,
          maxWidth: 120,
          quality: 70,
          timeMs: ms,
        );
        if (t != null) results.add(t);
      } catch (_) {}
    }
    if (mounted && results.isNotEmpty) {
      setState(() => _coverFrameThumbs = results);
    }
  }

  Future<void> _loadBytes() async {
    try {
      final b = await widget.file.readAsBytes();
      if (mounted) setState(() => _bytes = b);
    } catch (e) {
      debugPrint('media_prepare readAsBytes: $e');
    }
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _locationCtrl.dispose();
    _tagCtrl.dispose();
    _tagFocus.dispose();
    _stTextCtrl.dispose();
    _stTextFocus.dispose();
    _storyCaptionCtrl.dispose();
    _carouselCtrl.dispose();
    _videoCtrl?.dispose();
    _cropGuideTimer?.cancel();
    _cropHintTimer?.cancel();
    super.dispose();
  }

  final _tagFocus = FocusNode();

  void _addTag() {
    // Strip # prefix, whitespace, and non-word characters.
    final raw = _tagCtrl.text
        .trim()
        .replaceAll('#', '')
        .replaceAll(RegExp(r'[^\w]'), '');
    if (raw.isEmpty) return;
    if (_tags.length >= 30) {
      showSeeUSnackBar(context, 'Максимум 30 тегов', tone: SeeUTone.danger);
      return;
    }
    if (!_tags.contains(raw)) setState(() => _tags.add(raw));
    _tagCtrl.clear();
    // Re-focus so the user can immediately type the next tag.
    _tagFocus.requestFocus();
  }

  // ── Back confirmation ──────────────────────────────────────────────────

  bool get _hasUnsavedWork =>
      _storyLayers.isNotEmpty ||
      _postLayers.isNotEmpty ||
      _selectedTrack != null ||
      _captionCtrl.text.isNotEmpty ||
      _tags.isNotEmpty;

  Future<void> _confirmBack() async {
    if (!_hasUnsavedWork) {
      Navigator.of(context).pop();
      return;
    }
    final c = context.seeuColors;
    // 0 = stay, 1 = save draft, 2 = discard
    final action = await showSeeUBottomSheet<int>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(PhosphorIconsRegular.warning,
                size: 32, color: SeeUColors.amber),
            const SizedBox(height: 14),
            Text('ЧЕРНОВИК',
                style:
                    SeeUTypography.kicker.copyWith(color: SeeUColors.accent)),
            const SizedBox(height: 4),
            Text('Сохранить черновик?',
                style: SeeUTypography.displayS.copyWith(color: c.ink)),
            const SizedBox(height: 8),
            Text(
              'Вы можете продолжить позже\nили отменить все правки.',
              textAlign: TextAlign.center,
              style: SeeUTypography.caption.copyWith(color: c.ink3),
            ),
            const SizedBox(height: 20),
            // Save draft button
            GestureDetector(
              onTap: () => Navigator.pop(context, 1),
              child: Container(
                height: 52,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [SeeUColors.accentSecondary, SeeUColors.accent],
                  ),
                  borderRadius: BorderRadius.circular(SeeURadii.medium),
                  boxShadow: [
                    BoxShadow(
                        color: SeeUColors.accent.withValues(alpha: 0.35),
                        blurRadius: 16, offset: const Offset(0, 6)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(PhosphorIconsRegular.bookmarkSimple,
                        color: Colors.white, size: 17),
                    const SizedBox(width: 8),
                    Text('Сохранить черновик',
                        style: SeeUTypography.body.copyWith(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, 0),
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(SeeURadii.medium),
                        border: Border.all(color: c.line),
                      ),
                      child: Text('Остаться',
                          style: SeeUTypography.body.copyWith(
                              color: c.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, 2),
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(SeeURadii.medium),
                        border: Border.all(color: SeeUColors.error.withValues(alpha: 0.4)),
                      ),
                      child: Text('Отменить',
                          style: SeeUTypography.body.copyWith(
                              color: SeeUColors.error,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 1) {
      await _saveDraft();
      if (mounted) Navigator.of(context).pop();
    } else if (action == 2) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _saveDraft() async {
    HapticFeedback.mediumImpact();
    try {
      await DraftService.save(DraftData(
        bytes: _compositedBytes ?? _bytes,
        publishMode: _publishMode,
        isVideo: widget.isVideo,
        caption: _captionCtrl.text,
        location: _locationCtrl.text,
        tags: List.from(_tags),
        audioTrackId: _selectedTrack?.id.toString(),
        closeFriendsOnly: _closeFriendsOnly,
        savedAt: DateTime.now(),
      ));
      if (mounted) {
        showSeeUSnackBar(context, 'Черновик сохранён',
            tone: SeeUTone.success);
      }
    } catch (e) {
      debugPrint('_saveDraft error: $e');
    }
  }

  // ── Publish ────────────────────────────────────────────────────────────

  Future<void> _publish() async {
    if (_publishState != _PublishState.idle &&
        _publishState != _PublishState.failed) { return; }
    if (_publishMode == 0 && _storyTooLong) {
      showSeeUSnackBar(
          context, 'Для истории видео должно быть не длиннее 1 минуты',
          tone: SeeUTone.danger, duration: const Duration(seconds: 2));
      return;
    }
    _videoCtrl?.pause();
    setState(() {
      _publishState = _PublishState.preparing;
      _uploadProgress = 0.0;
      _uploadedBytes = 0;
      _totalBytes = 0;
      _publishError = null;
    });

    try {
      final api = ref.read(apiClientProvider);

      // 0a/0b. Photo composite — use pre-baked bytes from _compositeForDetails().
      // _compositedBytes was captured on "Далее →" while the RepaintBoundary was
      // still in the tree, so it includes enhancement filters + canvas layers.
      // This also handles the case where no layers exist but enhancement was set.
      if (!widget.isVideo && _compositedBytes != null) {
        _bytes = _compositedBytes;
        final prefix = _publishMode == 0 ? 'story' : 'post';
        _stylizedFilename = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.png';
      }

      // 0c. Mute original audio if music track is selected.
      if (widget.isVideo && _selectedTrack != null && _muteOriginal) {
        final src = _trimmedVideoPath ?? widget.file.path;
        final muted = await VideoTrimService.stripAudio(src);
        if (muted != null) {
          _trimmedVideoPath = muted;
          _stylizedFilename =
              'muted_${DateTime.now().millisecondsSinceEpoch}.mp4';
        }
      }

      // 1. Upload media file — switch to uploading state with progress.
      // _totalBytes starts at 0; onSendProgress will fill it from multipart total.
      if (mounted) {
        setState(() {
          _publishState = _PublishState.uploading;
          _totalBytes = _bytes?.length ?? 0;
        });
      }

      final uploadName = _stylizedFilename ?? widget.file.name;
      final MultipartFile mediaFile;
      if (widget.isVideo) {
        final path = _trimmedVideoPath ?? widget.file.path;
        mediaFile = await MultipartFile.fromFile(path, filename: uploadName);
      } else {
        final bytes = _bytes ?? await widget.file.readAsBytes();
        mediaFile = MultipartFile.fromBytes(bytes, filename: uploadName);
      }
      final formData = FormData.fromMap({'file': mediaFile});
      final uploadResp = await api.post(
        ApiEndpoints.mediaUpload,
        data: formData,
        onSendProgress: (sent, total) {
          if (mounted) {
            setState(() {
              _uploadProgress = total > 0 ? sent / total : 0.0;
              _uploadedBytes = sent;
              if (_totalBytes == 0 && total > 0) _totalBytes = total;
            });
          }
        },
        options: Options(
          sendTimeout: const Duration(seconds: 120),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final mediaUrl = uploadResp.data['data']['url'] as String;
      final mediaType = widget.isVideo ? 'video' : 'image';

      // 2. Create story or post — switch to processing state.
      if (mounted) setState(() => _publishState = _PublishState.processing);

      String? publishedId;

      if (_publishMode == 0) {
        final storyData = <String, dynamic>{
          'media_url': mediaUrl,
          'media_type': mediaType,
        };
        if (_selectedTrack != null && !widget.isVideo) {
          storyData['audio_track_id'] = _selectedTrack!.id;
          if (_audioStartSec > 0) {
            storyData['audio_start_seconds'] = _audioStartSec.toInt();
          }
        }
        if (_pendingPoll != null) {
          storyData['poll'] = _pendingPoll!.toJson();
        }
        if (_storyLayers.isNotEmpty) {
          storyData['layers'] = _storyLayers.map((l) => l.toJson()).toList();
        }
        if (_closeFriendsOnly) {
          storyData['close_friends_only'] = true;
        }
        if (_replyAudience > 0) {
          storyData['reply_audience'] =
              const ['all', 'friends', 'none'][_replyAudience];
        }
        final storyCap = _storyCaptionCtrl.text.trim();
        if (storyCap.isNotEmpty) storyData['caption'] = storyCap;
        final storyResp =
            await api.post(ApiEndpoints.stories, data: storyData);
        publishedId =
            (storyResp.data?['data'] as Map?)?['id']?.toString();
      } else {
        final captionParts = <String>[];
        if (_captionCtrl.text.trim().isNotEmpty) {
          captionParts.add(_captionCtrl.text.trim());
        }
        if (_tags.isNotEmpty) {
          captionParts.add(_tags.map((t) => '#$t').join(' '));
        }
        // Upload extra photos for carousel
        final extraUrls = <String>[];
        for (final xf in widget.extraFiles) {
          try {
            final bytes = await xf.readAsBytes();
            final mf = MultipartFile.fromBytes(bytes, filename: xf.name);
            final resp = await api.post(
              ApiEndpoints.mediaUpload,
              data: FormData.fromMap({'file': mf}),
              options: Options(
                sendTimeout: const Duration(seconds: 120),
                receiveTimeout: const Duration(seconds: 60),
              ),
            );
            final url = resp.data['data']['url'] as String?;
            if (url != null) extraUrls.add(url);
          } catch (e) {
            debugPrint('extra photo upload: $e');
          }
        }

        // Upload video cover frame if selected
        String? coverUrl;
        if (widget.isVideo && _uploadedCoverBytes != null) {
          try {
            final mf = MultipartFile.fromBytes(
              _uploadedCoverBytes!,
              filename: 'cover_${DateTime.now().millisecondsSinceEpoch}.jpg',
            );
            final resp = await api.post(
              ApiEndpoints.mediaUpload,
              data: FormData.fromMap({'file': mf}),
              options: Options(
                sendTimeout: const Duration(seconds: 60),
                receiveTimeout: const Duration(seconds: 30),
              ),
            );
            coverUrl = resp.data['data']['url'] as String?;
          } catch (e) {
            debugPrint('cover upload: $e');
          }
        }

        final allMediaUrls = [mediaUrl, ...extraUrls];
        final allMediaTypes = List.filled(allMediaUrls.length, mediaType);

        final postData = <String, dynamic>{
          'caption': captionParts.isNotEmpty ? captionParts.join('\n\n') : '',
          'media_urls': allMediaUrls,
          'media_types': allMediaTypes,
        };
        if (coverUrl != null) postData['thumbnail_url'] = coverUrl;
        if (_selectedTrack != null) {
          postData['audio_track_id'] = _selectedTrack!.id;
          if (_audioStartSec > 0) {
            postData['audio_start_seconds'] = _audioStartSec.round();
          }
        }
        final loc = _locationCtrl.text.trim();
        if (loc.isNotEmpty) postData['location'] = loc;

        final postResp = await api.post(ApiEndpoints.posts, data: postData);
        publishedId =
            (postResp.data?['data'] as Map?)?['id']?.toString();
        if (mounted) ref.read(feedProvider.notifier).refresh();
      }

      // 3. Success — brief flash then navigate via GoRouter.
      if (mounted) {
        setState(() => _publishState = _PublishState.success);
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          context.go('/publish-success', extra: <String, dynamic>{
            'thumbnailBytes': widget.isVideo
                ? _videoThumbBytes
                : (_compositedBytes ?? _bytes),
            'isStory': _publishMode == 0,
            'publishedId': publishedId,
          });
        }
      }
    } catch (e) {
      debugPrint('Publish error: $e');
      if (mounted) {
        String msg = 'Не удалось опубликовать';
        if (e is DioException && e.response != null) {
          final data = e.response?.data;
          if (data is Map && data['error'] != null) {
            msg = data['error'].toString();
          }
        }
        setState(() {
          _publishState = _PublishState.failed;
          _publishError = msg;
        });
        if (_videoReady) _videoCtrl?.play();
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      resizeToAvoidBottomInset: !_isEditingText,
      body: Stack(
        children: [
          GestureDetector(
            // Pull-to-dismiss: fast downward swipe navigates back / to edit step
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 900 && !_isEditingText) {
                if (_step == _EditStep.details) {
                  setState(() { _stepForward = false; _step = _EditStep.edit; });
                } else {
                  _confirmBack();
                }
              }
            },
            child: SafeArea(
              child: AnimatedSwitcher(
                duration: SeeUMotion.slow,
                transitionBuilder: (child, animation) {
                  final fwd = _stepForward;
                  final entering = child.key == ValueKey(_step);
                  final dx = fwd
                      ? (entering ? 1.0 : -1.0)
                      : (entering ? -1.0 : 1.0);
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(dx, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                        parent: animation, curve: SeeUMotion.smooth)),
                    child: child,
                  );
                },
                child: _step == _EditStep.edit
                    ? _buildEditPage(c)
                    : _buildDetailsPage(c),
              ),
            ),
          ),
          // Full-screen inline text editor (story + post photo mode).
          if (_isEditingText) _buildFullScreenTextEditor(c),
        ],
      ),
    );
  }

  // ── Top bar (edit step) ────────────────────────────────────────────────

  Widget _buildTopBarEdit(SeeUThemeColors c) {
    final hasUndo = _publishMode == 0 ? _storyUndo != null : _postUndo != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          // Back — glass rounded square
          _GlassSquareButton(
            onTap: _confirmBack,
            child: Icon(PhosphorIconsBold.caretLeft, color: c.ink, size: 19),
          ),
          // Segmented control as the primary format switch.
          Expanded(child: Center(child: _buildModeSegment(c))),
          // Undo button — shown only when undo is available
          if (hasUndo) ...[
            _GlassSquareButton(
              onTap: _undo,
              child: const Icon(PhosphorIconsRegular.arrowCounterClockwise,
                  color: SeeUColors.accent, size: 18),
            ),
            const SizedBox(width: 8),
          ],
          // Save/Share button
          Tooltip(
            message: 'Сохранить / Поделиться',
            child: _GlassSquareButton(
              onTap: _downloadMedia,
              child: Icon(PhosphorIconsRegular.downloadSimple,
                  color: c.ink, size: 19),
            ),
          ),
        ],
      ),
    );
  }


  Future<void> _downloadMedia() async {
    HapticFeedback.lightImpact();
    try {
      final filePath = _trimmedVideoPath ?? widget.file.path;
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Сохранить в галерею',
      );
    } catch (e) {
      if (mounted) {
        showSeeUSnackBar(context, 'Не удалось поделиться файлом',
            tone: SeeUTone.danger);
      }
    }
  }

  Widget _buildModeSegment(SeeUThemeColors c) {
    final labels = ['История', _postLabel];
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(SeeURadii.pill),
        border: Border.all(color: c.line, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < labels.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                if (i == 0 && _storyTooLong) {
                  showSeeUSnackBar(context,
                      'Для истории видео должно быть не длиннее 1 минуты',
                      tone: SeeUTone.danger,
                      duration: const Duration(seconds: 2));
                  return;
                }
                setState(() {
                  _publishMode = i;
                  // Each tab retains its own pan/zoom and selection.
                  _selectedLayerId = null;
                });
              },
              child: AnimatedContainer(
                duration: SeeUMotion.normal,
                curve: SeeUMotion.smooth,
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  gradient: _publishMode == i
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [SeeUColors.accentSecondary, SeeUColors.accent],
                        )
                      : null,
                  color: _publishMode == i ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(SeeURadii.pill),
                  boxShadow: _publishMode == i
                      ? [
                          BoxShadow(
                            color: SeeUColors.accent.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Opacity(
                  opacity: (i == 0 && _storyTooLong) ? 0.4 : 1.0,
                  child: AnimatedDefaultTextStyle(
                    duration: SeeUMotion.normal,
                    style: SeeUTypography.caption.copyWith(
                      color: _publishMode == i ? Colors.white : c.ink3,
                      fontWeight: _publishMode == i
                          ? FontWeight.w800
                          : FontWeight.w600,
                      fontSize: 13,
                    ),
                    child: Text(labels[i]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }


  // ── Preview ────────────────────────────────────────────────────────────
  //
  // The edit step uses _buildPreviewLarge() inside an Expanded widget.
  // The inner stacks (_buildStoryStack / _buildPostStack) are shared.

  // ── Large preview (fills Expanded, used in edit step) ────────────────────

  Widget _buildPreviewLarge(SeeUThemeColors c) {
    if (_publishMode == 0) {
      final inner = Center(
        child: AspectRatio(
          aspectRatio: 9.0 / 16.0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SeeURadii.medium),
            child: LayoutBuilder(builder: (ctx, box) {
              return _buildStoryStack(c, Size(box.maxWidth, box.maxHeight));
            }),
          ),
        ),
      );
      return widget.heroTag != null
          ? Hero(tag: widget.heroTag!, child: inner)
          : inner;
    }

    // Multi-photo: PageView carousel across all slots
    if (widget.extraFiles.isNotEmpty) {
      final previewAspect = _aspects[_aspectIdx];
      return PageView.builder(
        controller: _carouselCtrl,
        itemCount: 1 + widget.extraFiles.length,
        onPageChanged: (i) {
          HapticFeedback.selectionClick();
          setState(() => _activeSlot = i);
        },
        itemBuilder: (ctx, i) {
          final extraBytes = i > 0 && (i - 1) < widget.extraBytes.length
              ? widget.extraBytes[i - 1]
              : null;
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: AspectRatio(
                aspectRatio: previewAspect,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(SeeURadii.medium),
                  child: i == 0
                      ? LayoutBuilder(builder: (ctx, box) =>
                          _buildPostStack(c, Size(box.maxWidth, box.maxHeight)))
                      : (extraBytes != null
                          ? Image.memory(extraBytes, fit: BoxFit.cover)
                          : FutureBuilder<Uint8List>(
                              future: widget.extraFiles[i - 1].readAsBytes(),
                              builder: (_, snap) => snap.hasData
                                  ? Image.memory(snap.data!, fit: BoxFit.cover)
                                  : const ColoredBox(color: SeeUColors.darkSurface),
                            )),
                ),
              ),
            ),
          );
        },
      );
    }

    // Single post / reel
    final previewAspect = _aspects[_aspectIdx];
    final inner = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: AspectRatio(
          aspectRatio: previewAspect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SeeURadii.medium),
            child: LayoutBuilder(builder: (ctx, box) {
              return _buildPostStack(c, Size(box.maxWidth, box.maxHeight));
            }),
          ),
        ),
      ),
    );
    return widget.heroTag != null
        ? Hero(tag: widget.heroTag!, child: inner)
        : inner;
  }

  // ── Inner story preview stack (reused by large preview + thumbnail) ────────

  Widget _buildStoryStack(SeeUThemeColors c, Size size) {
    return GestureDetector(
      onTap: () => setState(() => _selectedLayerId = null),
      onScaleStart: (d) {
        _showCropGuide();
        _mediaGestureBaseScale  = _mediaScale;
        _mediaGestureBaseOffset = _mediaOffset;
        _mediaGestureFocalStart = d.localFocalPoint;
      },
      onScaleUpdate: (d) => setState(() {
        _cropGuideTimer?.cancel();
        _cropGuideVisible = true;
        _mediaScale  = (_mediaGestureBaseScale * d.scale).clamp(0.2, 5.0);
        _mediaOffset = _mediaGestureBaseOffset +
            (d.localFocalPoint - _mediaGestureFocalStart);
      }),
      onScaleEnd: (_) {
        _cropGuideTimer?.cancel();
        _cropGuideTimer = Timer(const Duration(milliseconds: 1800), () {
          if (mounted) setState(() => _cropGuideVisible = false);
        });
      },
      behavior: HitTestBehavior.translucent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // RepaintBoundary wraps ONLY media + canvas layers.
          // Music pill and badges are outside so they don't get baked into export.
          RepaintBoundary(
            key: _storyCanvasKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: SeeUColors.darkBg),
                Center(
                  child: Transform.translate(
                    offset: _mediaOffset,
                    child: Transform.scale(
                      scale: _mediaScale,
                      child: SizedBox(
                        width: size.width,
                        height: size.height,
                        child: FittedBox(
                          fit: BoxFit.cover,
                          // Enhancement is inside RepaintBoundary → baked into export
                          child: _wrapWithEnhancement(_buildMediaRaw()),
                        ),
                      ),
                    ),
                  ),
                ),
                ..._storyLayers.map((l) => _buildLayerWidget(l, size)),
              ],
            ),
          ),
          // Subtle edge vignette — reinforces publication boundary
          _buildVignetteOverlay(),
          // Crop frame + composition guides
          _buildCropGuideOverlay(),
          // Decorative overlays — OUTSIDE RepaintBoundary
          if (_selectedTrack != null)
            Positioned(
              bottom: 10,
              left: 10,
              child: _buildMusicPillWidget(),
            ),
          // Duration badge (top-left)
          Positioned(
            top: 8,
            left: 8,
            child: _buildDurationBadge(),
          ),
          // Poll overlay preview
          if (_pendingPoll != null)
            Positioned(
              left: 16,
              right: 16,
              top: size.height * 0.38,
              child: _buildPollPreviewWidget(_pendingPoll!),
            ),
          // Pinch-to-crop hint — shown once per screen open
          _buildCropHint(),
        ],
      ),
    );
  }

  Widget _buildDurationBadge() {
    // Photos don't have a meaningful duration — don't show the badge
    if (!widget.isVideo) return const SizedBox.shrink();
    final tooLong = _storyTooLong;
    final dur = _videoReady ? _videoDurationSec : 0.0;
    if (dur == 0.0) return const SizedBox.shrink();
    final label = tooLong
        ? '${dur.round()}с · слишком длинное'
        : '${dur.clamp(0.0, kStoryMaxVideoSeconds.toDouble()).round()}с';
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tooLong)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(PhosphorIconsFill.warning, color: Colors.white, size: 10),
          )
        else
          Container(
            width: 5, height: 5,
            margin: const EdgeInsets.only(right: 4),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        Text(label,
            style: const TextStyle(
                color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
      ],
    );
    if (tooLong) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: SeeUColors.error.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(SeeURadii.pill),
        ),
        child: content,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(SeeURadii.pill),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          child: content,
        ),
      ),
    );
  }

  Widget _buildPollPreviewWidget(StoryPoll poll) {
    return GestureDetector(
      onTap: _addOrEditPoll,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(PhosphorIconsFill.chartBar,
                    color: SeeUColors.accent, size: 14),
                const SizedBox(width: 5),
                Text('Опрос',
                    style: SeeUTypography.micro.copyWith(
                        color: SeeUColors.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
                const Spacer(),
                Icon(PhosphorIconsRegular.pencil,
                    color: Colors.white.withValues(alpha: 0.7), size: 14),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              poll.question,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            _PollOptionBar(label: poll.optionA, percent: 50, accent: true),
            const SizedBox(height: 6),
            _PollOptionBar(label: poll.optionB, percent: 50, accent: false),
          ],
        ),
      ),
    );
  }

  // ── Inner post preview stack (reused by large preview + thumbnail) ─────────

  Widget _buildPostStack(SeeUThemeColors c, Size size) {
    return GestureDetector(
      onTap: () => setState(() => _selectedLayerId = null),
      onScaleStart: (d) {
        _showCropGuide();
        _mediaGestureBaseScale  = _mediaScale;
        _mediaGestureBaseOffset = _mediaOffset;
        _mediaGestureFocalStart = d.localFocalPoint;
      },
      onScaleUpdate: (d) => setState(() {
        _cropGuideTimer?.cancel();
        _cropGuideVisible = true;
        _mediaScale  = (_mediaGestureBaseScale * d.scale).clamp(0.2, 5.0);
        _mediaOffset = _mediaGestureBaseOffset +
            (d.localFocalPoint - _mediaGestureFocalStart);
      }),
      onScaleEnd: (_) {
        _cropGuideTimer?.cancel();
        _cropGuideTimer = Timer(const Duration(milliseconds: 1800), () {
          if (mounted) setState(() => _cropGuideVisible = false);
        });
      },
      behavior: HitTestBehavior.translucent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // RepaintBoundary wraps media + post layers for compositing.
          RepaintBoundary(
            key: _postCanvasKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: SeeUColors.darkBg),
                Center(
                  child: Transform.translate(
                    offset: _mediaOffset,
                    child: Transform.scale(
                      scale: _mediaScale,
                      child: SizedBox(
                        width: size.width,
                        height: size.height,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          // Enhancement inside RepaintBoundary → baked into export
                          child: _wrapWithEnhancement(_buildMediaRaw()),
                        ),
                      ),
                    ),
                  ),
                ),
                ..._postLayers.map((l) => _buildLayerWidget(l, size)),
              ],
            ),
          ),
          // Subtle edge vignette + crop frame guides
          _buildVignetteOverlay(),
          _buildCropGuideOverlay(),
          if (_selectedTrack != null)
            Positioned(
              bottom: 10,
              left: 10,
              child: _buildMusicPillWidget(),
            ),
          // Pinch-to-crop hint
          _buildCropHint(),
        ],
      ),
    );
  }

  // Raw media widget — used inside a FittedBox for scaling.
  Widget _buildMediaRaw() {
    if (widget.isVideo) {
      if (!_videoReady || _videoCtrl == null) {
        return const SizedBox(
          width: 200,
          height: 300,
          child: ColoredBox(
            color: Colors.black,
            child: Center(child: BrandedLoader()),
          ),
        );
      }
      final vSize = _videoCtrl!.value.size;
      return GestureDetector(
        onTap: () {
          if (_videoCtrl == null || !_videoReady) return;
          setState(() {
            _videoCtrl!.value.isPlaying
                ? _videoCtrl!.pause()
                : _videoCtrl!.play();
          });
        },
        child: Stack(
          children: [
            SizedBox(
              width: vSize.width,
              height: vSize.height,
              child: VideoPlayer(_videoCtrl!),
            ),
            if (!_videoCtrl!.value.isPlaying)
              Positioned.fill(
                child: Center(
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.14),
                              Colors.black.withValues(alpha: 0.28),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                            width: 0.8,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(PhosphorIconsFill.play,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    // Photo
    if (_bytes != null) {
      return Image.memory(_bytes!, fit: BoxFit.contain);
    }
    return const SizedBox(
      width: 200,
      height: 300,
      child: ColoredBox(color: Colors.black),
    );
  }

  Widget _buildMusicPillWidget() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(SeeURadii.pill),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.30),
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            border: Border.all(
              color: SeeUColors.accent.withValues(alpha: 0.55),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(PhosphorIconsFill.musicNote,
                  color: SeeUColors.accent, size: 11),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  '${_selectedTrack!.title} · ${_selectedTrack!.artist}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Canvas editor tools ─────────────────────────────────────────────────

  void _addStoryText() {
    _saveUndo();
    setState(() {
      _editingLayerId = null;
      _editTextColor  = Colors.white;
      _editBgStyle    = _BgStyle.none;
      _editBgColor    = Colors.black;
      _editFontSize   = 24.0;
      _editAlign      = _TextAlign2.center;
      _stTextCtrl.clear();
      _isEditingText  = true;
    });
    Future.delayed(const Duration(milliseconds: 80),
        () => _stTextFocus.requestFocus());
  }

  void _startEditText(_CanvasLayer layer) {
    setState(() {
      _editingLayerId = layer.id;
      _editTextColor = layer.textColor;
      _editBgStyle = layer.bgStyle;
      _editBgColor = layer.bgColor;
      _editFontSize = layer.fontSize;
      _editAlign = layer.align;
      _stTextCtrl.text = layer.text;
      _isEditingText = true;
      _selectedLayerId = null;
    });
    Future.delayed(const Duration(milliseconds: 80),
        () => _stTextFocus.requestFocus());
  }

  void _commitEditText() {
    final text = _stTextCtrl.text.trim();
    _stTextFocus.unfocus();
    if (text.isEmpty) {
      setState(() => _isEditingText = false);
      return;
    }
    _saveUndo();
    setState(() {
      _isEditingText = false;
      if (_editingLayerId == null) {
        // new layer
        final newId = _stNextId++;
        _layers.add(_CanvasLayer(
          id: newId,
          kind: _LayerKind.text,
          text: text,
          textColor: _editTextColor,
          bgStyle: _editBgStyle,
          bgColor: _editBgColor,
          fontSize: _editFontSize,
          align: _editAlign,
          position: const Offset(0.5, 0.5),
        ));
        _lastAddedLayerId = newId;
      } else {
        // update existing
        final idx = _layers.indexWhere((l) => l.id == _editingLayerId);
        if (idx >= 0) {
          _layers[idx]
            ..text = text
            ..textColor = _editTextColor
            ..bgStyle = _editBgStyle
            ..bgColor = _editBgColor
            ..fontSize = _editFontSize
            ..align = _editAlign;
        }
      }
    });
  }

  // ── Undo ─────────────────────────────────────────────────────────────────

  void _saveUndo() {
    if (_publishMode == 0) {
      _storyUndo = _storyLayers.map((l) => l.copy()).toList();
    } else {
      _postUndo = _postLayers.map((l) => l.copy()).toList();
    }
  }

  void _undo() {
    HapticFeedback.mediumImpact();
    if (_publishMode == 0 && _storyUndo != null) {
      setState(() {
        _storyLayers
          ..clear()
          ..addAll(_storyUndo!);
        _storyUndo = null;
      });
    } else if (_publishMode == 1 && _postUndo != null) {
      setState(() {
        _postLayers
          ..clear()
          ..addAll(_postUndo!);
        _postUndo = null;
      });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────

  void _deleteLayer(int id) {
    _saveUndo();
    HapticFeedback.mediumImpact();
    setState(() {
      _layers.removeWhere((l) => l.id == id);
      if (_selectedLayerId == id) _selectedLayerId = null;
    });
  }

  void _addStorySticker() {
    const categories = {
      'Смайлы': ['😀', '😂', '😍', '🥰', '😎', '🤩', '😴', '🤯', '🥳', '😭', '😤', '🫶'],
      'Активность': ['🔥', '❤️', '⭐', '🎉', '✨', '💫', '💥', '🌈', '🎵', '🎶', '👑', '💎'],
      'Природа': ['🌸', '🌺', '🦋', '🌙', '☀️', '⚡', '🌊', '🍀', '🌴', '🦄', '🐉', '🌸'],
      'Жесты': ['👍', '👎', '🙌', '🤝', '✌️', '🫵', '💪', '👏', '🙏', '🤙', '☝️', '🫂'],
    };

    showSeeUBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final c = ctx.seeuColors;
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.5,
          child: Column(
            children: [
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('ОФОРМЛЕНИЕ',
                              style: SeeUTypography.kicker
                                  .copyWith(color: SeeUColors.accent)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Стикеры',
                        style:
                            SeeUTypography.displayS.copyWith(color: c.ink)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DefaultTabController(
                  length: categories.length,
                  child: Column(
                    children: [
                      TabBar(
                        isScrollable: true,
                        labelColor: SeeUColors.accent,
                        unselectedLabelColor: c.ink3,
                        indicatorColor: SeeUColors.accent,
                        labelStyle: SeeUTypography.caption.copyWith(
                            fontWeight: FontWeight.w700, fontSize: 12),
                        tabs: categories.keys
                            .map((k) => Tab(text: k))
                            .toList(),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: categories.values.map((emojis) {
                            return GridView.count(
                              padding: const EdgeInsets.all(16),
                              crossAxisCount: 6,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              children: emojis.map((emoji) {
                                return GestureDetector(
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    HapticFeedback.selectionClick();
                                    _saveUndo();
                                    // Slight random offset so multiple stickers
                                    // don't pile up in the same spot.
                                    final rng = DateTime.now().millisecondsSinceEpoch;
                                    final dx = 0.35 + (rng % 31) / 100.0;
                                    final dy = 0.30 + (rng % 41) / 100.0;
                                    final newId = _stNextId++;
                                    setState(() {
                                      _layers.add(_CanvasLayer(
                                        id: newId,
                                        kind: _LayerKind.sticker,
                                        emoji: emoji,
                                        position: Offset(dx, dy),
                                      ));
                                      _lastAddedLayerId = newId;
                                    });
                                  },
                                  child: Center(
                                    child: Text(emoji,
                                        style:
                                            const TextStyle(fontSize: 32)),
                                  ),
                                );
                              }).toList(),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Layer widget ─────────────────────────────────────────────────────────

  Widget _buildLayerWidget(_CanvasLayer layer, Size canvasSize) {
    final isSelected = _selectedLayerId == layer.id;
    final cx = layer.position.dx * canvasSize.width;
    final cy = layer.position.dy * canvasSize.height;

    Widget content;
    switch (layer.kind) {
      case _LayerKind.text:
        content = _buildTextLayerContent(layer);
      case _LayerKind.sticker:
        content = Text(layer.emoji,
            style: TextStyle(fontSize: 40 * layer.scale, height: 1));
      case _LayerKind.location:
        content = _buildLocationLayerContent(layer);
      case _LayerKind.link:
        content = _buildLinkLayerContent(layer);
    }

    if (isSelected) {
      content = Container(
        decoration: BoxDecoration(
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.7), width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.all(2),
        child: content,
      );
    }

    final layerWidget = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedLayerId = isSelected ? null : layer.id);
      },
      onDoubleTap: () {
        // Each kind has a meaningful double-tap action:
        //  text     → re-open editor
        //  location → edit name
        //  link     → edit text + URL
        //  sticker  → delete (quick removal)
        switch (layer.kind) {
          case _LayerKind.text:
            _startEditText(layer);
          case _LayerKind.location:
            _editLayerLocation(layer);
          case _LayerKind.link:
            _editLayerLink(layer);
          case _LayerKind.sticker:
            _deleteLayer(layer.id);
        }
      },
      onScaleStart: (d) {
        _layerGestureBaseScale    = layer.scale;
        _layerGestureBaseRotation = layer.rotation;
      },
      onScaleUpdate: (d) => setState(() {
        layer.scale    = (_layerGestureBaseScale * d.scale).clamp(0.3, 5.0);
        layer.rotation = _layerGestureBaseRotation + d.rotation;
        layer.position = Offset(
          (layer.position.dx +
                  d.focalPointDelta.dx / canvasSize.width)
              .clamp(0.05, 0.95),
          (layer.position.dy +
                  d.focalPointDelta.dy / canvasSize.height)
              .clamp(0.05, 0.95),
        );
      }),
      child: Transform.rotate(
        angle: layer.rotation,
        child: layer.kind == _LayerKind.sticker
            ? content
            : Transform.scale(scale: layer.scale, child: content),
      ),
    );

    // Clamp control buttons so they don't get clipped by the canvas edge.
    // Near the left edge → shift × to the right; near the top → shift down.
    final btnOffsetX = cx < 20 ? 0.0 : -14.0;
    final btnOffsetY = cy < 20 ? 0.0 : -14.0;

    // Edit button icon depends on layer type.
    final editIcon = layer.kind == _LayerKind.location
        ? PhosphorIconsBold.pencilSimple
        : layer.kind == _LayerKind.link
            ? PhosphorIconsBold.pencilSimple
            : PhosphorIconsBold.pencil;
    final bool hasEditBtn =
        layer.kind == _LayerKind.text ||
        layer.kind == _LayerKind.location ||
        layer.kind == _LayerKind.link;

    final isNew = _lastAddedLayerId == layer.id;
    return Positioned(
      left: cx,
      top: cy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Pop-in animation for newly added layers
            isNew
                ? TweenAnimationBuilder<double>(
                    key: ValueKey('pop_${layer.id}'),
                    tween: Tween(begin: 0.55, end: 1.0),
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutBack,
                    onEnd: () {
                      if (_lastAddedLayerId == layer.id) {
                        setState(() => _lastAddedLayerId = null);
                      }
                    },
                    builder: (_, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: layerWidget,
                  )
                : layerWidget,
            if (isSelected)
              Positioned(
                top: btnOffsetY,
                left: btnOffsetX,
                child: GestureDetector(
                  onTap: () => _deleteLayer(layer.id),
                  child: Container(
                    width: 28, height: 28,
                    decoration: const BoxDecoration(
                        color: SeeUColors.danger, shape: BoxShape.circle),
                    child: const Icon(PhosphorIconsBold.x,
                        color: Colors.white, size: 13),
                  ),
                ),
              ),
            if (isSelected && hasEditBtn)
              Positioned(
                top: btnOffsetY,
                right: -14,
                child: GestureDetector(
                  onTap: () {
                    switch (layer.kind) {
                      case _LayerKind.text:
                        _startEditText(layer);
                      case _LayerKind.location:
                        _editLayerLocation(layer);
                      case _LayerKind.link:
                        _editLayerLink(layer);
                      default:
                        break;
                    }
                  },
                  child: Container(
                    width: 28, height: 28,
                    decoration: const BoxDecoration(
                        color: SeeUColors.accent, shape: BoxShape.circle),
                    child: Icon(editIcon, color: Colors.white, size: 13),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Edit existing location sticker name.
  Future<void> _editLayerLocation(_CanvasLayer layer) async {
    final ctrl = TextEditingController(text: layer.locationName);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _SimpleInputDialog(
        title: 'Геометка',
        hint: 'Название места',
        ctrl: ctrl,
        icon: PhosphorIconsFill.mapPin,
        iconColor: SeeUColors.accent,
      ),
    );
    ctrl.dispose();
    if (result == null || result.trim().isEmpty) return;
    _saveUndo();
    setState(() => layer.locationName = result.trim());
  }

  // Edit existing link sticker text + URL.
  Future<void> _editLayerLink(_CanvasLayer layer) async {
    final textCtrl = TextEditingController(text: layer.linkText);
    final urlCtrl  = TextEditingController(text: layer.linkUrl);
    final c = context.seeuColors;
    final result = await showDialog<({String text, String url})>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(PhosphorIconsRegular.link,
                color: SeeUColors.accent, size: 20),
            const SizedBox(width: 8),
            Text('Изменить ссылку',
                style: SeeUTypography.body
                    .copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: textCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Текст ссылки',
                hintStyle: SeeUTypography.body.copyWith(color: c.ink3),
                filled: true,
                fillColor: c.surface2,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: urlCtrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'https://...',
                hintStyle: SeeUTypography.body.copyWith(color: c.ink3),
                filled: true,
                fillColor: c.surface2,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: c.ink3)),
          ),
          TextButton(
            onPressed: () {
              var url = urlCtrl.text.trim();
              if (url.isEmpty) return;
              if (!url.startsWith('http://') &&
                  !url.startsWith('https://')) {
                url = 'https://$url';
              }
              Navigator.pop(ctx, (text: textCtrl.text.trim(), url: url));
            },
            child: Text('Сохранить',
                style: TextStyle(
                    color: SeeUColors.accent,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    textCtrl.dispose();
    urlCtrl.dispose();
    if (result == null) return;
    _saveUndo();
    setState(() {
      layer.linkText = result.text;
      layer.linkUrl  = result.url;
    });
  }

  Widget _buildTextLayerContent(_CanvasLayer layer) {
    Widget text = Text(
      layer.text,
      textAlign: layer.align == _TextAlign2.left
          ? TextAlign.left
          : layer.align == _TextAlign2.right
              ? TextAlign.right
              : TextAlign.center,
      style: TextStyle(
        color: layer.textColor,
        fontSize: layer.fontSize,
        fontWeight: FontWeight.w700,
        height: 1.2,
        shadows: layer.bgStyle == _BgStyle.none
            ? const [Shadow(color: Colors.black54, blurRadius: 8)]
            : null,
      ),
    );

    switch (layer.bgStyle) {
      case _BgStyle.solid:
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: layer.bgColor.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
          ),
          child: text,
        );
      case _BgStyle.blur:
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              color: Colors.black.withValues(alpha: 0.25),
              child: text,
            ),
          ),
        );
      case _BgStyle.none:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: text,
        );
    }
  }

  // ── Location layer widget ────────────────────────────────────────────────

  Widget _buildLocationLayerContent(_CanvasLayer layer) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(SeeURadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsFill.mapPin,
              color: SeeUColors.accent, size: 14),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              layer.locationName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  // ── Link layer widget ─────────────────────────────────────────────────────

  Widget _buildLinkLayerContent(_CanvasLayer layer) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.tryParse(layer.linkUrl);
        if (uri != null && await canLaunchUrl(uri)) launchUrl(uri);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: SeeUColors.accent.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(PhosphorIconsRegular.link, color: Colors.white, size: 13),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                layer.linkText.isNotEmpty ? layer.linkText : layer.linkUrl,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white70,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Story — add location sticker ─────────────────────────────────────────

  Future<void> _addStoryLocation() async {
    // Show GPS loading indicator while detecting location.
    setState(() => _gpsLoading = true);
    String? detected;
    try {
      final svc = await Geolocator.isLocationServiceEnabled();
      if (svc) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) {
          if (mounted) {
            showSeeUSnackBar(context, 'Нет доступа к геолокации',
                tone: SeeUTone.danger);
          }
        } else {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 8),
            ),
          );
          detected = _nearestCity(pos.latitude, pos.longitude);
        }
      } else {
        if (mounted) {
          showSeeUSnackBar(context, 'Геолокация отключена в настройках',
              tone: SeeUTone.danger);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _gpsLoading = false);
    if (!mounted) return;

    final ctrl = TextEditingController(text: detected ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _SimpleInputDialog(
        title: 'Геометка',
        hint: 'Название места',
        ctrl: ctrl,
        icon: PhosphorIconsFill.mapPin,
        iconColor: SeeUColors.accent,
      ),
    );
    ctrl.dispose();
    if (result == null || result.trim().isEmpty) return;
    _saveUndo();
    setState(() {
      _layers.add(_CanvasLayer(
        id: _stNextId++,
        kind: _LayerKind.location,
        locationName: result.trim(),
        position: const Offset(0.5, 0.12),
      ));
    });
  }

  /// Returns the nearest Kazakh city name to the given coordinates.
  String _nearestCity(double lat, double lng) {
    String best = 'Алматы';
    double bestDist = double.infinity;
    for (final c in kKazakhstanCities) {
      final dlat = c.lat - lat;
      final dlng = c.lng - lng;
      final d = sqrt(dlat * dlat + dlng * dlng);
      if (d < bestDist) {
        bestDist = d;
        best = c.name;
      }
    }
    return best;
  }

  // ── Crop guide helpers ───────────────────────────────────────────────────

  void _showCropGuide() {
    _cropGuideTimer?.cancel();
    if (!_cropGuideVisible) setState(() => _cropGuideVisible = true);
    _cropGuideTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _cropGuideVisible = false);
    });
  }

  Widget _buildVignetteOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.2,
              colors: [
                Colors.transparent,
                Colors.transparent,
                Colors.black.withValues(alpha: 0.16),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCropGuideOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Corner markers — always faintly visible (15%), bright during gesture
            AnimatedOpacity(
              duration: const Duration(milliseconds: 400),
              opacity: _cropGuideVisible ? 1.0 : 0.15,
              child: CustomPaint(painter: const _CropCornersPainter()),
            ),
            // Rule-of-thirds + crosshair — only during active gesture
            AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _cropGuideVisible ? 1.0 : 0.0,
              child: CustomPaint(painter: const _CropGuidesPainter()),
            ),
          ],
        ),
      ),
    );
  }

  // Pinch-to-crop one-time hint — appears for 2.5s on screen open
  Widget _buildCropHint() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      bottom: _cropHintVisible ? 48 : 28,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 350),
          opacity: _cropHintVisible ? 1.0 : 0.0,
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SeeURadii.pill),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 0.5,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsRegular.arrowsOut,
                          color: Colors.white70, size: 13),
                      SizedBox(width: 6),
                      Text(
                        'Зажмите двумя пальцами для кадрирования',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Story — add link sticker ──────────────────────────────────────────────

  Future<void> _addStoryLink() async {
    final textCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final result = await showDialog<({String text, String url})>(
      context: context,
      builder: (ctx) {
        final c = ctx.seeuColors;
        return AlertDialog(
          backgroundColor: c.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(PhosphorIconsRegular.link,
                  color: Color(0xFF0A84FF), size: 20),
              const SizedBox(width: 8),
              Text('Ссылка', style: SeeUTypography.body.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Текст ссылки',
                  hintStyle: SeeUTypography.body.copyWith(color: c.ink3),
                  filled: true,
                  fillColor: c.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlCtrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: 'https://...',
                  hintStyle: SeeUTypography.body.copyWith(color: c.ink3),
                  filled: true,
                  fillColor: c.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Отмена', style: TextStyle(color: c.ink3)),
            ),
            TextButton(
              onPressed: () {
                var url = urlCtrl.text.trim();
                if (url.isEmpty) return;
                // Auto-add scheme if missing.
                if (!url.startsWith('http://') && !url.startsWith('https://')) {
                  url = 'https://$url';
                }
                final uri = Uri.tryParse(url);
                if (uri == null || !uri.hasAuthority) {
                  showSeeUSnackBar(ctx, 'Введите корректный адрес ссылки',
                      tone: SeeUTone.danger);
                  return;
                }
                Navigator.pop(ctx, (text: textCtrl.text.trim(), url: url));
              },
              child: Text('Добавить',
                  style: TextStyle(
                      color: SeeUColors.accent, fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
    textCtrl.dispose();
    urlCtrl.dispose();
    if (result == null) return;
    _saveUndo();
    setState(() {
      _layers.add(_CanvasLayer(
        id: _stNextId++,
        kind: _LayerKind.link,
        linkText: result.text,
        linkUrl: result.url,
        position: const Offset(0.5, 0.88),
      ));
    });
  }

  // ── Auto-fill GPS location for post form ─────────────────────────────────

  Future<void> _fillGpsLocation() async {
    HapticFeedback.lightImpact();
    setState(() => _gpsLoading = true);
    try {
      final svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) {
        if (mounted) {
          showSeeUSnackBar(context, 'Геолокация отключена в настройках устройства',
              tone: SeeUTone.danger);
        }
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          showSeeUSnackBar(context, 'Нет разрешения на использование геолокации',
              tone: SeeUTone.danger);
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (mounted) {
        _locationCtrl.text = _nearestCity(pos.latitude, pos.longitude);
      }
    } catch (_) {
      if (mounted) {
        showSeeUSnackBar(context, 'Не удалось определить местоположение',
            tone: SeeUTone.danger);
      }
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  // ── Poll ─────────────────────────────────────────────────────────────────

  Future<void> _addOrEditPoll() async {
    // Returns StoryPoll (save/update), 'delete' string (remove), or null (dismiss).
    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PollCreatorSheet(initial: _pendingPoll),
    );
    if (result == 'delete') {
      setState(() => _pendingPoll = null);
    } else if (result is StoryPoll) {
      setState(() => _pendingPoll = result);
    }
  }

  // ── Text editor overlay (full canvas) ───────────────────────────────────

  static const _kTextColors = [
    Colors.white,
    Colors.black,
    SeeUColors.accent,
    Color(0xFFFFD60A), // yellow
    Color(0xFF30D158), // green
    Color(0xFF0A84FF), // blue
    Color(0xFFFF453A), // red
    Color(0xFFBF5AF2), // purple
  ];

  static const _kBgColors = [
    Colors.black,
    Colors.white,
    SeeUColors.accent,
    Color(0xFFFFD60A),
    Color(0xFF30D158),
    Color(0xFF0A84FF),
    Color(0xFFFF453A),
    Color(0xFFBF5AF2),
  ];

  // Full-screen text editor — replaces the old in-canvas overlay.
  // Sits at Scaffold level (Stack child) so it:
  //   • fills the entire screen (not just the story canvas)
  //   • controls its own keyboard padding via viewInsets
  //   • hides the Publish button automatically (parent checks _isEditingText)
  Widget _buildFullScreenTextEditor(SeeUThemeColors c) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final topPad = MediaQuery.of(context).padding.top;

    final textAlign = _editAlign == _TextAlign2.left
        ? TextAlign.left
        : _editAlign == _TextAlign2.right
            ? TextAlign.right
            : TextAlign.center;

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Background — tapping empty space commits/closes the editor.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _commitEditText,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.82),
                ),
              ),
            ),

            // All editor controls in a Column that pushes up with the keyboard.
            Column(
              children: [
                SizedBox(height: topPad + 8),

                // ── Color swatches ──
                GestureDetector(
                  onTap: () {}, // prevent dismiss propagation
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _kTextColors.map((color) {
                        final isSelected =
                            _editTextColor.toARGB32() == color.toARGB32();
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _editTextColor = color);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: isSelected ? 30 : 26,
                            height: isSelected ? 30 : 26,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.3),
                                width: isSelected ? 2.5 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                          color: color.withValues(alpha: 0.5),
                                          blurRadius: 8)
                                    ]
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // ── Bg style selector ──
                GestureDetector(
                  onTap: () {},
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _BgStyleBtn(
                          label: 'Без фона',
                          icon: PhosphorIconsRegular.textT,
                          selected: _editBgStyle == _BgStyle.none,
                          onTap: () =>
                              setState(() => _editBgStyle = _BgStyle.none),
                        ),
                        const SizedBox(width: 8),
                        _BgStyleBtn(
                          label: 'Размытие',
                          icon: PhosphorIconsRegular.drop,
                          selected: _editBgStyle == _BgStyle.blur,
                          onTap: () =>
                              setState(() => _editBgStyle = _BgStyle.blur),
                        ),
                        const SizedBox(width: 8),
                        _BgStyleBtn(
                          label: 'Заливка',
                          icon: PhosphorIconsRegular.paintBucket,
                          selected: _editBgStyle == _BgStyle.solid,
                          onTap: () =>
                              setState(() => _editBgStyle = _BgStyle.solid),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Bg color swatches (visible only when Solid is selected) ──
                if (_editBgStyle == _BgStyle.solid)
                  GestureDetector(
                    onTap: () {},
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: _kBgColors.map((color) {
                          final sel =
                              _editBgColor.toARGB32() == color.toARGB32();
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _editBgColor = color);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: sel ? 28 : 24,
                              height: sel ? 28 : 24,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: sel
                                      ? Colors.white
                                      : Colors.white
                                          .withValues(alpha: 0.3),
                                  width: sel ? 2.5 : 1,
                                ),
                                boxShadow: sel
                                    ? [
                                        BoxShadow(
                                            color:
                                                color.withValues(alpha: 0.5),
                                            blurRadius: 8)
                                      ]
                                    : null,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                // ── Text field — takes remaining space above keyboard ──
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: _stTextCtrl,
                        focusNode: _stTextFocus,
                        autofocus: true,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        style: TextStyle(
                          color: _editTextColor,
                          fontSize: _editFontSize,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          shadows: _editBgStyle == _BgStyle.none
                              ? const [
                                  Shadow(color: Colors.black54, blurRadius: 8)
                                ]
                              : null,
                        ),
                        textAlign: textAlign,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Введите текст...',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: _editFontSize,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Font size slider ──
                GestureDetector(
                  onTap: () {},
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(PhosphorIconsRegular.textT,
                            color: Colors.white54, size: 14),
                        Expanded(
                          child: Slider(
                            value: _editFontSize,
                            min: 14,
                            max: 72,
                            activeColor: SeeUColors.accent,
                            inactiveColor:
                                Colors.white.withValues(alpha: 0.25),
                            onChanged: (v) =>
                                setState(() => _editFontSize = v),
                          ),
                        ),
                        const Icon(PhosphorIconsBold.textT,
                            color: Colors.white70, size: 22),
                      ],
                    ),
                  ),
                ),

                // ── Alignment + confirm — sits just above the keyboard ──
                GestureDetector(
                  onTap: () {},
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, bottom > 0 ? 8 : 28),
                    child: Row(
                      children: [
                        _AlignBtn(
                          icon: PhosphorIconsRegular.textAlignLeft,
                          selected: _editAlign == _TextAlign2.left,
                          onTap: () =>
                              setState(() => _editAlign = _TextAlign2.left),
                        ),
                        const SizedBox(width: 8),
                        _AlignBtn(
                          icon: PhosphorIconsRegular.textAlignCenter,
                          selected: _editAlign == _TextAlign2.center,
                          onTap: () =>
                              setState(() => _editAlign = _TextAlign2.center),
                        ),
                        const SizedBox(width: 8),
                        _AlignBtn(
                          icon: PhosphorIconsRegular.textAlignRight,
                          selected: _editAlign == _TextAlign2.right,
                          onTap: () =>
                              setState(() => _editAlign = _TextAlign2.right),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: _commitEditText,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              color: SeeUColors.accent,
                              borderRadius:
                                  BorderRadius.circular(SeeURadii.pill),
                            ),
                            child: const Text(
                              'Готово',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Keyboard height spacer — controls sit above keyboard.
                SizedBox(height: bottom),
              ],
            ),
          ],
        ),
      ),
    );
  }


  // ── Action row (Формат | Музыка | Обрезать) ────────────────────────────

  Widget _buildActionRow(SeeUThemeColors c) {
    if (_publishMode == 0) return _buildStoryActionRow(c);
    return _buildPostActionRow(c);
  }

  Widget _buildStoryActionRow(SeeUThemeColors c) {
    return Stack(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // Extra right padding so last chip peeks before the fade gradient
          padding: const EdgeInsets.fromLTRB(16, 10, 48, 4),
          child: Row(
            children: [
              // Canvas tools first (most used) — photo only
              if (!widget.isVideo) ...[
                _ActionChip(
                  icon: PhosphorIconsRegular.textT,
                  label: 'Текст',
                  color: _storyLayers.any((l) => l.kind == _LayerKind.text)
                      ? SeeUColors.accent
                      : c.ink2,
                  onTap: _addStoryText,
                ),
                const SizedBox(width: 8),
                _ActionChip(
                  icon: PhosphorIconsRegular.smiley,
                  label: 'Стикер',
                  color: c.ink2,
                  onTap: _addStorySticker,
                ),
                const SizedBox(width: 8),
              ],
              // Music
              _ActionChip(
                icon: _selectedTrack != null
                    ? PhosphorIconsFill.musicNote
                    : PhosphorIconsRegular.musicNote,
                label: _selectedTrack != null ? _selectedTrack!.title : 'Музыка',
                color: _selectedTrack != null ? SeeUColors.accent : c.ink2,
                maxLabelWidth: 90,
                onTap: _openMusicPicker,
              ),
              // Poll
              const SizedBox(width: 8),
              _ActionChip(
                icon: _pendingPoll != null
                    ? PhosphorIconsFill.chartBar
                    : PhosphorIconsRegular.chartBar,
                label: 'Опрос',
                color: _pendingPoll != null ? SeeUColors.accent : c.ink2,
                onTap: _addOrEditPoll,
              ),
              // Geo and link — secondary, placed later
              const SizedBox(width: 8),
              _gpsLoading
                  ? _SpinningGeoChip(color: c.ink2)
                  : _ActionChip(
                      icon: PhosphorIconsFill.mapPin,
                      label: 'Геотег',
                      color: _storyLayers.any((l) => l.kind == _LayerKind.location)
                          ? SeeUColors.accent
                          : c.ink2,
                      onTap: _addStoryLocation,
                    ),
              const SizedBox(width: 8),
              _ActionChip(
                icon: PhosphorIconsRegular.link,
                label: 'Ссылка',
                color: _storyLayers.any((l) => l.kind == _LayerKind.link)
                    ? SeeUColors.accent
                    : c.ink2,
                onTap: _addStoryLink,
              ),
            ],
          ),
        ),
        // Right fade — signals the row is scrollable
        Positioned(
          right: 0, top: 0, bottom: 0,
          child: IgnorePointer(
            child: Container(
              width: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [c.bg.withValues(alpha: 0), c.bg],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPostActionRow(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Row 1: Format (always fully visible, no scroll) ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              for (int i = 0; i < _aspectLabels.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _FormatChip(
                  label: _aspectLabels[i],
                  selected: _aspectIdx == i,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _aspectIdx = i);
                  },
                ),
              ],
            ],
          ),
        ),
        // ── Row 2: Tools (scrollable) ──
        Stack(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 48, 4),
              child: Row(
                children: [
                  // Canvas tools (photo only)
                  if (!widget.isVideo) ...[
                    _ActionChip(
                      icon: PhosphorIconsRegular.textT,
                      label: 'Текст',
                      color: _postLayers.any((l) => l.kind == _LayerKind.text)
                          ? SeeUColors.accent
                          : c.ink2,
                      onTap: _addStoryText,
                    ),
                    const SizedBox(width: 8),
                    _ActionChip(
                      icon: PhosphorIconsRegular.smiley,
                      label: 'Стикер',
                      color: c.ink2,
                      onTap: _addStorySticker,
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Music
                  _ActionChip(
                    icon: _selectedTrack != null
                        ? PhosphorIconsFill.musicNote
                        : PhosphorIconsRegular.musicNote,
                    label: _selectedTrack != null ? _selectedTrack!.title : 'Музыка',
                    color: _selectedTrack != null ? SeeUColors.accent : c.ink2,
                    maxLabelWidth: 80,
                    onTap: _openMusicPicker,
                  ),
                  // Trim (video only) — shows trimmed duration when applied
                  if (widget.isVideo) ...[
                    const SizedBox(width: 8),
                    _ActionChip(
                      icon: PhosphorIconsRegular.scissors,
                      label: _trimmedDurationSec > 0
                          ? '${_trimmedDurationSec.round()}с'
                          : 'Обрезать',
                      color: _trimmedDurationSec > 0 ? SeeUColors.accent : c.ink2,
                      onTap: _videoReady ? _openVideoTrim : null,
                    ),
                    const SizedBox(width: 8),
                    // Cover frame picker chip
                    _ActionChip(
                      icon: _coverFrameSec != null
                          ? PhosphorIconsFill.images
                          : PhosphorIconsRegular.images,
                      label: 'Обложка',
                      color: _coverPickerVisible || _coverFrameSec != null
                          ? SeeUColors.accent
                          : c.ink2,
                      onTap: _videoReady
                          ? () async {
                              HapticFeedback.selectionClick();
                              if (!_coverPickerVisible &&
                                  _coverFrameThumbs.isEmpty) {
                                await _generateCoverFrameThumbs();
                              }
                              setState(() =>
                                  _coverPickerVisible = !_coverPickerVisible);
                            }
                          : null,
                    ),
                  ],
                ],
              ),
            ),
            // Right fade — signals scrollability
            Positioned(
              right: 0, top: 0, bottom: 0,
              child: IgnorePointer(
                child: Container(
                  width: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [c.bg.withValues(alpha: 0), c.bg],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Music trim card (compact, shown when track selected) ───────────────

  Widget _buildMusicTrimCard(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          border: Border.all(
            color: SeeUColors.accent.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: SeeUColors.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(PhosphorIconsFill.musicNote,
                      color: SeeUColors.accent, size: 15),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedTrack!.title,
                        style: SeeUTypography.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _selectedTrack!.artist,
                        style: SeeUTypography.micro.copyWith(color: c.ink3),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() {
                    _selectedTrack = null;
                    _audioStartSec = 0;
                  }),
                  child: Icon(PhosphorIcons.x(), size: 16, color: c.ink3),
                ),
              ],
            ),
            if ((_selectedTrack?.durationSeconds ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _buildMusicTrimmer(),
              ),
            // Video + music → choice to drop the original audio.
            // #84: custom pill toggle matching the app's chip language.
            if (widget.isVideo && _selectedTrack != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _muteOriginal = !_muteOriginal);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Icon(PhosphorIconsRegular.speakerSimpleX,
                          size: 18, color: c.ink2),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Убрать звук видео',
                            style: SeeUTypography.caption
                                .copyWith(fontWeight: FontWeight.w600)),
                      ),
                      AnimatedContainer(
                        duration: SeeUMotion.normal,
                        curve: SeeUMotion.smooth,
                        width: 44,
                        height: 26,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: _muteOriginal
                              ? SeeUColors.accent
                              : c.line,
                          borderRadius: BorderRadius.circular(SeeURadii.pill),
                        ),
                        child: AnimatedAlign(
                          duration: SeeUMotion.normal,
                          curve: SeeUMotion.smooth,
                          alignment: _muteOriginal
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The music segment selector adapts to the publish format:
  ///  • video → locked window = clip length;
  ///  • photo + story → locked 15s window (photo stories are ≤ 15s);
  ///  • photo + post → start-only, the song loops forever from there.
  Widget _buildMusicTrimmer() {
    final track = _selectedTrack!;
    if (widget.isVideo) {
      return WaveformRangeTrimmer(
        key: ValueKey('trim_v_${track.id}_${_clipDuration.round()}'),
        track: track,
        lockedWindowSeconds: _clipDuration,
        initialStartSec: _audioStartSec,
        onChanged: (sel) => _audioStartSec = sel.startSec,
      );
    }
    if (_publishMode == 0) {
      return WaveformRangeTrimmer(
        key: ValueKey('trim_ps_${track.id}'),
        track: track,
        lockedWindowSeconds: 15,
        initialStartSec: _audioStartSec,
        onChanged: (sel) => _audioStartSec = sel.startSec,
      );
    }
    return WaveformRangeTrimmer(
      key: ValueKey('trim_pp_${track.id}'),
      track: track,
      startOnly: true,
      initialStartSec: _audioStartSec,
      onChanged: (sel) => _audioStartSec = sel.startSec,
    );
  }

  // ── Music button + trim slider ──────────────────────────────────────────

  /// Duration of the clip the user is publishing (video length or 15s for photo)
  double get _clipDuration {
    if (widget.isVideo && _videoCtrl != null && _videoReady) {
      final d = _videoCtrl!.value.duration.inMilliseconds / 1000.0;
      return d > 0 ? d : 15;
    }
    return 15; // photo story/post shows 15s
  }

  /// Open the full-screen video trimmer. On success replaces the working file
  /// (preview + upload) with the physically trimmed copy.
  Future<void> _openVideoTrim() async {
    if (!widget.isVideo) return;
    HapticFeedback.mediumImpact();
    final maxSel =
        _publishMode == 0 ? kStoryMaxVideoSeconds.toDouble() : null;
    final result = await Navigator.of(context).push<VideoTrimResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VideoTrimScreen(
          filePath: _trimmedVideoPath ?? widget.file.path,
          maxSelectionSec: maxSel,
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (result.outputPath == null) {
      showSeeUSnackBar(context, 'Не удалось обрезать видео',
          tone: SeeUTone.danger, duration: const Duration(seconds: 2));
      return;
    }

    final path = result.outputPath!;
    setState(() {
      _trimmedVideoPath = path;
      _stylizedFilename = 'trim_${DateTime.now().millisecondsSinceEpoch}.mp4';
      _videoReady = false;
    });
    // No need to read video bytes — upload streams from disk via MultipartFile.fromFile.
    final old = _videoCtrl;
    final nc = VideoPlayerController.file(File(path));
    _videoCtrl = nc;
    await old?.dispose();
    try {
      await nc.setLooping(true);
      await nc.initialize();
      if (!mounted) return;
      setState(() {
        _videoReady = true;
        _videoDurationSec = nc.value.duration.inMilliseconds / 1000.0;
        _trimmedDurationSec = _videoDurationSec;
        if (_storyTooLong && _publishMode == 0) _publishMode = 1;
      });
      nc.play();
    } catch (e) {
      debugPrint('trim reinit video: $e');
    }
  }

  void _openMusicPicker() {
    _videoCtrl?.pause();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MusicPickerSheet(
        onSelect: (track) {
          setState(() {
            _selectedTrack = track;
            _audioStartSec = 0;
          });
          Navigator.of(context).pop();
        },
      ),
    ).then((_) {
      if (mounted && _videoReady) _videoCtrl?.play();
    });
  }

  // ── Post form (caption, location, tags) ────────────────────────────────

  static const _quickEmojis = ['😊', '🔥', '✨', '❤️', '😍', '🙌'];

  void _insertEmoji(String e) {
    final sel = _captionCtrl.selection;
    final text = _captionCtrl.text;
    final start = sel.isValid ? sel.start : text.length;
    final end   = sel.isValid ? sel.end   : text.length;
    final next  = text.replaceRange(start, end, e);
    _captionCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + e.length),
    );
    HapticFeedback.selectionClick();
  }

  void _openEmojiPickerForCaption() {
    // Reuse the same category emoji sheet but insert into caption instead.
    const categories = {
      'Смайлы':    ['😀','😂','😍','🥰','😎','🤩','😴','🤯','🥳','😭','😤','🫶',
                    '🙃','😇','🤭','😅','😏','🤔','😒','😳','🤗','😘'],
      'Активность':['🔥','❤️','⭐','🎉','✨','💫','💥','🌈','🎵','🎶','👑','💎',
                    '🏆','🎯','💪','⚡','🌟','🎊','🎈','💯','🎁','🛡️'],
      'Природа':   ['🌸','🌺','🦋','🌙','☀️','⚡','🌊','🍀','🌴','🦄','🐉','🐬',
                    '🦁','🌻','🍁','❄️','🌿','🐝','🦊','🐺','🦅','🌵'],
      'Жесты':     ['👍','👎','🙌','🤝','✌️','🫵','💪','👏','🙏','🤙','☝️','🫂',
                    '🤜','🤛','👊','✊','🤞','🤟','🤘','👋','🖐️','✋'],
    };
    showSeeUBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final c = ctx.seeuColors;
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.5,
          child: Column(
            children: [
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('ОФОРМЛЕНИЕ',
                              style: SeeUTypography.kicker
                                  .copyWith(color: SeeUColors.accent)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Эмодзи',
                        style:
                            SeeUTypography.displayS.copyWith(color: c.ink)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: DefaultTabController(
                  length: categories.length,
                  child: Column(
                    children: [
                      TabBar(
                        isScrollable: true,
                        labelColor: SeeUColors.accent,
                        unselectedLabelColor: c.ink3,
                        indicatorColor: SeeUColors.accent,
                        tabs: categories.keys
                            .map((k) => Tab(text: k))
                            .toList(),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: categories.values.map((emojis) {
                            return GridView.count(
                              padding: const EdgeInsets.all(12),
                              crossAxisCount: 8,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              children: emojis.map((e) {
                                return GestureDetector(
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _insertEmoji(e);
                                  },
                                  child: Center(
                                    child: Text(e,
                                        style: const TextStyle(fontSize: 26)),
                                  ),
                                );
                              }).toList(),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPostForm(SeeUThemeColors c) {
    final captionLen = _captionCtrl.text.characters.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          // Caption card with emoji row + progress counter.
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(SeeURadii.medium),
              border: Border.all(color: c.line),
              boxShadow: SeeUShadows.sm,
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _captionCtrl,
                        maxLines: 5,
                        minLines: 1,
                        maxLength: 2000,
                        textInputAction: TextInputAction.done,
                        style: SeeUTypography.body.copyWith(fontSize: 14.5),
                        decoration: InputDecoration(
                          hintText: 'Расскажи что происходит...',
                          hintStyle: SeeUTypography.body
                              .copyWith(fontSize: 14.5, color: c.ink4),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          counterText: '',
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final e in _quickEmojis)
                      GestureDetector(
                        onTap: () => _insertEmoji(e),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(e, style: const TextStyle(fontSize: 18)),
                        ),
                      ),
                    GestureDetector(
                      onTap: _openEmojiPickerForCaption,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.line),
                        ),
                        child: Icon(PhosphorIconsRegular.smiley,
                            size: 14, color: c.ink3),
                      ),
                    ),
                    const Spacer(),
                    // Progress counter: bar + number
                    Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: captionLen / 2000,
                              backgroundColor: c.line,
                              valueColor: AlwaysStoppedAnimation(
                                captionLen > 1800
                                    ? SeeUColors.error
                                    : SeeUColors.accent,
                              ),
                              minHeight: 3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('$captionLen',
                            style: SeeUTypography.mono
                                .copyWith(fontSize: 11, color: c.ink4)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Location — full width with prominent GPS button
          Container(
            height: 46,
            padding: const EdgeInsets.only(left: 13),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(SeeURadii.medium),
              border: Border.all(color: c.line),
              boxShadow: SeeUShadows.sm,
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsRegular.mapPin,
                    size: 16, color: SeeUColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _locationCtrl,
                    style: SeeUTypography.body.copyWith(fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'Место',
                      hintStyle: SeeUTypography.caption
                          .copyWith(color: c.ink3, fontSize: 13.5),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                // GPS button — proper 44px touch area
                GestureDetector(
                  onTap: _gpsLoading ? null : _fillGpsLocation,
                  child: SizedBox(
                    width: 52,
                    height: 46,
                    child: Center(
                      child: _gpsLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: SeeUColors.accent,
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(PhosphorIconsRegular.crosshair,
                                    size: 16, color: SeeUColors.accent),
                                const SizedBox(height: 2),
                                Text('GPS',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: SeeUColors.accent,
                                      fontWeight: FontWeight.w700,
                                    )),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Tag entry — full row with Expanded input
          Container(
            height: 46,
            padding: const EdgeInsets.only(left: 13),
            decoration: BoxDecoration(
              color: SeeUColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(SeeURadii.medium),
              border: Border.all(color: SeeUColors.accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsRegular.hash,
                    size: 15, color: SeeUColors.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _tagCtrl,
                    focusNode: _tagFocus,
                    textInputAction: TextInputAction.done,
                    style: SeeUTypography.body.copyWith(
                        fontSize: 13.5,
                        color: SeeUColors.accent,
                        fontWeight: FontWeight.w600),
                    cursorColor: SeeUColors.accent,
                    decoration: InputDecoration(
                      hintText: 'Добавить тег...',
                      hintStyle: SeeUTypography.caption.copyWith(
                          color: SeeUColors.accent.withValues(alpha: 0.5),
                          fontSize: 13.5),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                // Add button — shown when there's text
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  child: _tagCtrl.text.trim().isNotEmpty
                      ? GestureDetector(
                          onTap: _addTag,
                          child: Container(
                            width: 52,
                            height: 46,
                            alignment: Alignment.center,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: SeeUColors.accent,
                                borderRadius:
                                    BorderRadius.circular(SeeURadii.pill),
                              ),
                              child: const Text('Добавить',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        )
                      : const SizedBox(width: 13),
                ),
              ],
            ),
          ),

          if (_tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _tags.map((t) {
                  // Tap on the × icon removes the tag, not the whole chip
                  return Container(
                    padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
                    decoration: BoxDecoration(
                      color: SeeUColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(SeeURadii.pill),
                      border: Border.all(
                        color: SeeUColors.accent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('#$t',
                            style: SeeUTypography.caption.copyWith(
                                fontSize: 12,
                                color: SeeUColors.accent,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 4),
                        // Explicit × button — prevents accidental deletion
                        GestureDetector(
                          onTap: () => setState(() => _tags.remove(t)),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: const Icon(PhosphorIconsBold.x,
                                size: 10, color: SeeUColors.accent),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Publish button area ────────────────────────────────────────────────
  //
  // State machine: idle → preparing → uploading → processing → success → navigate
  //                                                                ↓ (on error)
  //                                                              failed → idle (retry)

  Widget _buildPublishButton(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
        child: switch (_publishState) {
          _PublishState.idle    => _buildIdleButton(c),
          _PublishState.preparing => _buildSpinnerTile(
              key: const ValueKey('prepare'),
              c: c,
              label: 'Подготавливаем публикацию...',
            ),
          _PublishState.uploading => _buildUploadTile(c),
          _PublishState.processing => _buildSpinnerTile(
              key: const ValueKey('process'),
              c: c,
              label: 'Обрабатываем публикацию...',
            ),
          _PublishState.success => _buildSuccessTile(c),
          _PublishState.failed  => _buildFailedTile(c),
        },
      ),
    );
  }

  Widget _buildIdleButton(SeeUThemeColors c) {
    return GestureDetector(
      key: const ValueKey('idle'),
      onTap: _publish,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [SeeUColors.accentSecondary, SeeUColors.accent],
          ),
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          boxShadow: [
            BoxShadow(
              color: SeeUColors.accent.withValues(alpha: 0.4),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _publishMode == 0
                  ? 'Опубликовать историю'
                  : (widget.isVideo ? 'Опубликовать рилс' : 'Опубликовать'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(PhosphorIconsRegular.paperPlaneTilt,
                color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildSpinnerTile({
    required Key key,
    required SeeUThemeColors c,
    required String label,
  }) {
    return Container(
      key: key,
      height: 56,
      decoration: BoxDecoration(
        color: SeeUColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(SeeURadii.medium),
        border: Border.all(
            color: SeeUColors.accent.withValues(alpha: 0.28), width: 0.8),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              color: SeeUColors.accent, strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: c.ink,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadTile(SeeUThemeColors c) {
    final pct = (_uploadProgress * 100).round();
    final total = _totalBytes;
    return Container(
      key: const ValueKey('upload'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(SeeURadii.medium),
        border: Border.all(color: c.line, width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _publishMode == 0
                    ? 'История загружается...'
                    : (widget.isVideo
                        ? 'Видео загружается...'
                        : 'Фото загружается...'),
                style: TextStyle(
                  color: c.ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$pct%',
                style: const TextStyle(
                  color: SeeUColors.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _uploadProgress,
              backgroundColor: c.line,
              valueColor:
                  const AlwaysStoppedAnimation(SeeUColors.accent),
              minHeight: 4,
            ),
          ),
          if (total > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${_formatBytes(_uploadedBytes)} / ${_formatBytes(total)}',
              style: TextStyle(color: c.ink3, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSuccessTile(SeeUThemeColors c) {
    return Container(
      key: const ValueKey('success'),
      height: 56,
      decoration: BoxDecoration(
        color: SeeUColors.success,
        borderRadius: BorderRadius.circular(SeeURadii.medium),
        boxShadow: [
          BoxShadow(
            color: SeeUColors.success.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsBold.checkCircle, color: Colors.white, size: 22),
          SizedBox(width: 8),
          Text('Опубликовано!',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildFailedTile(SeeUThemeColors c) {
    return Container(
      key: const ValueKey('failed'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: SeeUColors.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(SeeURadii.medium),
        border: Border.all(
            color: SeeUColors.error.withValues(alpha: 0.28), width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsBold.warningCircle,
                  color: SeeUColors.error, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _publishError ?? 'Не удалось опубликовать',
                  style: const TextStyle(
                    color: SeeUColors.error,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _publishState = _PublishState.idle),
                  child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius:
                          BorderRadius.circular(SeeURadii.small),
                      border: Border.all(color: c.line),
                    ),
                    child: Text('Отмена',
                        style: TextStyle(
                            color: c.ink2,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: _publish,
                  child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: SeeUColors.accent,
                      borderRadius:
                          BorderRadius.circular(SeeURadii.small),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsBold.arrowClockwise,
                            color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text('Повторить',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 Б';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TWO-STEP FLOW — Edit page & Details page
  // ════════════════════════════════════════════════════════════════════════════

  // ── Edit page ─────────────────────────────────────────────────────────────
  //
  // Full-height preview (Expanded) + tools at bottom + "Далее →" button.

  Widget _buildEditPage(SeeUThemeColors c) {
    return Column(
      key: const ValueKey(_EditStep.edit),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopBarEdit(c),
        // Preview fills all remaining vertical space
        Expanded(child: _buildPreviewLarge(c)),
        // Photo enhancement slider — only when a tool is active
        if (!widget.isVideo && _activeTool != _EnhanceTool.none)
          _buildEnhancerSlider(c),
        // Photo enhancement toolbar — always visible for photos
        if (!widget.isVideo)
          _buildEnhancerToolbar(c),
        // Video cover frame picker (toggle via chip in action row)
        if (widget.isVideo && _coverPickerVisible)
          _buildCoverFramePicker(c),
        // Carousel dots for multi-photo
        if (widget.extraFiles.isNotEmpty)
          _buildCarouselDots(c),
        // Action chips (Текст / Стикер / Музыка / Обрезать / etc.)
        _buildActionRow(c),
        // Music trim card — slides in when a track is selected
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: _selectedTrack != null
              ? AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: 1.0,
                  child: _buildMusicTrimCard(c),
                )
              : const SizedBox.shrink(),
        ),
        _buildNextButton(c),
      ],
    );
  }

  // ── Details page ──────────────────────────────────────────────────────────
  //
  // Small thumbnail + form (caption / location / tags) + publish button.

  Widget _buildDetailsPage(SeeUThemeColors c) {
    return Column(
      key: const ValueKey(_EditStep.details),
      children: [
        _buildTopBarDetails(c),
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDetailsThumbnail(c),
                const SizedBox(height: 16),
                // Post / Reel: caption, location, tags
                if (_publishMode == 1) _buildPostForm(c),
                // Story: caption + audience + reply audience
                if (_publishMode == 0) ...[
                  _buildStoryCaptionField(c),
                  const SizedBox(height: 12),
                  _buildAudienceRow(c),
                  const SizedBox(height: 12),
                  _buildReplyAudienceRow(c),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        if (!_isEditingText) _buildPublishButton(c),
      ],
    );
  }

  // ── Top bar for details step ───────────────────────────────────────────────

  Widget _buildTopBarDetails(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          // ← Back to edit
          _GlassSquareButton(
            width: null,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _stepForward = false;
                _step = _EditStep.edit;
                _compositedBytes = null; // invalidate; will re-composite on next "Далее →"
              });
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsBold.caretLeft, color: c.ink, size: 17),
                const SizedBox(width: 4),
                Text('Редактировать',
                    style: SeeUTypography.caption.copyWith(
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
          // Title — editorial: kicker + serif
          Expanded(
            child: Center(
              child: Column(
                children: [
                  Text('ПУБЛИКАЦИЯ',
                      style: SeeUTypography.kicker
                          .copyWith(color: SeeUColors.accent)),
                  const SizedBox(height: 2),
                  Text('Детали',
                      style: SeeUTypography.displayS
                          .copyWith(color: c.ink, fontSize: 18)),
                ],
              ),
            ),
          ),
          // Spacer to balance left button width
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  // ── Composite preview to bytes before entering details step ─────────────
  //
  // Called when user taps "Далее →". Captures RepaintBoundary while the edit
  // step is still in the widget tree (enhancement + layers already rendered).
  // Result stored in _compositedBytes — used for the thumbnail and upload.

  Future<void> _compositeForDetails() async {
    if (widget.isVideo) {
      // For video: ensure we have a thumbnail for the details step
      if (_videoThumbBytes == null) await _generateVideoThumb();
      // Generate cover frame strip if not yet done and cover picker hasn't been opened
      if (_coverFrameThumbs.isEmpty) unawaited(_generateCoverFrameThumbs());
      return;
    }
    final pixelRatio = MediaQuery.of(context).devicePixelRatio.clamp(2.0, 3.0);
    final key = _publishMode == 0 ? _storyCanvasKey : _postCanvasKey;
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    try {
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null && mounted) {
        setState(() => _compositedBytes = byteData.buffer.asUint8List());
      }
    } catch (e) {
      debugPrint('_compositeForDetails: $e');
    }
  }

  // ── "Далее →" button (end of edit step) ──────────────────────────────────

  Widget _buildNextButton(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: GestureDetector(
        onTap: () async {
          HapticFeedback.selectionClick();
          // Composite while edit step is still in tree (captures enhancement + layers)
          await _compositeForDetails();
          if (mounted) setState(() { _stepForward = true; _step = _EditStep.details; });
        },
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [SeeUColors.accentSecondary, SeeUColors.accent],
            ),
            borderRadius: BorderRadius.circular(SeeURadii.medium),
            boxShadow: [
              BoxShadow(
                color: SeeUColors.accent.withValues(alpha: 0.4),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Далее',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(PhosphorIconsRegular.arrowRight,
                  color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  // ── Details thumbnail ─────────────────────────────────────────────────────

  Widget _buildDetailsThumbnail(SeeUThemeColors c) {
    final hasExtra = widget.extraFiles.isNotEmpty;
    final thumbBytes = _compositedBytes ?? _bytes ?? _videoThumbBytes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Primary thumbnail
              Container(
                width: 90,
                height: 120,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: SeeUShadows.md,
                ),
                child: thumbBytes != null
                    ? Image.memory(thumbBytes, fit: BoxFit.cover)
                    : widget.heroTag != null
                        ? Hero(
                            tag: widget.heroTag!,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                  gradient: SeeUGradients.heroOrange),
                            ),
                          )
                        : const DecoratedBox(
                            decoration: BoxDecoration(
                                gradient: SeeUGradients.heroOrange),
                            child: Center(
                              child: Icon(PhosphorIconsRegular.image,
                                  color: Colors.white, size: 28),
                            ),
                          ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Mode badge pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            SeeUColors.accentSecondary, SeeUColors.accent],
                        ),
                        borderRadius: BorderRadius.circular(SeeURadii.pill),
                      ),
                      child: Text(
                        _publishMode == 0
                            ? 'История'
                            : (widget.isVideo
                                ? 'Рилс'
                                : (hasExtra
                                    ? 'Карусель · ${1 + widget.extraFiles.length}'
                                    : 'Публикация')),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _publishMode == 0
                          ? 'Выбери аудиторию и добавь описание'
                          : hasExtra
                              ? 'Карусель из ${1 + widget.extraFiles.length} фото'
                              : 'Добавь описание, подпись и теги',
                      style: SeeUTypography.caption.copyWith(color: c.ink3),
                    ),
                    if (widget.isVideo && _coverFrameSec != null) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(PhosphorIconsFill.images,
                            size: 12, color: SeeUColors.accent),
                        const SizedBox(width: 4),
                        Text('Обложка выбрана',
                            style: SeeUTypography.micro
                                .copyWith(color: SeeUColors.accent)),
                      ]),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // Multi-photo strip (shown when carousel)
          if (hasExtra) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 1 + widget.extraFiles.length + 1, // +1 for "add more"
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  if (i == 1 + widget.extraFiles.length) {
                    return _buildAddMoreButton(c);
                  }
                  final bytes = i == 0
                      ? (_compositedBytes ?? _bytes)
                      : (i - 1 < widget.extraBytes.length
                          ? widget.extraBytes[i - 1]
                          : null);
                  return Container(
                    width: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: i == 0
                            ? SeeUColors.accent
                            : c.line.withValues(alpha: 0.5),
                        width: i == 0 ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: bytes != null
                        ? Image.memory(bytes, fit: BoxFit.cover)
                        : const DecoratedBox(
                            decoration: BoxDecoration(
                                gradient: SeeUGradients.heroOrange)),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAddMoreButton(SeeUThemeColors c) {
    return GestureDetector(
      onTap: () async {
        // TODO: allow adding more photos — requires stateful extra lists
        showSeeUSnackBar(context, 'Выберите фото в галерее при открытии');
      },
      child: Container(
        width: 64,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.line, style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(PhosphorIconsRegular.plus, size: 20, color: SeeUColors.accent),
            const SizedBox(height: 2),
            Text('Ещё', style: SeeUTypography.micro.copyWith(
                color: SeeUColors.accent, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── Audience row (story mode, details step) ───────────────────────────────

  Widget _buildAudienceRow(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          border: Border.all(color: c.line),
          boxShadow: SeeUShadows.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Аудитория',
                style: SeeUTypography.micro.copyWith(color: c.ink3)),
            const SizedBox(height: 12),
            // All friends option
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _closeFriendsOnly = false);
              },
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: SeeUMotion.normal,
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: !_closeFriendsOnly
                          ? SeeUColors.accent
                          : c.surface2,
                      border: Border.all(
                        color: !_closeFriendsOnly
                            ? SeeUColors.accent
                            : c.line,
                        width: 2,
                      ),
                    ),
                    child: !_closeFriendsOnly
                        ? const Icon(PhosphorIconsBold.check,
                            color: Colors.white, size: 12)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  const Icon(PhosphorIconsRegular.users,
                      size: 18, color: SeeUColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Все',
                            style: SeeUTypography.caption
                                .copyWith(fontWeight: FontWeight.w700)),
                        Text('Все ваши подписчики',
                            style: SeeUTypography.micro
                                .copyWith(color: c.ink3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Close friends option
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _closeFriendsOnly = true);
              },
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: SeeUMotion.normal,
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _closeFriendsOnly
                          ? SeeUColors.success
                          : c.surface2,
                      border: Border.all(
                        color: _closeFriendsOnly
                            ? SeeUColors.success
                            : c.line,
                        width: 2,
                      ),
                    ),
                    child: _closeFriendsOnly
                        ? const Icon(PhosphorIconsBold.check,
                            color: Colors.white, size: 12)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  const Icon(PhosphorIconsFill.star,
                      size: 18, color: SeeUColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Только близкие друзья',
                            style: SeeUTypography.caption
                                .copyWith(fontWeight: FontWeight.w700)),
                        Text('Избранный список подписчиков',
                            style: SeeUTypography.micro
                                .copyWith(color: c.ink3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // CAROUSEL DOTS
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildCarouselDots(SeeUThemeColors c) {
    final total = 1 + widget.extraFiles.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (i) {
          final active = i == _activeSlot;
          return AnimatedContainer(
            duration: SeeUMotion.normal,
            width: active ? 18 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: active ? SeeUColors.accent : c.line,
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // VIDEO COVER FRAME PICKER
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildCoverFramePicker(SeeUThemeColors c) {
    if (_coverFrameThumbs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2, color: SeeUColors.accent),
            ),
            const SizedBox(width: 8),
            Text('Загружаем кадры…',
                style: SeeUTypography.micro.copyWith(color: c.ink3)),
          ]),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Row(children: [
            Text('Обложка',
                style: SeeUTypography.caption.copyWith(
                    fontWeight: FontWeight.w700, fontSize: 12)),
            const Spacer(),
            if (_coverFrameSec != null)
              GestureDetector(
                onTap: () => setState(() => _coverFrameSec = null),
                child: Text('Сбросить',
                    style: SeeUTypography.micro.copyWith(
                        color: SeeUColors.error)),
              ),
          ]),
        ),
        SizedBox(
          height: 68,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            itemCount: _coverFrameThumbs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (ctx, i) {
              final frameSec = (_videoDurationSec / (_coverFrameThumbs.length - 1)) * i;
              final isSelected = _coverFrameSec != null &&
                  (_coverFrameSec! - frameSec).abs() < 0.5;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _coverFrameSec = frameSec;
                    _uploadedCoverBytes = _coverFrameThumbs[i];
                  });
                },
                child: AnimatedContainer(
                  duration: SeeUMotion.normal,
                  width: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? SeeUColors.accent
                          : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: isSelected ? SeeUShadows.sm : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(fit: StackFit.expand, children: [
                    Image.memory(_coverFrameThumbs[i], fit: BoxFit.cover),
                    if (isSelected)
                      Container(
                        color: SeeUColors.accent.withValues(alpha: 0.25),
                        child: const Center(
                          child: Icon(PhosphorIconsFill.checkCircle,
                              color: Colors.white, size: 18),
                        ),
                      ),
                  ]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // STORY DETAILS EXTRAS
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildStoryCaptionField(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          border: Border.all(color: c.line),
          boxShadow: SeeUShadows.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Описание истории',
                style: SeeUTypography.micro.copyWith(color: c.ink3)),
            const SizedBox(height: 8),
            TextField(
              controller: _storyCaptionCtrl,
              maxLines: 3,
              maxLength: 300,
              style: SeeUTypography.body.copyWith(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Расскажи что происходит (необязательно)…',
                hintStyle:
                    SeeUTypography.body.copyWith(color: c.ink3, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                counterStyle: SeeUTypography.micro.copyWith(color: c.ink3),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyAudienceRow(SeeUThemeColors c) {
    const opts = ['Все', 'Только друзья', 'Никто'];
    const icons = [
      PhosphorIconsRegular.chatCircle,
      PhosphorIconsRegular.userCircle,
      PhosphorIconsRegular.prohibit,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          border: Border.all(color: c.line),
          boxShadow: SeeUShadows.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Кто может ответить',
                style: SeeUTypography.micro.copyWith(color: c.ink3)),
            const SizedBox(height: 12),
            Row(
              children: List.generate(3, (i) {
                final active = _replyAudience == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _replyAudience = i);
                    },
                    child: AnimatedContainer(
                      duration: SeeUMotion.normal,
                      margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: active
                            ? SeeUColors.accent.withValues(alpha: 0.12)
                            : c.surface2,
                        borderRadius: BorderRadius.circular(SeeURadii.medium),
                        border: Border.all(
                          color: active
                              ? SeeUColors.accent.withValues(alpha: 0.5)
                              : c.line,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(icons[i],
                              size: 16,
                              color: active ? SeeUColors.accent : c.ink3),
                          const SizedBox(height: 4),
                          Text(opts[i],
                              style: SeeUTypography.micro.copyWith(
                                color: active ? SeeUColors.accent : c.ink3,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 10,
                              )),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PHOTO ENHANCEMENT
  // ════════════════════════════════════════════════════════════════════════════

  // ── Enhancer toolbar (photos only, shown in edit step) ────────────────────

  Widget _buildEnhancerToolbar(SeeUThemeColors c) {
    final tools = [
      (_EnhanceTool.none,       PhosphorIconsRegular.magicWand,     'Авто'),
      (_EnhanceTool.brightness, PhosphorIconsRegular.sun,            'Яркость'),
      (_EnhanceTool.contrast,   PhosphorIconsRegular.circle,         'Контраст'),
      (_EnhanceTool.saturation, PhosphorIconsRegular.dropHalf,       'Цвет'),
      (_EnhanceTool.warmth,     PhosphorIconsRegular.thermometer,    'Тепло'),
    ];

    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
        itemCount: tools.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final (tool, icon, label) = tools[i];
          final isAuto = tool == _EnhanceTool.none;
          final isActive = _activeTool == tool && !isAuto;
          final hasValue = isAuto
              ? (_brightness != 0 || _contrast != 0 ||
                 _saturation != 0 || _warmth != 0)
              : false;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              if (isAuto) {
                // Apply auto-enhance preset
                setState(() {
                  _brightness = 0.05;
                  _contrast   = 0.10;
                  _saturation = 0.15;
                  _warmth     = 0.02;
                  _activeTool = _EnhanceTool.none;
                });
              } else {
                setState(() {
                  _activeTool = isActive ? _EnhanceTool.none : tool;
                });
              }
            },
            child: AnimatedContainer(
              duration: SeeUMotion.normal,
              curve: SeeUMotion.smooth,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isActive
                    ? SeeUColors.accent.withValues(alpha: 0.12)
                    : (hasValue && isAuto
                        ? SeeUColors.accent.withValues(alpha: 0.08)
                        : c.surface2),
                borderRadius: BorderRadius.circular(SeeURadii.pill),
                border: Border.all(
                  color: (isActive || (hasValue && isAuto))
                      ? SeeUColors.accent.withValues(alpha: 0.5)
                      : c.line,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 13,
                      color: (isActive || (hasValue && isAuto))
                          ? SeeUColors.accent
                          : c.ink2),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: SeeUTypography.caption.copyWith(
                      fontSize: 12,
                      color: (isActive || (hasValue && isAuto))
                          ? SeeUColors.accent
                          : c.ink2,
                      fontWeight: (isActive || (hasValue && isAuto))
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Enhancer slider (shown when a tool is active) ─────────────────────────

  Widget _buildEnhancerSlider(SeeUThemeColors c) {
    double currentValue;
    String label;
    switch (_activeTool) {
      case _EnhanceTool.brightness:
        currentValue = _brightness; label = 'Яркость';
      case _EnhanceTool.contrast:
        currentValue = _contrast;   label = 'Контраст';
      case _EnhanceTool.saturation:
        currentValue = _saturation; label = 'Цвет';
      case _EnhanceTool.warmth:
        currentValue = _warmth;     label = 'Тепло';
      case _EnhanceTool.none:
        return const SizedBox.shrink();
    }
    final pct = (currentValue * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              Text(label,
                  style: SeeUTypography.caption.copyWith(
                      fontWeight: FontWeight.w600, fontSize: 12)),
              const Spacer(),
              Text('${pct > 0 ? "+" : ""}$pct%',
                  style: SeeUTypography.mono.copyWith(
                      fontSize: 11, color: SeeUColors.accent)),
              const SizedBox(width: 8),
              // Reset button
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    switch (_activeTool) {
                      case _EnhanceTool.brightness: _brightness = 0;
                      case _EnhanceTool.contrast:   _contrast   = 0;
                      case _EnhanceTool.saturation: _saturation = 0;
                      case _EnhanceTool.warmth:     _warmth     = 0;
                      case _EnhanceTool.none: break;
                    }
                  });
                },
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.line),
                  ),
                  child: Icon(PhosphorIconsRegular.arrowCounterClockwise,
                      size: 13, color: c.ink3),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: SeeUColors.accent,
              inactiveTrackColor: c.line,
              thumbColor: SeeUColors.accent,
              overlayColor: SeeUColors.accent.withValues(alpha: 0.15),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: currentValue,
              min: -1.0,
              max: 1.0,
              onChanged: (v) {
                setState(() {
                  switch (_activeTool) {
                    case _EnhanceTool.brightness: _brightness = v;
                    case _EnhanceTool.contrast:   _contrast   = v;
                    case _EnhanceTool.saturation: _saturation = v;
                    case _EnhanceTool.warmth:     _warmth     = v;
                    case _EnhanceTool.none: break;
                  }
                });
                // Haptic every 10% change
                final bucket = (v * 10).round();
                if (bucket != _lastHapticBucket) {
                  _lastHapticBucket = bucket;
                  HapticFeedback.selectionClick();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Enhancement color filter wrapper ─────────────────────────────────────

  Widget _wrapWithEnhancement(Widget child) {
    if (_brightness == 0 && _contrast == 0 &&
        _saturation == 0 && _warmth == 0) {
      return child;
    }
    Widget result = child;
    if (_brightness != 0) {
      result = ColorFiltered(
        colorFilter:
            ColorFilter.matrix(_brightnessMatrix(_brightness)),
        child: result,
      );
    }
    if (_contrast != 0) {
      result = ColorFiltered(
        colorFilter:
            ColorFilter.matrix(_contrastMatrix(_contrast)),
        child: result,
      );
    }
    if (_saturation != 0) {
      result = ColorFiltered(
        colorFilter:
            ColorFilter.matrix(_saturationMatrix(_saturation)),
        child: result,
      );
    }
    if (_warmth != 0) {
      result = ColorFiltered(
        colorFilter: ColorFilter.matrix(_warmthMatrix(_warmth)),
        child: result,
      );
    }
    return result;
  }

  List<double> _brightnessMatrix(double v) => [
    1, 0, 0, 0, v * 255,
    0, 1, 0, 0, v * 255,
    0, 0, 1, 0, v * 255,
    0, 0, 0, 1, 0,
  ];

  List<double> _contrastMatrix(double v) {
    final cv = v + 1.0;
    final t = (1.0 - cv) / 2.0 * 255;
    return [
      cv, 0, 0, 0, t,
      0, cv, 0, 0, t,
      0, 0, cv, 0, t,
      0, 0, 0, 1, 0,
    ];
  }

  List<double> _saturationMatrix(double v) {
    const rw = 0.213, gw = 0.715, bw = 0.072;
    final s = v + 1.0;
    return [
      rw + (1 - rw) * s, gw - gw * s,        bw - bw * s,        0, 0,
      rw - rw * s,       gw + (1 - gw) * s,  bw - bw * s,        0, 0,
      rw - rw * s,       gw - gw * s,         bw + (1 - bw) * s, 0, 0,
      0,                 0,                   0,                  1, 0,
    ];
  }

  List<double> _warmthMatrix(double v) => [
    1 + v * 0.12, 0, 0, 0, 0,
    0, 1 + v * 0.03, 0, 0, 0,
    0, 0, 1 - v * 0.18, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

// ─── Action chip widget ────────────────────────────────────────────────────

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final double maxLabelWidth;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.maxLabelWidth = 60,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            border: Border.all(color: c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxLabelWidth),
                child: Text(
                  label,
                  style: SeeUTypography.caption.copyWith(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Spinning chip (GPS loading) ───────────────────────────────────────────

class _SpinningGeoChip extends StatefulWidget {
  final Color color;
  const _SpinningGeoChip({required this.color});
  @override
  State<_SpinningGeoChip> createState() => _SpinningGeoChipState();
}

class _SpinningGeoChipState extends State<_SpinningGeoChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(SeeURadii.pill),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RotationTransition(
            turns: _ctrl,
            child: Icon(PhosphorIconsRegular.circleNotch,
                size: 15, color: widget.color),
          ),
          const SizedBox(width: 5),
          Text('Геотег',
              style: SeeUTypography.caption.copyWith(
                  fontSize: 12,
                  color: widget.color,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Canvas layer data models ───────────────────────────────────────────────

enum _BgStyle { none, blur, solid }
enum _LayerKind { text, sticker, location, link }
enum _TextAlign2 { left, center, right }

class _CanvasLayer {
  final int id;
  final _LayerKind kind;
  Offset position; // normalized 0..1
  double scale = 1.0;
  double rotation = 0.0;
  // text
  String text;
  Color textColor;
  _BgStyle bgStyle;
  Color bgColor;
  double fontSize;
  _TextAlign2 align;
  // sticker
  String emoji;
  // location sticker
  String locationName;
  // link sticker
  String linkText;
  String linkUrl;

  _CanvasLayer({
    required this.id,
    required this.kind,
    this.position = const Offset(0.5, 0.5),
    this.text = '',
    this.textColor = Colors.white,
    this.bgStyle = _BgStyle.none,
    this.bgColor = Colors.black,
    this.fontSize = 24.0,
    this.align = _TextAlign2.center,
    this.emoji = '',
    this.locationName = '',
    this.linkText = '',
    this.linkUrl = '',
  });

  _CanvasLayer copy() => _CanvasLayer(
        id: id,
        kind: kind,
        position: position,
        text: text,
        textColor: textColor,
        bgStyle: bgStyle,
        bgColor: bgColor,
        fontSize: fontSize,
        align: align,
        emoji: emoji,
        locationName: locationName,
        linkText: linkText,
        linkUrl: linkUrl,
      )
        ..scale    = scale
        ..rotation = rotation;

  Map<String, dynamic> toJson() => {
        'kind':       kind.name,
        'position_x': position.dx,
        'position_y': position.dy,
        'scale':      scale,
        'rotation':   rotation,
        if (kind == _LayerKind.text) ...{
          'text':       text,
          'text_color': textColor.toARGB32(),
          'bg_style':   bgStyle.name,
          'bg_color':   bgColor.toARGB32(),
          'font_size':  fontSize,
          'align':      align.name,
        },
        if (kind == _LayerKind.sticker) 'emoji': emoji,
        if (kind == _LayerKind.location) 'location_name': locationName,
        if (kind == _LayerKind.link) ...{
          'link_text': linkText,
          'link_url':  linkUrl,
        },
      };
}

// ── Text editor helper widgets ─────────────────────────────────────────────

class _BgStyleBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _BgStyleBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? SeeUColors.accent.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: Border.all(
            color: selected
                ? SeeUColors.accent.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: selected ? SeeUColors.accent : Colors.white70),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color:
                    selected ? SeeUColors.accent : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlignBtn extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AlignBtn({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            size: 18,
            color: selected ? Colors.white : Colors.white54),
      ),
    );
  }
}

// ── Format chip (1:1 / 4:5 / 9:16) ───────────────────────────────────────────

class _FormatChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FormatChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? SeeUColors.accent.withValues(alpha: 0.12)
              : c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: Border.all(
            color: selected
                ? SeeUColors.accent.withValues(alpha: 0.5)
                : c.line,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: SeeUTypography.caption.copyWith(
            fontSize: 12.5,
            color: selected ? SeeUColors.accent : c.ink3,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ── Simple text input dialog (used for location sticker) ─────────────────

class _SimpleInputDialog extends StatelessWidget {
  final String title;
  final String hint;
  final TextEditingController ctrl;
  final IconData icon;
  final Color iconColor;

  const _SimpleInputDialog({
    required this.title,
    required this.hint,
    required this.ctrl,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return AlertDialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Text(title,
              style: SeeUTypography.body
                  .copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: SeeUTypography.body.copyWith(color: c.ink3),
          filled: true,
          fillColor: c.surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          isDense: true,
        ),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Отмена', style: TextStyle(color: c.ink3)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: Text('Добавить',
              style: TextStyle(
                  color: iconColor, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ── Poll creator bottom sheet ─────────────────────────────────────────────

class _PollCreatorSheet extends StatefulWidget {
  final StoryPoll? initial;
  const _PollCreatorSheet({this.initial});

  @override
  State<_PollCreatorSheet> createState() => _PollCreatorSheetState();
}

class _PollCreatorSheetState extends State<_PollCreatorSheet> {
  late final TextEditingController _questionCtrl;
  late final TextEditingController _optACtrl;
  late final TextEditingController _optBCtrl;

  @override
  void initState() {
    super.initState();
    _questionCtrl = TextEditingController(text: widget.initial?.question ?? '');
    _optACtrl     = TextEditingController(text: widget.initial?.optionA ?? '');
    _optBCtrl     = TextEditingController(text: widget.initial?.optionB ?? '');
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    _optACtrl.dispose();
    _optBCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final q  = _questionCtrl.text.trim();
    final a  = _optACtrl.text.trim();
    final b  = _optBCtrl.text.trim();
    if (q.isEmpty || a.isEmpty || b.isEmpty) {
      showSeeUSnackBar(context, 'Заполните вопрос и оба варианта ответа',
          tone: SeeUTone.danger);
      return;
    }
    Navigator.pop(context, StoryPoll(question: q, optionA: a, optionB: b));
  }

  Widget _inputField(TextEditingController ctrl, String hint,
      {TextInputAction action = TextInputAction.next}) {
    final c = context.seeuColors;
    return TextField(
      controller: ctrl,
      textInputAction: action,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: SeeUTypography.body.copyWith(color: c.ink4),
        filled: true,
        fillColor: c.surface2,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c      = context.seeuColors;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(SeeURadii.card),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: c.line, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(
            children: [
              const Icon(PhosphorIconsFill.chartBar,
                  color: SeeUColors.accent, size: 20),
              const SizedBox(width: 8),
              Text('Опрос',
                  style: SeeUTypography.body
                      .copyWith(fontWeight: FontWeight.w800, fontSize: 16)),
              const Spacer(),
              if (widget.initial != null)
                GestureDetector(
                  onTap: () => Navigator.pop(context, 'delete'),
                  child: Text('Удалить',
                      style: TextStyle(
                          color: SeeUColors.error, fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Вопрос', style: SeeUTypography.micro.copyWith(color: c.ink3)),
          const SizedBox(height: 6),
          _inputField(_questionCtrl, 'Например: Что выберете?'),
          const SizedBox(height: 14),
          Text('Варианты', style: SeeUTypography.micro.copyWith(color: c.ink3)),
          const SizedBox(height: 6),
          _inputField(_optACtrl, 'Вариант А'),
          const SizedBox(height: 8),
          _inputField(_optBCtrl, 'Вариант Б',
              action: TextInputAction.done),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: _save,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [SeeUColors.accentSecondary, SeeUColors.accent],
                  ),
                  borderRadius: BorderRadius.circular(SeeURadii.medium),
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.initial != null ? 'Сохранить опрос' : 'Добавить опрос',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Poll option bar ───────────────────────────────────────────────────────

class _PollOptionBar extends StatelessWidget {
  final String label;
  final double percent;
  final bool accent;
  const _PollOptionBar(
      {required this.label, required this.percent, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withValues(alpha: 0.12),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: percent / 100,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: accent
                    ? SeeUColors.accent.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.18),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Publish state machine ─────────────────────────────────────────────────

enum _PublishState { idle, preparing, uploading, processing, success, failed }

// ── Two-step edit flow ────────────────────────────────────────────────────
enum _EditStep { edit, details }

// ── Photo enhancement tools ───────────────────────────────────────────────
enum _EnhanceTool { none, brightness, contrast, saturation, warmth }

// ── Crop frame painters ────────────────────────────────────────────────────
//
// Two separate painters driven by two AnimatedOpacity layers in
// _buildCropGuideOverlay():
//
//   _CropCornersPainter  — always faintly visible (15% opacity); bright during
//                          gesture. Shows exact publication boundary.
//   _CropGuidesPainter   — only visible during gesture (0% → 100% → 0%).
//                          Rule-of-thirds + center crosshair.
//
// Clean UI at rest (corners only), rich composition aids during editing.

class _CropCornersPainter extends CustomPainter {
  const _CropCornersPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const double arm   = 24.0;
    const double thick = 2.5;

    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = thick
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;

    // Top-left
    canvas.drawLine(Offset(0, arm), Offset.zero, paint);
    canvas.drawLine(Offset.zero, Offset(arm, 0), paint);
    // Top-right
    canvas.drawLine(Offset(w - arm, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, arm), paint);
    // Bottom-left
    canvas.drawLine(Offset(0, h - arm), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(arm, h), paint);
    // Bottom-right
    canvas.drawLine(Offset(w - arm, h), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h - arm), Offset(w, h), paint);
  }

  @override
  bool shouldRepaint(_CropCornersPainter old) => false;
}

class _CropGuidesPainter extends CustomPainter {
  const _CropGuidesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Rule-of-thirds grid
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.13)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(w / 3, 0), Offset(w / 3, h), gridPaint);
    canvas.drawLine(Offset(w * 2 / 3, 0), Offset(w * 2 / 3, h), gridPaint);
    canvas.drawLine(Offset(0, h / 3), Offset(w, h / 3), gridPaint);
    canvas.drawLine(Offset(0, h * 2 / 3), Offset(w, h * 2 / 3), gridPaint);

    // Center crosshair
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1.0;
    const double crossArm = 18.0;
    canvas.drawLine(
      Offset(w / 2 - crossArm, h / 2),
      Offset(w / 2 + crossArm, h / 2),
      crossPaint,
    );
    canvas.drawLine(
      Offset(w / 2, h / 2 - crossArm),
      Offset(w / 2, h / 2 + crossArm),
      crossPaint,
    );
  }

  @override
  bool shouldRepaint(_CropGuidesPainter old) => false;
}

// ── Glass square button (top bar) ──────────────────────────────────────────
//
// Стеклянный квадрат по рецепту «стекло над медиа»: blur 18 + градиент
// white→black + тонкий светлый бордюр.

class _GlassSquareButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double? width;
  final EdgeInsetsGeometry? padding;

  const _GlassSquareButton({
    required this.child,
    this.onTap,
    this.width = 44,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SeeURadii.small),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: width,
            height: 44,
            padding: padding,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.14),
                  Colors.black.withValues(alpha: 0.28),
                ],
              ),
              borderRadius: BorderRadius.circular(SeeURadii.small),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18), width: 0.8),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── Music picker bottom sheet ──────────────────────────────────────────────
