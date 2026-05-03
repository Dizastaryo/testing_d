import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/design/design.dart';
import '../../core/providers/feed_provider.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';

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

  List<File> _selectedFiles = [];
  bool _isPosting = false;
  bool _locationFocused = false;
  final List<String> _tags = [];
  final ImagePicker _picker = ImagePicker();

  static const int _maxCaption = 2000;

  static const List<String> _emojis = [
    '\u{1F60A}', '\u{1F525}', '\u{2764}\u{FE0F}', '\u{2728}',
    '\u{1F389}', '\u{1F44F}', '\u{1F4AA}', '\u{1F31F}',
  ];

  static const List<String> _locationSuggestions = [
    '\u0410\u043B\u043C\u0430\u0442\u044B',
    '\u0410\u0441\u0442\u0430\u043D\u0430',
    '\u0411\u0438\u0448\u043A\u0435\u043A',
    '\u0422\u0430\u0448\u043A\u0435\u043D\u0442',
    '\u041C\u043E\u0441\u043A\u0432\u0430',
  ];

  Future<void> _pickImages() async {
    final pickedFiles = await _picker.pickMultiImage();
    if (pickedFiles.isNotEmpty) {
      setState(() {
        _selectedFiles = pickedFiles.map((xf) => File(xf.path)).toList();
      });
    }
  }

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

  void _addTag() {
    final raw = _tagCtrl.text.trim().replaceAll('#', '');
    if (raw.isEmpty) return;
    final tag = '#$raw';
    if (!_tags.contains(tag)) {
      setState(() => _tags.add(tag));
    }
    _tagCtrl.clear();
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
  }

  Future<void> _publish() async {
    if (_selectedFiles.isEmpty) return;
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

      // Upload each file and collect URLs
      final List<String> mediaUrls = [];
      for (final file in _selectedFiles) {
        final formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(file.path),
        });
        final uploadResp = await api.post(
          ApiEndpoints.mediaUpload,
          data: formData,
        );
        final url = uploadResp.data['data']['url'] as String;
        mediaUrls.add(url);
      }

      await api.post(ApiEndpoints.posts, data: {
        'caption': captionParts.isNotEmpty ? captionParts.join('\n\n') : '',
        'media_urls': mediaUrls,
        'media_types': List.filled(mediaUrls.length, 'image'),
        'location': _locationCtrl.text.trim().isNotEmpty ? _locationCtrl.text.trim() : '',
      });
      if (mounted) {
        ref.read(feedProvider.notifier).refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '\u041F\u043E\u0441\u0442 \u043E\u043F\u0443\u0431\u043B\u0438\u043A\u043E\u0432\u0430\u043D!',
              style: SeeUTypography.body.copyWith(color: Colors.white),
            ),
            backgroundColor: SeeUColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SeeURadii.small),
            ),
          ),
        );
        context.go('/feed');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isPosting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '\u041D\u0435 \u0443\u0434\u0430\u043B\u043E\u0441\u044C \u043E\u043F\u0443\u0431\u043B\u0438\u043A\u043E\u0432\u0430\u0442\u044C.',
              style: SeeUTypography.body.copyWith(color: Colors.white),
            ),
            backgroundColor: SeeUColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SeeURadii.small),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final bool canPublish = _selectedFiles.isNotEmpty && !_isPosting;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          '\u041D\u043E\u0432\u044B\u0439 \u043F\u043E\u0441\u0442',
          style: SeeUTypography.subtitle.copyWith(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            PhosphorIcons.x(PhosphorIconsStyle.bold),
            color: c.ink,
          ),
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
                      '\u041E\u043F\u0443\u0431\u043B\u0438\u043A\u043E\u0432\u0430\u0442\u044C',
                      style: SeeUTypography.caption.copyWith(
                        color: canPublish
                            ? SeeUColors.accent
                            : c.ink3,
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
              // ── Preview ──
              if (_selectedFiles.isNotEmpty) _buildPreview(),

              // ── Image grid ──
              _buildSectionHeader(
                icon: PhosphorIcons.images(PhosphorIconsStyle.bold),
                title: '\u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u0444\u043E\u0442\u043E',
              ),
              _buildImageGrid(),
              const SizedBox(height: 20),

              // ── Caption ──
              _buildSectionHeader(
                icon: PhosphorIcons.textAa(PhosphorIconsStyle.bold),
                title: '\u041E\u043F\u0438\u0441\u0430\u043D\u0438\u0435',
              ),
              _buildCaptionInput(),
              const SizedBox(height: 4),
              _buildEmojiRow(),
              const SizedBox(height: 20),

              // ── Location ──
              _buildSectionHeader(
                icon: PhosphorIcons.mapPin(PhosphorIconsStyle.bold),
                title: '\u041C\u0435\u0441\u0442\u043E',
              ),
              _buildLocationInput(),
              if (_locationFocused) _buildLocationSuggestions(),
              const SizedBox(height: 20),

              // ── Tags ──
              _buildSectionHeader(
                icon: PhosphorIcons.hash(PhosphorIconsStyle.bold),
                title: '\u0422\u0435\u0433\u0438',
              ),
              _buildTagsInput(),
              if (_tags.isNotEmpty) _buildTagChips(),
              const SizedBox(height: 28),

              // ── Publish button ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SeeUButton(
                  label: '\u041E\u043F\u0443\u0431\u043B\u0438\u043A\u043E\u0432\u0430\u0442\u044C',
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

  // ─── Preview ───────────────────────────────────────────────────────────────

  Widget _buildPreview() {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SeeURadii.card),
        child: Stack(
          children: [
            Image.file(
              _selectedFiles.first,
              width: double.infinity,
              height: 280,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: double.infinity,
                height: 280,
                color: c.surface2,
                child: Icon(
                  PhosphorIcons.imageSquare(PhosphorIconsStyle.bold),
                  size: 48,
                  color: c.ink3,
                ),
              ),
            ),
            if (_captionCtrl.text.trim().isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
                  child: Text(
                    _captionCtrl.text.trim(),
                    style: SeeUTypography.body.copyWith(
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Section header ────────────────────────────────────────────────────────

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
          Text(
            title,
            style: SeeUTypography.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: c.ink2,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Image grid ────────────────────────────────────────────────────────────

  Widget _buildImageGrid() {
    final c = context.seeuColors;
    final itemCount = _selectedFiles.length + 1; // +1 for the "add" button
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemBuilder: (context, index) {
          // Last item is the "add" button
          if (index == _selectedFiles.length) {
            return GestureDetector(
              onTap: _pickImages,
              child: Container(
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(SeeURadii.small),
                  border: Border.all(color: c.line, width: 1.5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      PhosphorIcons.plus(PhosphorIconsStyle.bold),
                      color: SeeUColors.accent,
                      size: 28,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\u0414\u043E\u0431\u0430\u0432\u0438\u0442\u044C',
                      style: SeeUTypography.micro.copyWith(
                        color: SeeUColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return GestureDetector(
            onLongPress: () {
              setState(() {
                _selectedFiles.removeAt(index);
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(SeeURadii.small),
                border: Border.all(
                  color: index == 0 ? SeeUColors.accent : Colors.transparent,
                  width: 3,
                ),
                boxShadow: index == 0 ? SeeUShadows.md : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(SeeURadii.small - 2),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      _selectedFiles[index],
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: c.surface2,
                        child: Icon(
                          PhosphorIcons.imageSquare(PhosphorIconsStyle.regular),
                          color: c.ink3,
                          size: 24,
                        ),
                      ),
                    ),
                    // Remove button
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedFiles.removeAt(index);
                          });
                        },
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Caption input ─────────────────────────────────────────────────────────

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
                hintText: '\u0420\u0430\u0441\u0441\u043A\u0430\u0436\u0438\u0442\u0435 \u043E \u0444\u043E\u0442\u043E...',
                hintStyle: SeeUTypography.body.copyWith(
                  color: c.ink3,
                ),
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

  // ─── Emoji row ─────────────────────────────────────────────────────────────

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
                _captionCtrl.selection = TextSelection.collapsed(
                  offset: offset + emoji.length,
                );
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

  // ─── Location input ────────────────────────────────────────────────────────

  Widget _buildLocationInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SeeUInput(
        controller: _locationCtrl,
        focusNode: _locationFocus,
        hintText: '\u0414\u043E\u0431\u0430\u0432\u0438\u0442\u044C \u043C\u0435\u0441\u0442\u043E',
        prefix: Icon(
          PhosphorIcons.mapPin(PhosphorIconsStyle.bold),
          color: SeeUColors.textTertiary,
          size: 20,
        ),
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
                  Icon(
                    PhosphorIcons.mapPin(PhosphorIconsStyle.regular),
                    size: 14,
                    color: SeeUColors.accent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    loc,
                    style: SeeUTypography.caption.copyWith(
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Tags input ────────────────────────────────────────────────────────────

  Widget _buildTagsInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SeeUInput(
        controller: _tagCtrl,
        hintText: '\u0414\u043E\u0431\u0430\u0432\u044C\u0442\u0435 \u0442\u0435\u0433 \u0438 \u043D\u0430\u0436\u043C\u0438\u0442\u0435 +',
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
            child: const Icon(Icons.add, color: Colors.white, size: 18),
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
                  Text(
                    tag,
                    style: SeeUTypography.caption.copyWith(
                      color: SeeUColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    PhosphorIcons.x(PhosphorIconsStyle.bold),
                    size: 12,
                    color: SeeUColors.accent,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
