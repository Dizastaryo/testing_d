import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

  int? _selectedImageIndex;
  bool _isPosting = false;
  bool _locationFocused = false;
  final List<String> _tags = [];

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

  List<String> get _mockImages => List.generate(
        9,
        (i) => 'https://picsum.photos/seed/seeu_pick_$i/400/400',
      );

  String? get _selectedImageUrl =>
      _selectedImageIndex != null ? _mockImages[_selectedImageIndex!] : null;

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
    if (_selectedImageUrl == null) return;
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
      await api.post(ApiEndpoints.posts, data: {
        'caption': captionParts.isNotEmpty ? captionParts.join('\n\n') : '',
        'media_urls': [_selectedImageUrl!],
        'media_types': ['image'],
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
    final bool canPublish = _selectedImageIndex != null && !_isPosting;

    return Scaffold(
      backgroundColor: SeeUColors.background,
      appBar: AppBar(
        backgroundColor: SeeUColors.background,
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
            color: SeeUColors.textPrimary,
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
                            : SeeUColors.textTertiary,
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
              if (_selectedImageUrl != null) _buildPreview(),

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SeeURadii.card),
        child: Stack(
          children: [
            Image.network(
              _selectedImageUrl!,
              width: double.infinity,
              height: 280,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: double.infinity,
                  height: 280,
                  color: SeeUColors.surfaceElevated,
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: SeeUColors.accent,
                      strokeWidth: 2,
                    ),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                width: double.infinity,
                height: 280,
                color: SeeUColors.surfaceElevated,
                child: Icon(
                  PhosphorIcons.imageSquare(PhosphorIconsStyle.bold),
                  size: 48,
                  color: SeeUColors.textTertiary,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: SeeUColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            title,
            style: SeeUTypography.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: SeeUColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Image grid ────────────────────────────────────────────────────────────

  Widget _buildImageGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 9,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemBuilder: (context, index) {
          final isSelected = _selectedImageIndex == index;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedImageIndex =
                    _selectedImageIndex == index ? null : index;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(SeeURadii.small),
                border: Border.all(
                  color: isSelected ? SeeUColors.accent : Colors.transparent,
                  width: 3,
                ),
                boxShadow: isSelected ? SeeUShadows.md : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(SeeURadii.small - 2),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      _mockImages[index],
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: SeeUColors.surfaceElevated,
                          child: const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: SeeUColors.accent,
                                strokeWidth: 1.5,
                              ),
                            ),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        color: SeeUColors.surfaceElevated,
                        child: Icon(
                          PhosphorIcons.imageSquare(PhosphorIconsStyle.regular),
                          color: SeeUColors.textTertiary,
                          size: 24,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Container(
                        color: SeeUColors.accent.withValues(alpha: 0.15),
                        child: Center(
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: SeeUColors.accent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
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
    final charCount = _captionCtrl.text.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            decoration: BoxDecoration(
              color: SeeUColors.surfaceElevated,
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
                  color: SeeUColors.textTertiary,
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
                    : SeeUColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Emoji row ─────────────────────────────────────────────────────────────

  Widget _buildEmojiRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: SeeUColors.surfaceElevated,
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
                color: SeeUColors.surfaceElevated,
                borderRadius: BorderRadius.circular(SeeURadii.pill),
                border: Border.all(color: SeeUColors.borderSubtle),
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
                      color: SeeUColors.textPrimary,
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
                color: SeeUColors.accentSoft,
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
