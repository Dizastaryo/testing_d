import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/design/design.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';

class StoryCreatorScreen extends ConsumerStatefulWidget {
  const StoryCreatorScreen({super.key});

  @override
  ConsumerState<StoryCreatorScreen> createState() => _StoryCreatorScreenState();
}

class _StoryCreatorScreenState extends ConsumerState<StoryCreatorScreen> {
  File? _selectedImage;
  final _textCtrl = TextEditingController();
  bool _isUploading = false;
  bool _showTextInput = false;
  Offset _textOffset = const Offset(100, 200);

  @override
  void initState() {
    super.initState();
    // M22: Listen to text controller for live preview of overlay
    _textCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  // U12: Show camera and gallery options bottom sheet
  void _showChangeImageOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                PhosphorIcons.camera(PhosphorIconsStyle.bold),
                color: Colors.white,
              ),
              title: const Text('Камера',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(
                PhosphorIcons.images(PhosphorIconsStyle.bold),
                color: Colors.white,
              ),
              title: const Text('Галерея',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // U11: TODO: Integrate camera → story flow (capture photo directly and pass
  // it to this screen instead of opening ImagePicker with camera source)
  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1080,
    );
    if (picked != null && mounted) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  Future<void> _postStory() async {
    if (_selectedImage == null) return;
    setState(() => _isUploading = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post(ApiEndpoints.stories, data: {
        'media_url': 'https://picsum.photos/seed/story${DateTime.now().millisecondsSinceEpoch}/600/1000',
        'text_overlay': _textCtrl.text.trim(),
      });
      // H25: TODO: Replace mock media_url with real image upload implementation
      if (mounted) {
        // M20: Set _isUploading = false before pop to avoid state leak
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('История опубликована!')),
        );
        context.pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось опубликовать. Попробуйте снова.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Image preview or pick prompt
          if (_selectedImage != null)
            Image.file(_selectedImage!, fit: BoxFit.cover)
          else
            _buildPickerPrompt(),

          // Text overlay (draggable)
          if (_selectedImage != null && _textCtrl.text.isNotEmpty)
            Positioned(
              left: _textOffset.dx,
              top: _textOffset.dy,
              child: GestureDetector(
                onPanUpdate: (details) {
                  // M21: Clamp _textOffset within screen bounds
                  final size = MediaQuery.of(context).size;
                  setState(() {
                    _textOffset = Offset(
                      (_textOffset.dx + details.delta.dx).clamp(0.0, size.width - 80),
                      (_textOffset.dy + details.delta.dy).clamp(0.0, size.height - 60),
                    );
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(SeeURadii.small),
                  ),
                  child: Text(
                    _textCtrl.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

          // H26: Text input overlay — background tap dismisses, TextField is separate
          if (_showTextInput)
            Positioned.fill(
              child: Stack(
                children: [
                  // Background tap target — does not wrap TextField
                  GestureDetector(
                    onTap: () => setState(() => _showTextInput = false),
                    child: Container(color: Colors.black54),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: TextField(
                        controller: _textCtrl,
                        autofocus: true,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 20),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Добавить текст...',
                          hintStyle: TextStyle(color: Colors.white54),
                          filled: false,
                        ),
                        onSubmitted: (_) =>
                            setState(() => _showTextInput = false),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        PhosphorIcons.x(PhosphorIconsStyle.bold),
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_selectedImage != null) ...[
                    // U13: Clear button for text overlay
                    if (_textCtrl.text.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() => _textCtrl.clear()),
                        child: Container(
                          width: 40,
                          height: 40,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: const BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            PhosphorIcons.textStrikethrough(PhosphorIconsStyle.bold),
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: () => setState(() => _showTextInput = true),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          PhosphorIcons.textT(PhosphorIconsStyle.bold),
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Bottom bar
          if (_selectedImage != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // U12: Show camera and gallery options for "Изменить"
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isUploading
                              ? null
                              : () => _showChangeImageOptions(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side:
                                const BorderSide(color: Colors.white54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(SeeURadii.pill),
                            ),
                          ),
                          child: const Text('Изменить'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 48,
                          child: GestureDetector(
                            onTap: _isUploading ? null : _postStory,
                            child: Container(
                              decoration: BoxDecoration(
                                color: SeeUColors.accent,
                                borderRadius: BorderRadius.circular(SeeURadii.pill),
                              ),
                              child: Center(
                                child: _isUploading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Text(
                                            'Опубликовать',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            PhosphorIcons.arrowRight(PhosphorIconsStyle.bold),
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
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

  Widget _buildPickerPrompt() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: SeeUColors.accent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              PhosphorIcons.plus(PhosphorIconsStyle.bold),
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Добавить в историю',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Поделитесь фото, которое исчезнет через 24 часа',
            style: TextStyle(
              fontFamily: 'Segoe UI',
              fontSize: 14,
              color: Colors.white70,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PickButton(
                icon: PhosphorIcons.images(PhosphorIconsStyle.bold),
                label: 'Галерея',
                onTap: () => _pickImage(ImageSource.gallery),
              ),
              const SizedBox(width: 24),
              _PickButton(
                icon: PhosphorIcons.camera(PhosphorIconsStyle.bold),
                label: 'Камера',
                onTap: () => _pickImage(ImageSource.camera),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PickButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(SeeURadii.card),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
