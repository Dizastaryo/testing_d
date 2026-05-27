import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/story_provider.dart';

/// STORY-1: композёр текстовых сторис. Юзер выбирает фон (preset-градиент
/// или solid color), набирает текст до 500 символов, тапает «Опубликовать».
/// Backend принимает {media_type:'text', text_overlay, bg_color}.
///
/// Viewer (см. stories_row._StoryViewerState) рендерит text-сторис как
/// Container с этим градиентом/цветом и центральный текст.
class TextStoryComposeScreen extends ConsumerStatefulWidget {
  const TextStoryComposeScreen({super.key});

  @override
  ConsumerState<TextStoryComposeScreen> createState() =>
      _TextStoryComposeScreenState();
}

class _TextStoryComposeScreenState
    extends ConsumerState<TextStoryComposeScreen> {
  final _textCtrl = TextEditingController();
  final _focus = FocusNode();
  String _bgId = 'sunset';
  bool _publishing = false;
  bool _closeFriendsOnly = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Введите текст');
      return;
    }
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      await api.post(ApiEndpoints.stories, data: {
        'media_type': 'text',
        'text_overlay': text,
        'bg_color': _bgId,
        if (_closeFriendsOnly) 'is_close_friends_only': true,
      });
      // Refresh story feed so own sphere shows new story.
      ref.read(storyProvider.notifier).loadStories();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Стори опубликована!'),
          backgroundColor: Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go('/feed');
    } on DioException catch (e) {
      setState(() {
        _publishing = false;
        _error = apiErrorMessage(e);
      });
    } catch (e) {
      setState(() {
        _publishing = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = textStoryBackgroundFor(_bgId);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(PhosphorIconsRegular.x, color: Colors.white),
                  ),
                  const Spacer(),
                  Text(
                    '${_textCtrl.text.length}/500',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _publishing ? null : _submit,
                    style: TextButton.styleFrom(
                      foregroundColor: SeeUColors.accent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      backgroundColor: Colors.white,
                    ),
                    child: _publishing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: SeeUColors.accent))
                        : const Text('Опубликовать',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            // Canvas — gradient + text input centered
            Expanded(
              child: GestureDetector(
                onTap: () => _focus.requestFocus(),
                child: Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: bg.gradient,
                    color: bg.color,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: TextField(
                        controller: _textCtrl,
                        focusNode: _focus,
                        textAlign: TextAlign.center,
                        maxLength: 500,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(500),
                        ],
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(
                          color: bg.textColor,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          border: InputBorder.none,
                          hintText: 'Напишите что-нибудь…',
                          hintStyle: TextStyle(
                            color: bg.textColor.withValues(alpha: 0.45),
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            // PROFILE-3: CF toggle. Зелёный фон = on.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: InkWell(
                onTap: () =>
                    setState(() => _closeFriendsOnly = !_closeFriendsOnly),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _closeFriendsOnly
                        ? const Color(0xFF4CAF50).withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.08),
                    border: Border.all(
                      color: _closeFriendsOnly
                          ? const Color(0xFF4CAF50)
                          : Colors.white24,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PhosphorIconsBold.star,
                        size: 16,
                        color: _closeFriendsOnly
                            ? const Color(0xFF4CAF50)
                            : Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Только для близких друзей',
                        style: TextStyle(
                          color: _closeFriendsOnly
                              ? const Color(0xFF4CAF50)
                              : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Background picker
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: kTextStoryBackgrounds.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final preset = kTextStoryBackgrounds[i];
                  final selected = preset.id == _bgId;
                  return GestureDetector(
                    onTap: () => setState(() => _bgId = preset.id),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: preset.gradient,
                        color: preset.color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.25),
                          width: selected ? 3 : 1.5,
                        ),
                      ),
                      child: Icon(
                        PhosphorIconsBold.textT,
                        color: preset.textColor,
                        size: 22,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Preset для text-сторис. id хранится в БД как `bg_color`.
/// Если градиента нет — рендерим solid color.
class TextStoryBackground {
  final String id;
  final Gradient? gradient;
  final Color? color;
  final Color textColor;
  const TextStoryBackground({
    required this.id,
    this.gradient,
    this.color,
    this.textColor = Colors.white,
  });
}

const kTextStoryBackgrounds = <TextStoryBackground>[
  TextStoryBackground(
    id: 'sunset',
    gradient: LinearGradient(
      colors: [Color(0xFFFF7E5F), Color(0xFFFEB47B)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ),
  TextStoryBackground(
    id: 'ocean',
    gradient: LinearGradient(
      colors: [Color(0xFF2193b0), Color(0xFF6dd5ed)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ),
  TextStoryBackground(
    id: 'forest',
    gradient: LinearGradient(
      colors: [Color(0xFF134E5E), Color(0xFF71B280)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ),
  TextStoryBackground(
    id: 'orange',
    gradient: LinearGradient(
      colors: [Color(0xFFFF5A3C), Color(0xFFFFB088)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ),
  TextStoryBackground(
    id: 'midnight',
    gradient: LinearGradient(
      colors: [Color(0xFF232526), Color(0xFF414345)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ),
  TextStoryBackground(
    id: 'mono',
    color: Color(0xFF111111),
  ),
  TextStoryBackground(
    id: 'paper',
    color: Color(0xFFFBF6E9),
    textColor: Color(0xFF111111),
  ),
];

/// Возвращает preset по id, fallback на 'sunset'. Используется в viewer'е
/// и compose-экране одинаково.
TextStoryBackground textStoryBackgroundFor(String id) {
  for (final bg in kTextStoryBackgrounds) {
    if (bg.id == id) return bg;
  }
  return kTextStoryBackgrounds.first;
}
