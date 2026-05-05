import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:video_player/video_player.dart';
import '../../core/design/design.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/providers/feed_provider.dart';

/// Intermediate screen shown after camera capture or gallery pick.
/// Allows user to:
/// 1. Preview media in story (9:16) and post (1:1 / 4:5) formats
/// 2. Choose to publish as Story or Post
/// 3. Add caption, location, tags (for Post)
/// 4. Crop / adjust framing
class MediaPrepareScreen extends ConsumerStatefulWidget {
  final File file;
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
  // 0 = Story, 1 = Post
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

  // Video preview
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _videoCtrl = VideoPlayerController.file(widget.file)
        ..setLooping(true)
        ..initialize().then((_) {
          if (mounted) {
            setState(() => _videoReady = true);
            _videoCtrl!.play();
          }
        });
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
      // Auth
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      final token = await storage.read(key: 'access_token');
      final dio = Dio();
      if (token != null && token.isNotEmpty) {
        dio.options.headers['Authorization'] = 'Bearer $token';
      }

      // Upload file
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(widget.file.path),
      });
      final uploadResp = await dio.post(
        '${ApiEndpoints.baseUrl}${ApiEndpoints.mediaUpload}',
        data: formData,
      );
      final mediaUrl = uploadResp.data['data']['url'] as String;
      final mediaType = widget.isVideo ? 'video' : 'image';

      if (_publishMode == 0) {
        // ── Story ──
        await dio.post(
          '${ApiEndpoints.baseUrl}${ApiEndpoints.stories}',
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
        // ── Post ──
        final captionParts = <String>[];
        if (_captionCtrl.text.trim().isNotEmpty) {
          captionParts.add(_captionCtrl.text.trim());
        }
        if (_tags.isNotEmpty) {
          captionParts.add(_tags.map((t) => '#$t').join(' '));
        }

        await dio.post(
          '${ApiEndpoints.baseUrl}${ApiEndpoints.posts}',
          data: {
            'caption': captionParts.isNotEmpty ? captionParts.join('\n\n') : '',
            'media_urls': [mediaUrl],
            'media_types': [mediaType],
            'location': _locationCtrl.text.trim(),
          },
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
      if (mounted) {
        setState(() => _isPublishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
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
            _publishMode == 0 ? 'Новая история' : 'Новый пост',
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
            _modeTab('Пост', 1, c),
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
                    : Image.file(widget.file, fit: BoxFit.cover),
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
                    _publishMode == 0 ? 'Опубликовать историю' : 'Опубликовать пост',
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
