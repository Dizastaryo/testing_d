import 'dart:ui' as ui;

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
      showSeeUSnackBar(context, 'Стори опубликована!',
          tone: SeeUTone.success);
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
            // Header — тёмный стеклянный бар: blur + светлый→тёмный градиент
            // + hairline снизу.
            ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.14),
                        Colors.black.withValues(alpha: 0.28),
                      ],
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 0.5,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    children: [
                      SeeUGlassCircleButton(
                        size: 36,
                        onTap: () => Navigator.of(context).maybePop(),
                        icon: const Icon(PhosphorIconsRegular.x,
                            color: Colors.white, size: 18),
                      ),
                      const Spacer(),
                      Text(
                        '${_textCtrl.text.length}/500',
                        style: SeeUTypography.kicker.copyWith(
                            color: Colors.white.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(width: 12),
                      Tappable.scaled(
                        onTap: _publishing ? null : _submit,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: SeeUGradients.heroOrange,
                            borderRadius:
                                BorderRadius.circular(SeeURadii.pill),
                            boxShadow: SeeUShadows.md,
                          ),
                          child: _publishing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Опубликовать',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
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
                    borderRadius: BorderRadius.circular(SeeURadii.card),
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
                        // Editorial serif (Fraunces + Playfair-fallback
                        // для кириллицы) — тот же характер, что displayM.
                        style: SeeUTypography.displayM.copyWith(
                          color: bg.textColor,
                          fontSize: 28,
                          height: 1.2,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          border: InputBorder.none,
                          hintText: 'Напишите что-нибудь…',
                          hintStyle: SeeUTypography.displayM.copyWith(
                            color: bg.textColor.withValues(alpha: 0.45),
                            fontSize: 28,
                            height: 1.2,
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
                    style: SeeUTypography.caption
                        .copyWith(color: SeeUColors.error)),
              ),
            // PROFILE-3: CF toggle — вложенный стеклянный чип (плоский,
            // без своего blur); активный — success-тинт.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: InkWell(
                onTap: () =>
                    setState(() => _closeFriendsOnly = !_closeFriendsOnly),
                borderRadius: BorderRadius.circular(SeeURadii.pill),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _closeFriendsOnly
                        ? SeeUColors.success.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.10),
                    border: Border.all(
                      color: _closeFriendsOnly
                          ? SeeUColors.success.withValues(alpha: 0.55)
                          : Colors.white.withValues(alpha: 0.22),
                    ),
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PhosphorIconsBold.star,
                        size: 16,
                        color: _closeFriendsOnly
                            ? SeeUColors.success
                            : Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Только для близких друзей',
                        style: TextStyle(
                          color: _closeFriendsOnly
                              ? SeeUColors.success
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
      colors: [SeeUColors.accent, Color(0xFFFFB088)],
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
