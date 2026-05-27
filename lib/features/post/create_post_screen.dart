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
  bool _locationFocused = false;
  final List<String> _tags = [];
  final ImagePicker _picker = ImagePicker();

  static const int _maxCaption = 2000;

  static const List<String> _emojis = [
    '😊', '🔥', '❤️', '✨', '🎉', '👏', '💪', '🌟',
  ];

  static const List<String> _locationSuggestions = [
    'Алматы', 'Астана', 'Бишкек', 'Ташкент', 'Москва',
  ];

  @override
  void initState() {
    super.initState();
    _locationFocus.addListener(() {
      setState(() => _locationFocused = _locationFocus.hasFocus);
    });
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть видео: $e')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Пост опубликован',
              style: SeeUTypography.body.copyWith(color: Colors.white)),
          backgroundColor: SeeUColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SeeURadii.small)),
        ),
      );
      context.go('/feed');
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _isPosting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось опубликовать: ${apiErrorMessage(e)}'),
          backgroundColor: SeeUColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPosting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e'),
          backgroundColor: SeeUColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final canPublish = _media.isNotEmpty && !_isPosting;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('Новый пост',
            style: SeeUTypography.subtitle
                .copyWith(fontWeight: FontWeight.w700)),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(PhosphorIcons.x(PhosphorIconsStyle.bold), color: c.ink),
          onPressed: () => context.pop(),
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
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_media.isNotEmpty) _buildPreview(),
              _buildSectionHeader(
                  icon: PhosphorIcons.images(PhosphorIconsStyle.bold),
                  title: 'Медиа'),
              _buildPickRow(),
              if (_media.isNotEmpty) _buildMediaGrid(),
              const SizedBox(height: 20),
              _buildSectionHeader(
                  icon: PhosphorIcons.textAa(PhosphorIconsStyle.bold),
                  title: 'Описание'),
              _buildCaptionInput(),
              const SizedBox(height: 4),
              _buildEmojiRow(),
              const SizedBox(height: 20),
              _buildSectionHeader(
                  icon: PhosphorIcons.mapPin(PhosphorIconsStyle.bold),
                  title: 'Место'),
              _buildLocationInput(),
              if (_locationFocused) _buildLocationSuggestions(),
              const SizedBox(height: 20),
              _buildSectionHeader(
                  icon: PhosphorIcons.hash(PhosphorIconsStyle.bold),
                  title: 'Теги'),
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
    );
  }

  Widget _buildPreview() {
    final c = context.seeuColors;
    final first = _media.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SeeURadii.card),
        child: Container(
          height: 280,
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
                  height: 280,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                      child: Icon(
                          PhosphorIcons.imageSquare(PhosphorIconsStyle.bold),
                          size: 48,
                          color: c.ink3))),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
  }) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.ink2),
          const SizedBox(width: 6),
          Text(title,
              style: SeeUTypography.caption.copyWith(
                  fontWeight: FontWeight.w600, color: c.ink2)),
        ],
      ),
    );
  }

  Widget _buildPickRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickImages,
              icon: Icon(PhosphorIcons.images(), size: 18),
              label: const Text('Фото'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickVideo,
              icon: Icon(PhosphorIcons.filmStrip(), size: 18),
              label: const Text('Видео'),
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
              borderRadius: BorderRadius.circular(16),
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

  Widget _buildLocationSuggestions() {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _locationSuggestions.map((loc) {
          return GestureDetector(
            onTap: () {
              _locationCtrl.text = loc;
              _locationFocus.unfocus();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(SeeURadii.pill),
                border: Border.all(color: c.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIcons.mapPin(PhosphorIconsStyle.regular),
                      size: 14, color: SeeUColors.accent),
                  const SizedBox(width: 4),
                  Text(loc, style: SeeUTypography.caption.copyWith(color: c.ink)),
                ],
              ),
            ),
          );
        }).toList(),
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
                color: SeeUColors.accent.withValues(alpha: 0.12),
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
