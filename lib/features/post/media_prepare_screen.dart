import 'dart:io' show File;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:video_player/video_player.dart';
import '../../core/design/design.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/models/story.dart';
import '../../core/providers/feed_provider.dart';
import '../../core/providers/post_compose_provider.dart';
import 'ai_caption_sheet.dart';
import 'ai_stylize_sheet.dart';
import '../stories/story_editor_screen.dart';
import 'widgets/music_picker_sheet.dart';

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
  /// Pre-loaded bytes (e.g. from camera + editor). Skips re-reading the file.
  final Uint8List? preloadedBytes;

  const MediaPrepareScreen({
    super.key,
    required this.file,
    required this.isVideo,
    this.initialPublishMode,
    this.preselectedTrack,
    this.preloadedBytes,
  });

  @override
  ConsumerState<MediaPrepareScreen> createState() => _MediaPrepareScreenState();
}

class _MediaPrepareScreenState extends ConsumerState<MediaPrepareScreen>
    with SingleTickerProviderStateMixin {
  // 0 = Story, 1 = Post
  int _publishMode = 1;
  bool _publishSuccess = false;

  // Post aspect ratio: 0 = original, 1 = 1:1, 2 = 4:5
  int _aspectIdx = 0;
  static const _aspects = [null, 1.0, 4.0 / 5.0];
  static const _aspectLabels = ['Ориг.', '1:1', '4:5'];

  // Post form
  final _captionCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final List<String> _tags = [];
  bool _isPublishing = false;
  AudioTrack? _selectedTrack;
  double _audioStartSec = 0; // start of selected audio segment

  // Video preview
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

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
    // Apply params passed from camera screen
    _publishMode = widget.initialPublishMode ?? 1;
    if (widget.preselectedTrack != null) {
      _selectedTrack = widget.preselectedTrack;
    }
    // Use preloaded bytes if provided (avoids re-reading file)
    if (widget.preloadedBytes != null) {
      _bytes = widget.preloadedBytes;
    } else {
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
            setState(() => _videoReady = true);
            _videoCtrl!.play();
          }
        }).catchError((e) {
          debugPrint('media_prepare video init: $e');
        });
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
    _videoCtrl?.dispose();
    super.dispose();
  }

  void _addTag() {
    final raw = _tagCtrl.text.trim().replaceAll('#', '');
    if (raw.isEmpty) return;
    if (!_tags.contains(raw)) setState(() => _tags.add(raw));
    _tagCtrl.clear();
  }

  // ── Publish ────────────────────────────────────────────────────────────

  Future<void> _publish() async {
    if (_isPublishing) return;
    setState(() => _isPublishing = true);

    try {
      final api = ref.read(apiClientProvider);

      // 1. Upload media file (works on web и mobile). Video uploads can be
      // large — bump sendTimeout to 120s for this single call (apiClient's
      // global default is 30s, which is fine for everything else).
      final bytes = _bytes ?? await widget.file.readAsBytes();
      final uploadName = _stylizedFilename ?? widget.file.name;
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: uploadName),
      });
      final uploadResp = await api.post(
        ApiEndpoints.mediaUpload,
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 120),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final mediaUrl = uploadResp.data['data']['url'] as String;
      final mediaType = widget.isVideo ? 'video' : 'image';

      if (_publishMode == 0) {
        // 2a. Create Story — для photo-story можно прокинуть audio_track_id
        // (Spotify-style музыка поверх). Для video — звук в самом видео,
        // audio_track опускаем чтобы не дублировать.
        final storyData = <String, dynamic>{
          'media_url': mediaUrl,
          'media_type': mediaType,
        };
        if (_selectedTrack != null && !widget.isVideo) {
          storyData['audio_track_id'] = _selectedTrack!.id;
          // MUSIC-7: offset playback'а в viewer'е.
          if (_audioStartSec > 0) {
            storyData['audio_start_seconds'] = _audioStartSec.toInt();
          }
        }
        // STORY-3: interactive poll если был добавлен в редакторе.
        if (_pendingPoll != null) {
          storyData['poll'] = _pendingPoll!.toJson();
        }
        await api.post(ApiEndpoints.stories, data: storyData);
        if (mounted) {
          setState(() => _publishSuccess = true);
          await Future.delayed(const Duration(milliseconds: 700));
          if (mounted) context.go('/feed');
        }
      } else {
        // Create Post — every publication is a unified post now (photo,
        // multi-photo, or video). Audio track may overlay a video.
        final captionParts = <String>[];
        if (_captionCtrl.text.trim().isNotEmpty) {
          captionParts.add(_captionCtrl.text.trim());
        }
        if (_tags.isNotEmpty) {
          captionParts.add(_tags.map((t) => '#$t').join(' '));
        }

        final postData = <String, dynamic>{
          'caption': captionParts.isNotEmpty ? captionParts.join('\n\n') : '',
          'media_urls': [mediaUrl],
          'media_types': [mediaType],
          if (_selectedTrack != null && widget.isVideo)
            'audio_track_id': _selectedTrack!.id,
        };
        final loc = _locationCtrl.text.trim();
        if (loc.isNotEmpty) postData['location'] = loc;

        await api.post(
          ApiEndpoints.posts,
          data: postData,
        );
        if (mounted) {
          ref.read(feedProvider.notifier).refresh();
          setState(() => _publishSuccess = true);
          await Future.delayed(const Duration(milliseconds: 700));
          if (mounted) context.go('/feed');
        }
      }
    } catch (e) {
      debugPrint('Publish error: $e');
      if (mounted) {
        setState(() => _isPublishing = false);
        String msg = 'Не удалось опубликовать';
        if (e is DioException && e.response != null) {
          final data = e.response?.data;
          if (data is Map && data['error'] != null) {
            msg = data['error'].toString();
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: SeeUColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(c),
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPreview(c),
                    _buildActionRow(c),
                    if (_selectedTrack != null) _buildMusicTrimCard(c),
                    if (_publishMode == 1) _buildPostForm(c),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            _buildPublishButton(c),
          ],
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────

  Widget _buildTopBar(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          // Back
          IconButton(
            icon: Icon(PhosphorIcons.arrowLeft(), color: c.ink, size: 22),
            onPressed: () => Navigator.of(context).pop(),
          ),
          // Inline mode tabs (центр)
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _inlineModeTab('История', 0, c),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('·',
                      style: TextStyle(
                          color: c.ink3,
                          fontSize: 18,
                          fontWeight: FontWeight.w300)),
                ),
                _inlineModeTab('Публикация', 1, c),
              ],
            ),
          ),
          // Music quick-add button (top right)
          GestureDetector(
            onTap: _openMusicPicker,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _selectedTrack != null
                    ? SeeUColors.accent.withValues(alpha: 0.12)
                    : c.surface2,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _selectedTrack != null
                      ? SeeUColors.accent.withValues(alpha: 0.4)
                      : c.line,
                ),
              ),
              child: Icon(
                _selectedTrack != null
                    ? PhosphorIconsFill.musicNote
                    : PhosphorIcons.musicNote(),
                color: _selectedTrack != null ? SeeUColors.accent : c.ink3,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inlineModeTab(String label, int idx, SeeUThemeColors c) {
    final active = _publishMode == idx;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _publishMode = idx);
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: SeeUTypography.body.copyWith(
              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              fontSize: active ? 15 : 14,
              color: active ? c.ink : c.ink3,
            ),
            child: Text(label),
          ),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            height: 2,
            width: active ? 22 : 0,
            decoration: BoxDecoration(
              color: SeeUColors.accent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }

  // ── Preview ────────────────────────────────────────────────────────────

  Widget _buildPreview(SeeUThemeColors c) {
    // Story = 9:16 preview, Post = aspect ratio options
    final double previewAspect;
    if (_publishMode == 0) {
      previewAspect = 9.0 / 16.0;
    } else {
      final a = _aspects[_aspectIdx];
      if (a != null) {
        previewAspect = a;
      } else {
        // Original aspect
        if (widget.isVideo && _videoCtrl != null && _videoReady) {
          previewAspect = _videoCtrl!.value.aspectRatio;
        } else {
          previewAspect = 4.0 / 5.0; // fallback
        }
      }
    }

    return Column(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: previewAspect,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: widget.isVideo
                      ? GestureDetector(
                          onTap: () {
                            if (_videoCtrl == null || !_videoReady) return;
                            setState(() {
                              _videoCtrl!.value.isPlaying
                                  ? _videoCtrl!.pause()
                                  : _videoCtrl!.play();
                            });
                          },
                          child: _videoReady && _videoCtrl != null
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    FittedBox(
                                      fit: BoxFit.cover,
                                      child: SizedBox(
                                        width: _videoCtrl!.value.size.width,
                                        height: _videoCtrl!.value.size.height,
                                        child: VideoPlayer(_videoCtrl!),
                                      ),
                                    ),
                                    if (!(_videoCtrl!.value.isPlaying))
                                      const Center(
                                        child: Icon(PhosphorIconsFill.play,
                                            color: Colors.white70, size: 40),
                                      ),
                                  ],
                                )
                              : Container(
                                  color: Colors.black,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white24, strokeWidth: 2,
                                    ),
                                  ),
                                ),
                        )
                      : InteractiveViewer(
                          minScale: 1.0,
                          maxScale: 4.0,
                          child: _bytes != null
                              ? Image.memory(_bytes!, fit: BoxFit.cover)
                              : Container(color: Colors.black),
                        ),
                ),

                // Music pill overlay on preview
                if (_selectedTrack != null)
                  Positioned(
                    bottom: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.60),
                        borderRadius: BorderRadius.circular(SeeURadii.pill),
                        border: Border.all(
                          color:
                              SeeUColors.accent.withValues(alpha: 0.45),
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
                            constraints:
                                const BoxConstraints(maxWidth: 110),
                            child: Text(
                              _selectedTrack!.title,
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

                // Publish mode badge (top left of preview)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(SeeURadii.pill),
                    ),
                    child: Text(
                      _publishMode == 0 ? 'ИСТОРИЯ' : 'ПОСТ',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  /// Открывает Story Editor с текущими bytes. На успех заменяет _bytes на
  /// composite PNG и помечает «edited_….png» имя файла для backend upload'а.
  /// STORY-3: если в редакторе добавлен interactive poll, сохраняем его
  /// в `_pendingPoll` чтобы отправить в body стори при публикации.
  Future<void> _openStoryEditor() async {
    if (_bytes == null) return;
    HapticFeedback.mediumImpact();
    final result = await Navigator.of(context).push<StoryEditorResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryEditorScreen(initialBytes: _bytes!),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _bytes = result.bytes;
      _stylizedFilename =
          'edited_${DateTime.now().millisecondsSinceEpoch}.png';
      _pendingPoll = result.poll;
    });
  }

  /// Открыть AI-стилизация sheet. На успех — заменяет preview-bytes
  /// результатом + меняет `widget.file.name` через локальное состояние
  /// (`_stylizedFilename`), чтобы upload при публикации использовал
  /// сгенерированный image.
  Future<void> _openStylizeSheet() async {
    if (_bytes == null) return;
    HapticFeedback.mediumImpact();
    final result = await showAIStylizeSheet(
      context: context,
      sourceBytes: _bytes!,
      sourceFilename: widget.file.name,
    );
    if (result == null || !mounted) return;
    setState(() {
      _bytes = result.bytes;
      _stylizedFilename =
          'stylized_${DateTime.now().millisecondsSinceEpoch}.png';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Кадр стилизован — посмотрите превью'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Открыть AI-caption sheet. Применяем выбранный caption (replace или
  /// append) + добавляем выбранные хэштеги в массив _tags.
  Future<void> _openCaptionSheet() async {
    if (_bytes == null) return;
    HapticFeedback.mediumImpact();
    final picked = await showAICaptionSheet(
      context: context,
      sourceBytes: _bytes!,
      sourceFilename: _stylizedFilename ?? widget.file.name,
    );
    if (picked == null || !mounted) return;
    setState(() {
      // Если у юзера уже что-то написано — добавляем через перенос строки.
      final existing = _captionCtrl.text.trim();
      _captionCtrl.text = existing.isEmpty
          ? picked.caption
          : '$existing\n${picked.caption}';
      _captionCtrl.selection = TextSelection.collapsed(
        offset: _captionCtrl.text.length,
      );
      // Hashtag'и добавляем только новые.
      for (final h in picked.hashtags) {
        if (!_tags.contains(h)) _tags.add(h);
      }
    });
  }

  // ── Action row (AI стиль | Текст | Музыка | Кроп) ─────────────────────

  Widget _buildActionRow(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // PRIMARY: full-width "Add text / stickers" button (photos only)
        if (!widget.isVideo)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: GestureDetector(
              onTap: _bytes == null ? null : _openStoryEditor,
              child: AnimatedOpacity(
                opacity: _bytes == null ? 0.4 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(SeeURadii.medium),
                    border: Border.all(color: c.line),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(PhosphorIconsRegular.smileySticker,
                          size: 18, color: c.ink2),
                      const SizedBox(width: 8),
                      Text(
                        'Добавить текст / стикеры',
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // SECONDARY: icon chips row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (!widget.isVideo) ...[
                _ActionChip(
                  icon: PhosphorIconsBold.sparkle,
                  label: 'AI стиль',
                  color: SeeUColors.accent,
                  onTap: _bytes == null ? null : _openStylizeSheet,
                ),
                const SizedBox(width: 8),
              ],
              _ActionChip(
                icon: _selectedTrack != null
                    ? PhosphorIconsFill.musicNote
                    : PhosphorIconsRegular.musicNote,
                label: _selectedTrack != null ? _selectedTrack!.title : 'Музыка',
                color: _selectedTrack != null ? SeeUColors.accent : c.ink2,
                maxLabelWidth: 80,
                onTap: _openMusicPicker,
              ),
              if (_publishMode == 1) ...[
                const SizedBox(width: 8),
                _ActionChip(
                  icon: PhosphorIconsRegular.crop,
                  label: _aspectLabels[_aspectIdx],
                  color: c.ink2,
                  onTap: () {
                    setState(() => _aspectIdx =
                        (_aspectIdx + 1) % _aspectLabels.length);
                  },
                ),
              ],
            ],
          ),
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
              _buildAudioTrimSlider(c),
          ],
        ),
      ),
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

  String _fmtSec(double s) {
    final m = s ~/ 60;
    final sec = (s % 60).toInt();
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  Widget _buildAudioTrimSlider(SeeUThemeColors c) {
    final track = _selectedTrack!;
    final totalDur = track.durationSeconds.toDouble();
    if (totalDur <= 0) return const SizedBox.shrink();

    final clipDur = _clipDuration.clamp(1.0, totalDur);
    final maxStart = (totalDur - clipDur).clamp(0.0, totalDur);
    final endSec = (_audioStartSec + clipDur).clamp(0.0, totalDur);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          // Visual trim bar
          SizedBox(
            height: 40,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final leftFrac = maxStart > 0 ? _audioStartSec / totalDur : 0.0;
                final widthFrac = clipDur / totalDur;

                return GestureDetector(
                  onHorizontalDragUpdate: (d) {
                    if (maxStart <= 0) return;
                    final delta = d.delta.dx / w * totalDur;
                    setState(() {
                      _audioStartSec = (_audioStartSec + delta).clamp(0.0, maxStart);
                    });
                  },
                  child: Stack(
                    children: [
                      // Background bar (full track)
                      Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        // Fake waveform bars
                        child: CustomPaint(
                          painter: MusicWaveformPainter(
                            color: c.ink3.withValues(alpha: 0.3),
                            barCount: 60,
                          ),
                          size: Size(w, 40),
                        ),
                      ),
                      // Selected range highlight
                      Positioned(
                        left: leftFrac * w,
                        width: widthFrac * w,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: SeeUColors.accent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: SeeUColors.accent,
                              width: 2,
                            ),
                          ),
                          // Active waveform
                          child: CustomPaint(
                            painter: MusicWaveformPainter(
                              color: SeeUColors.accent.withValues(alpha: 0.6),
                              barCount: (60 * widthFrac).round().clamp(5, 60),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          // Time labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _fmtSec(_audioStartSec),
                style: SeeUTypography.micro.copyWith(
                  color: SeeUColors.accent, fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Выбрано ${clipDur.toInt()} сек',
                style: SeeUTypography.micro.copyWith(color: c.ink3),
              ),
              Text(
                _fmtSec(endSec),
                style: SeeUTypography.micro.copyWith(
                  color: SeeUColors.accent, fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openMusicPicker() {
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
    );
  }

  // ── Post form (caption, location, tags) ────────────────────────────────

  Widget _buildPostForm(SeeUThemeColors c) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            // Caption + AI button
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _captionCtrl,
                    maxLines: 2,
                    maxLength: 2000,
                    style: SeeUTypography.body.copyWith(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Что происходит?',
                      hintStyle: SeeUTypography.body.copyWith(
                        fontSize: 14,
                        color: c.ink3,
                      ),
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
                if (!widget.isVideo)
                  GestureDetector(
                    onTap: _bytes == null ? null : _openCaptionSheet,
                    child: Container(
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.only(left: 6, top: 4),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SeeUGradients.heroOrange,
                      ),
                      child: Icon(
                        PhosphorIconsBold.sparkle,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),

            // Location
            Row(
              children: [
                Icon(PhosphorIcons.mapPin(), size: 16, color: c.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _locationCtrl,
                    style: SeeUTypography.body.copyWith(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Добавить место',
                      hintStyle: SeeUTypography.caption.copyWith(
                          color: c.ink3, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Tags
            Row(
              children: [
                Icon(PhosphorIcons.hash(), size: 16, color: c.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _tagCtrl,
                    style: SeeUTypography.body.copyWith(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Добавить теги',
                      hintStyle: SeeUTypography.caption.copyWith(
                          color: c.ink3, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                if (_tagCtrl.text.trim().isNotEmpty)
                  GestureDetector(
                    onTap: _addTag,
                    child: Icon(PhosphorIcons.plus(), size: 18, color: SeeUColors.accent),
                  ),
              ],
            ),
            if (_tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _tags.map((t) {
                    return Chip(
                      label: Text('#$t', style: SeeUTypography.caption.copyWith(fontSize: 12)),
                      deleteIcon: const Icon(PhosphorIconsRegular.x, size: 14),
                      onDeleted: () => setState(() => _tags.remove(t)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Publish button ─────────────────────────────────────────────────────

  Widget _buildPublishButton(SeeUThemeColors c) {
    final Widget buttonChild;
    final BoxDecoration buttonDecoration;

    if (_publishSuccess) {
      // S6.7: brief green success flash
      buttonChild = const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsBold.checkCircle, color: Colors.white, size: 22),
          SizedBox(width: 8),
          Text(
            'Опубликовано!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
      buttonDecoration = BoxDecoration(
        color: SeeUColors.success,
        borderRadius: BorderRadius.circular(SeeURadii.pill),
        boxShadow: [
          BoxShadow(
            color: SeeUColors.success.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      );
    } else if (_isPublishing) {
      buttonChild = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _publishMode == 0 ? 'Публикуем историю...' : 'Публикуем...',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
      buttonDecoration = BoxDecoration(
        color: SeeUColors.accent.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(SeeURadii.pill),
      );
    } else {
      buttonChild = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _publishMode == 0 ? 'Опубликовать историю' : 'Опубликовать',
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
      );
      buttonDecoration = BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [SeeUColors.accentSecondary, SeeUColors.accent],
        ),
        borderRadius: BorderRadius.circular(SeeURadii.pill),
        boxShadow: [
          BoxShadow(
            color: SeeUColors.accent.withValues(alpha: 0.38),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: GestureDetector(
        onTap: (_isPublishing || _publishSuccess) ? null : _publish,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          height: 54,
          decoration: buttonDecoration,
          alignment: Alignment.center,
          child: buttonChild,
        ),
      ),
    );
  }
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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

// ── Music picker bottom sheet ──────────────────────────────────────────────
