// Cross-platform create-post screen.
//
// Avoids `dart:io.File` and `MultipartFile.fromFile` because those don't work
// on Flutter Web (XFile.path is a `blob:` URL with no underlying file). Instead
// we read bytes once via `xfile.readAsBytes()` and use `Image.memory` for
// preview and `MultipartFile.fromBytes` for upload — works on web and mobile.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/feed_provider.dart';

class _PickedMedia {
  final XFile xfile;
  final Uint8List bytes;
  final bool isVideo;

  _PickedMedia({
    required this.xfile,
    required this.bytes,
    required this.isVideo,
  });

  String get name => xfile.name;
  String get mediaType => isVideo ? 'video' : 'image';
}

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _captionCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final _captionFocus = FocusNode();
  final _locationFocus = FocusNode();

  final List<_PickedMedia> _media = [];
  bool _isPosting = false;
  final List<String> _tags = [];
  final ImagePicker _picker = ImagePicker();

  static const int _maxCaption = 2000;

  static const List<String> _emojis = [
    '😊', '🔥', '❤️', '✨', '🎉', '👏', '💪', '🌟',
  ];

  /// Форматы превью: подпись → соотношение сторон. Дефолт — 4:5.
  static const List<(String, double)> _formats = [
    ('1:1', 1.0),
    ('4:5', 4 / 5),
    ('9:16', 9 / 16),
  ];
  double _previewAspect = 4 / 5;

  @override
  void initState() {
    super.initState();
    _captionCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _locationCtrl.dispose();
    _tagCtrl.dispose();
    _captionFocus.dispose();
    _locationFocus.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage();
    if (picked.isEmpty) return;
    final loaded = <_PickedMedia>[];
    for (final x in picked) {
      try {
        final bytes = await x.readAsBytes();
        loaded.add(_PickedMedia(xfile: x, bytes: bytes, isVideo: false));
      } catch (e) {
        debugPrint('readAsBytes failed for ${x.name}: $e');
      }
    }
    if (!mounted) return;
    setState(() => _media.addAll(loaded));
  }

  Future<void> _pickVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    try {
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() {
        _media.add(_PickedMedia(xfile: x, bytes: bytes, isVideo: true));
      });
    } catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Не удалось открыть видео: $e',
          tone: SeeUTone.danger);
    }
  }

  void _addTag() {
    final raw = _tagCtrl.text.trim().replaceAll('#', '');
    if (raw.isEmpty) return;
    final tag = '#$raw';
    if (!_tags.contains(tag)) {
      setState(() => _tags.add(tag));
    }
    _tagCtrl.clear();
  }

  void _removeTag(String tag) => setState(() => _tags.remove(tag));

  Future<void> _publish() async {
    if (_media.isEmpty) return;
    setState(() => _isPosting = true);
    try {
      final captionParts = <String>[];
      if (_captionCtrl.text.trim().isNotEmpty) {
        captionParts.add(_captionCtrl.text.trim());
      }
      if (_tags.isNotEmpty) {
        captionParts.add(_tags.join(' '));
      }

      final api = ref.read(apiClientProvider);

      // Upload all media in parallel for speed.
      final uploadFutures = _media.map((m) async {
        final form = FormData.fromMap({
          'file': MultipartFile.fromBytes(m.bytes, filename: m.name),
        });
        final resp = await api.post(ApiEndpoints.mediaUpload, data: form);
        final data = resp.data is Map && resp.data.containsKey('data')
            ? resp.data['data']
            : resp.data;
        return data['url'] as String;
      });
      final mediaUrls = await Future.wait(uploadFutures);

      await api.post(ApiEndpoints.posts, data: {
        'caption': captionParts.isNotEmpty ? captionParts.join('\n\n') : '',
        'media_urls': mediaUrls,
        'media_types': _media.map((m) => m.mediaType).toList(),
        'location': _locationCtrl.text.trim(),
      });

      if (!mounted) return;
      ref.read(feedProvider.notifier).refresh();
      showSeeUSnackBar(context, 'Пост опубликован', tone: SeeUTone.success);
      context.go('/feed');
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _isPosting = false);
      showSeeUSnackBar(context, 'Не удалось опубликовать: ${apiErrorMessage(e)}',
          tone: SeeUTone.danger);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPosting = false);
      showSeeUSnackBar(context, 'Ошибка: $e', tone: SeeUTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final canPublish = _media.isNotEmpty && !_isPosting;

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          SeeUGlassBar(
            titleText: 'Новый пост',
            kicker: 'ПУБЛИКАЦИЯ',
            centerTitle: true,
            leading: Tappable.scaled(
              onTap: () => context.pop(),
              scaleFactor: 0.9,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(PhosphorIcons.x(PhosphorIconsStyle.bold),
                    color: c.ink, size: 20),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: canPublish ? _publish : null,
                  child: _isPosting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: SeeUColors.accent,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Опубликовать',
                          style: SeeUTypography.caption.copyWith(
                            color: canPublish ? SeeUColors.accent : c.ink3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
          Expanded(
            child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_media.isNotEmpty) ...[
                _buildFormatRow(),
                _buildPreview(),
              ],
              const SeeUSectionHeader(kicker: 'Медиа', hairline: true),
              const SizedBox(height: 10),
              _buildPickRow(),
              if (_media.isNotEmpty) _buildMediaGrid(),
              const SizedBox(height: 20),
              const SeeUSectionHeader(kicker: 'Описание', hairline: true),
              const SizedBox(height: 10),
              _buildCaptionInput(),
              const SizedBox(height: 4),
              _buildEmojiRow(),
              const SizedBox(height: 20),
              const SeeUSectionHeader(kicker: 'Место', hairline: true),
              const SizedBox(height: 10),
              _buildLocationInput(),
              const SizedBox(height: 20),
              const SeeUSectionHeader(kicker: 'Теги', hairline: true),
              const SizedBox(height: 10),
              _buildTagsInput(),
              if (_tags.isNotEmpty) _buildTagChips(),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SeeUButton(
                  label: 'Опубликовать',
                  onTap: canPublish ? _publish : null,
                  isLoading: _isPosting,
                ),
              ),
            ],
          ),
        ),
      ),
          ),
        ],
      ),
    );
  }

  /// Ряд формат-чипов над превью: 1:1 / 4:5 / 9:16, активный — accent.
  Widget _buildFormatRow() {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: _formats.map((f) {
          final isActive = _previewAspect == f.$2;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tappable.scaled(
              onTap: () => setState(() => _previewAspect = f.$2),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? SeeUColors.accent : c.surface2,
                  borderRadius: BorderRadius.circular(SeeURadii.pill),
                  border: Border.all(
                      color: isActive ? SeeUColors.accent : c.line),
                ),
                child: Text(
                  f.$1,
                  style: SeeUTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.white : c.ink2,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPreview() {
    final c = context.seeuColors;
    final first = _media.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SeeURadii.card),
        // Превью повторяет выбранный формат публикации.
        child: AspectRatio(
          aspectRatio: _previewAspect,
          child: Container(
            color: c.surface2,
            child: first.isVideo
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(PhosphorIcons.filmStrip(PhosphorIconsStyle.bold),
                            size: 48, color: c.ink3),
                        const SizedBox(height: 8),
                        Text(first.name,
                            style: SeeUTypography.caption,
                            textAlign: TextAlign.center),
                      ],
                    ),
                  )
                : Image.memory(first.bytes,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(
                        child: Icon(
                            PhosphorIcons.imageSquare(PhosphorIconsStyle.bold),
                            size: 48,
                            color: c.ink3))),
          ),
        ),
      ),
    );
  }

  /// Плоский чип выбора медиа: surface2 + hairline-бордюр.
  Widget _pickChip({
    required PhosphorIconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(icon, size: 18, color: c.ink2),
            const SizedBox(width: 8),
            Text(label,
                style: SeeUTypography.caption
                    .copyWith(fontWeight: FontWeight.w600, color: c.ink)),
          ],
        ),
      ),
    );
  }

  Widget _buildPickRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: _pickChip(
              icon: PhosphorIcons.images(),
              label: 'Фото',
              onTap: _pickImages,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _pickChip(
              icon: PhosphorIcons.filmStrip(),
              label: 'Видео',
              onTap: _pickVideo,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaGrid() {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _media.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemBuilder: (context, index) {
          final m = _media[index];
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SeeURadii.small),
              border: Border.all(
                color: index == 0 ? SeeUColors.accent : Colors.transparent,
                width: 3,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SeeURadii.small - 2),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (m.isVideo)
                    Container(
                      color: c.surface2,
                      child: Icon(PhosphorIcons.filmStrip(), color: c.ink3, size: 28),
                    )
                  else
                    Image.memory(m.bytes, fit: BoxFit.cover),
                  if (m.isVideo)
                    const Positioned(
                      bottom: 4,
                      left: 4,
                      child: Icon(PhosphorIconsFill.playCircle,
                          color: Colors.white, size: 20),
                    ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => setState(() => _media.removeAt(index)),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(PhosphorIconsRegular.x,
                            color: Colors.white, size: 14),
                      ),
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

  Widget _buildCaptionInput() {
    final c = context.seeuColors;
    final charCount = _captionCtrl.text.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(SeeURadii.medium),
            ),
            child: TextField(
              controller: _captionCtrl,
              focusNode: _captionFocus,
              maxLines: 5,
              minLines: 3,
              maxLength: _maxCaption,
              style: SeeUTypography.body,
              decoration: InputDecoration(
                hintText: 'Расскажите о фото…',
                hintStyle: SeeUTypography.body.copyWith(color: c.ink3),
                border: InputBorder.none,
                filled: false,
                counterText: '',
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 4),
            child: Text(
              '$charCount / $_maxCaption',
              style: SeeUTypography.micro.copyWith(
                color: charCount > _maxCaption * 0.9
                    ? SeeUColors.error
                    : c.ink3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiRow() {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: _emojis.map((emoji) {
            return GestureDetector(
              onTap: () {
                final text = _captionCtrl.text;
                final sel = _captionCtrl.selection;
                final offset = sel.isValid ? sel.baseOffset : text.length;
                final newText =
                    text.substring(0, offset) + emoji + text.substring(offset);
                _captionCtrl.text = newText;
                _captionCtrl.selection =
                    TextSelection.collapsed(offset: offset + emoji.length);
                _captionFocus.requestFocus();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildLocationInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SeeUInput(
        controller: _locationCtrl,
        focusNode: _locationFocus,
        hintText: 'Добавить место',
        prefix: Icon(PhosphorIcons.mapPin(PhosphorIconsStyle.bold),
            color: SeeUColors.textTertiary, size: 20),
      ),
    );
  }

  Widget _buildTagsInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SeeUInput(
        controller: _tagCtrl,
        hintText: 'Добавьте тег и нажмите +',
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _addTag(),
        suffix: GestureDetector(
          onTap: _addTag,
          child: Container(
            margin: const EdgeInsets.all(8),
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: SeeUColors.accent,
              shape: BoxShape.circle,
            ),
            child: const Icon(PhosphorIconsBold.plus, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildTagChips() {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _tags.map((tag) {
          return GestureDetector(
            onTap: () => _removeTag(tag),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(SeeURadii.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tag,
                      style: SeeUTypography.caption.copyWith(
                          color: SeeUColors.accent,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  Icon(PhosphorIcons.x(PhosphorIconsStyle.bold),
                      size: 12, color: SeeUColors.accent),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
