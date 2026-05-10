import 'dart:io' show File;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/design/design.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/providers/feed_provider.dart';
import '../../core/providers/post_compose_provider.dart';
import '../../core/providers/user_provider.dart';

/// Intermediate screen shown after camera capture or gallery pick.
/// Allows user to:
/// 1. Preview media in story (9:16) and post (1:1 / 4:5) formats
/// 2. Choose to publish as Story or Post
/// 3. Add caption, location, tags (for Post)
/// 4. Crop / adjust framing
class MediaPrepareScreen extends ConsumerStatefulWidget {
  final XFile file;
  final bool isVideo;

  const MediaPrepareScreen({
    super.key,
    required this.file,
    required this.isVideo,
  });

  @override
  ConsumerState<MediaPrepareScreen> createState() => _MediaPrepareScreenState();
}

class _MediaPrepareScreenState extends ConsumerState<MediaPrepareScreen>
    with SingleTickerProviderStateMixin {
  // 0 = Story, 1 = Post (any media: photo, multi-photo, video). Reels are
  // gone — every publication is a "rils" in the unified product model.
  int _publishMode = 1;

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

  @override
  void initState() {
    super.initState();
    _loadBytes();

    // Pick up preselected track from Music screen ("Использовать в посте"),
    // if any. Doing this in postFrame because StateProvider mutation outside
    // of a Riverpod-aware build phase warns in debug.
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
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: widget.file.name),
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
        // 2a. Create Story
        await api.post(
          ApiEndpoints.stories,
          data: {
            'media_url': mediaUrl,
            'media_type': mediaType,
          },
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Стори опубликована!'),
              backgroundColor: Color(0xFF4CAF50),
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.go('/feed');
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Пост опубликован!',
                  style: SeeUTypography.body.copyWith(color: Colors.white)),
              backgroundColor: SeeUColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.go('/feed');
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
            _buildModeToggle(c),
            Expanded(child: _buildPreview(c)),
            _buildMusicButton(c),
            if (_publishMode == 1) _buildPostForm(c),
            _buildPublishButton(c),
          ],
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────

  Widget _buildTopBar(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(PhosphorIcons.arrowLeft(), color: c.ink, size: 22),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          Text(
            _publishMode == 0 ? 'Новая история' : 'Новая публикация',
            style: SeeUTypography.subtitle,
          ),
          const Spacer(),
          const SizedBox(width: 48), // balance
        ],
      ),
    );
  }

  // ── Mode toggle (Story / Post) ─────────────────────────────────────────

  Widget _buildModeToggle(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
        ),
        child: Row(
          children: [
            _modeTab('История', 0, c),
            _modeTab('Публикация', 1, c),
          ],
        ),
      ),
    );
  }

  Widget _modeTab(String label, int idx, SeeUThemeColors c) {
    final active = _publishMode == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _publishMode = idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: active ? SeeUColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(SeeURadii.pill),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: SeeUTypography.caption.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : c.ink2,
            ),
          ),
        ),
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
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: previewAspect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: widget.isVideo
                    ? (_videoReady && _videoCtrl != null
                        ? FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _videoCtrl!.value.size.width,
                              height: _videoCtrl!.value.size.height,
                              child: VideoPlayer(_videoCtrl!),
                            ),
                          )
                        : Container(
                            color: Colors.black,
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white24, strokeWidth: 2,
                              ),
                            ),
                          ))
                    : (_bytes != null
                        ? Image.memory(_bytes!, fit: BoxFit.cover)
                        : Container(color: Colors.black)),
              ),
            ),
          ),
        ),

        // Aspect ratio selector (Post mode only)
        if (_publishMode == 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_aspectLabels.length, (i) {
                final active = _aspectIdx == i;
                return GestureDetector(
                  onTap: () => setState(() => _aspectIdx = i),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? c.ink : c.surface2,
                      borderRadius: BorderRadius.circular(SeeURadii.pill),
                    ),
                    child: Text(
                      _aspectLabels[i],
                      style: SeeUTypography.caption.copyWith(
                        color: active ? Colors.white : c.ink2,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
      ],
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

  Widget _buildMusicButton(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          // Track selector row
          GestureDetector(
            onTap: _openMusicPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(SeeURadii.pill),
                border: Border.all(
                  color: _selectedTrack != null
                      ? SeeUColors.accent.withValues(alpha: 0.4)
                      : c.line,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    PhosphorIcons.musicNotes(),
                    size: 18,
                    color: _selectedTrack != null ? SeeUColors.accent : c.ink3,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _selectedTrack != null
                        ? Column(
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
                          )
                        : Text(
                            'Добавить музыку',
                            style: SeeUTypography.body.copyWith(
                              fontSize: 14,
                              color: c.ink3,
                            ),
                          ),
                  ),
                  if (_selectedTrack != null)
                    GestureDetector(
                      onTap: () => setState(() {
                        _selectedTrack = null;
                        _audioStartSec = 0;
                      }),
                      child: Icon(PhosphorIcons.x(), size: 16, color: c.ink3),
                    )
                  else
                    Icon(PhosphorIcons.caretRight(), size: 16, color: c.ink3),
                ],
              ),
            ),
          ),

          // Audio trim slider (shown when track selected)
          if (_selectedTrack != null) _buildAudioTrimSlider(c),
        ],
      ),
    );
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
                          painter: _WaveformPainter(
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
                            painter: _WaveformPainter(
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
      builder: (_) => _MusicPickerSheet(
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
            // Caption
            TextField(
              controller: _captionCtrl,
              maxLines: 2,
              maxLength: 2000,
              style: SeeUTypography.body.copyWith(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Добавьте описание...',
                hintStyle: SeeUTypography.body.copyWith(
                  fontSize: 14, color: c.ink3,
                ),
                border: InputBorder.none,
                counterText: '',
              ),
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
                      deleteIcon: const Icon(Icons.close, size: 14),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: GestureDetector(
          onTap: _isPublishing ? null : _publish,
          child: Container(
            decoration: BoxDecoration(
              color: _isPublishing
                  ? SeeUColors.accent.withValues(alpha: 0.5)
                  : SeeUColors.accent,
              borderRadius: BorderRadius.circular(SeeURadii.pill),
            ),
            alignment: Alignment.center,
            child: _isPublishing
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5,
                    ),
                  )
                : Text(
                    _publishMode == 0
                        ? 'Опубликовать историю'
                        : 'Опубликовать',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Music picker bottom sheet ──────────────────────────────────────────────

class _MusicPickerSheet extends ConsumerStatefulWidget {
  final ValueChanged<AudioTrack> onSelect;
  const _MusicPickerSheet({required this.onSelect});

  @override
  ConsumerState<_MusicPickerSheet> createState() => _MusicPickerSheetState();
}

class _MusicPickerSheetState extends ConsumerState<_MusicPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<AudioTrack>? _filtered;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _fmtDuration(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  String _fmtUses(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}М';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}К';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final tracksAsync = ref.watch(audioTracksProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('Выберите музыку', style: SeeUTypography.subtitle),
          const SizedBox(height: 10),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(SeeURadii.pill),
              ),
              child: Row(
                children: [
                  Icon(PhosphorIcons.magnifyingGlass(), size: 16, color: c.ink3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: SeeUTypography.body.copyWith(fontSize: 13),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Найти трек...',
                        hintStyle: SeeUTypography.body.copyWith(
                          fontSize: 13, color: c.ink3,
                        ),
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      onChanged: (q) {
                        final tracks = tracksAsync.valueOrNull ?? [];
                        if (q.trim().isEmpty) {
                          setState(() => _filtered = null);
                        } else {
                          final lq = q.toLowerCase();
                          setState(() {
                            _filtered = tracks
                                .where((t) =>
                                    t.title.toLowerCase().contains(lq) ||
                                    t.artist.toLowerCase().contains(lq))
                                .toList();
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Track list
          Expanded(
            child: tracksAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: SeeUColors.accent),
              ),
              error: (_, __) => Center(
                child: Text('Ошибка загрузки',
                    style: SeeUTypography.body.copyWith(color: c.ink3)),
              ),
              data: (allTracks) {
                final tracks = _filtered ?? allTracks;
                if (tracks.isEmpty) {
                  return Center(
                    child: Text('Ничего не найдено',
                        style: SeeUTypography.body.copyWith(color: c.ink3)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: tracks.length,
                  itemBuilder: (_, i) => _buildTrackTile(tracks[i], c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackTile(AudioTrack track, SeeUThemeColors c) {
    return GestureDetector(
      onTap: () => widget.onSelect(track),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(SeeURadii.medium),
          ),
          child: Row(
            children: [
              // Cover
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 46, height: 46,
                  child: track.coverUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: track.coverUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: c.line,
                            child: Icon(PhosphorIcons.musicNotes(),
                                color: c.ink3, size: 20),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: c.line,
                            child: Icon(PhosphorIcons.musicNotes(),
                                color: c.ink3, size: 20),
                          ),
                        )
                      : Container(
                          color: c.line,
                          child: Icon(PhosphorIcons.musicNotes(),
                              color: c.ink3, size: 20),
                        ),
                ),
              ),
              const SizedBox(width: 10),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: SeeUTypography.subtitle.copyWith(
                        fontWeight: FontWeight.w600, fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${track.artist}  ·  ${_fmtDuration(track.durationSeconds)}',
                      style: SeeUTypography.caption.copyWith(
                        color: c.ink3, fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              // Uses count
              Column(
                children: [
                  Icon(PhosphorIcons.play(PhosphorIconsStyle.fill),
                      size: 12, color: c.ink3),
                  const SizedBox(height: 2),
                  Text(
                    _fmtUses(track.usesCount),
                    style: SeeUTypography.micro.copyWith(
                      color: c.ink3, fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Waveform painter (decorative bars) ─────────────────────────────────────

class _WaveformPainter extends CustomPainter {
  final Color color;
  final int barCount;

  _WaveformPainter({required this.color, this.barCount = 60});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round;
    final barW = 2.0;
    final gap = (size.width - barCount * barW) / (barCount + 1);
    // Deterministic pseudo-random heights
    for (int i = 0; i < barCount; i++) {
      final seed = (i * 7 + 3) % 13;
      final h = size.height * (0.2 + 0.6 * (seed / 13.0));
      final x = gap + i * (barW + gap) + barW / 2;
      final top = (size.height - h) / 2;
      paint.strokeWidth = barW;
      canvas.drawLine(Offset(x, top), Offset(x, top + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.color != color || old.barCount != barCount;
}
