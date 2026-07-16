import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/feed_provider.dart';

/// Composer «Волны» (§03 A4) — текст-первый пост. Набранный текст рисуется
/// серифным курсивом Times New Roman (как в дизайне и в самой волне),
/// плейсхолдер — Lora. Автор выбирает цвет акцентной планки. Публикует через
/// POST /posts {is_wave:true}.
class WaveComposeScreen extends ConsumerStatefulWidget {
  const WaveComposeScreen({super.key});

  @override
  ConsumerState<WaveComposeScreen> createState() => _WaveComposeScreenState();
}

class _WaveComposeScreenState extends ConsumerState<WaveComposeScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  static const _max = 500;
  bool _publishing = false;

  // Палитра акцентной планки волны. Индекс 0 (коралл) — дефолт бэка (шлём
  // null), остальные передаём как ARGB int в wave_color_value.
  static const _accents = <Color>[
    SeeUColors.accent,
    SeeUColors.amber,
    SeeUColors.plum,
    SeeUColors.info,
    SeeUColors.like,
    SeeUColors.success,
  ];
  int _accentIdx = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _publishing) return;
    setState(() => _publishing = true);
    try {
      final data = <String, dynamic>{
        'is_wave': true,
        'caption': text,
        'media_urls': <String>[],
        'media_types': <String>[],
      };
      // Коралл (индекс 0) — дефолт, не шлём; остальные как ARGB int.
      if (_accentIdx != 0) {
        data['wave_color_value'] = _accents[_accentIdx].toARGB32();
      }
      await ref.read(apiClientProvider).post(ApiEndpoints.posts, data: data);
      if (!mounted) return;
      ref.read(feedProvider.notifier).refresh();
      HapticFeedback.mediumImpact();
      context.pop();
      showSeeUSnackBar(context, 'Волна опубликована',
          icon: PhosphorIcons.checkCircle());
    } catch (_) {
      if (!mounted) return;
      setState(() => _publishing = false);
      showSeeUSnackBar(context, 'Не удалось опубликовать',
          tone: SeeUTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final user = ref.watch(authProvider).user;
    final canPost = _ctrl.text.trim().isNotEmpty && !_publishing;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Верхняя панель: Отмена · Новая волна · Опубликовать.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    behavior: HitTestBehavior.opaque,
                    child: Text('Отмена',
                        style: SeeUTypography.body.copyWith(color: c.ink3)),
                  ),
                  const Spacer(),
                  Text('Новая волна',
                      style: SeeUTypography.subtitle
                          .copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Tappable.scaled(
                    onTap: () {
                      if (canPost) _publish();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 15, vertical: 8),
                      decoration: BoxDecoration(
                        color: canPost ? SeeUColors.accent : c.surface2,
                        borderRadius: BorderRadius.circular(SeeURadii.pill),
                      ),
                      child: _publishing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text('Опубликовать',
                              style: SeeUTypography.caption.copyWith(
                                fontWeight: FontWeight.w700,
                                color: canPost ? Colors.white : c.ink3,
                              )),
                    ),
                  ),
                ],
              ),
            ),
            // Автор + «· ВОЛНА» + подпись видимости.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: c.surface2,
                    backgroundImage: (user?.avatarUrl != null &&
                            user!.avatarUrl!.isNotEmpty)
                        ? NetworkImage(user.avatarUrl!)
                        : null,
                    child: (user?.avatarUrl == null ||
                            (user?.avatarUrl?.isEmpty ?? true))
                        ? Icon(PhosphorIcons.user(), size: 16, color: c.ink3)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                user?.username ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: SeeUTypography.subtitle
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('· ВОЛНА',
                                style: SeeUTypography.kicker.copyWith(
                                  color: SeeUColors.accent,
                                  fontWeight: FontWeight.w700,
                                )),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text('видно всем · ответить смогут подписчики',
                            style:
                                SeeUTypography.micro.copyWith(color: c.ink3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Серифный курсив (Times New Roman) — как в самой волне.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  maxLength: _max,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  cursorColor: SeeUColors.accent,
                  buildCounter: (_,
                          {required currentLength,
                          required isFocused,
                          maxLength}) =>
                      null,
                  style: TextStyle(
                    fontFamily: 'Times New Roman',
                    fontFamilyFallback: const [
                      'Playfair Display',
                      'Georgia',
                      'serif',
                    ],
                    fontStyle: FontStyle.italic,
                    fontSize: 21,
                    height: 1.55,
                    color: c.ink,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Скажи волной…',
                    hintStyle: TextStyle(
                      fontFamily: 'Lora',
                      fontFamilyFallback: const ['Playfair Display', 'serif'],
                      fontStyle: FontStyle.italic,
                      fontSize: 18,
                      color: c.ink3.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ),
            // Нижняя панель: цвет акцентной планки + счётчик.
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
              child: Row(
                children: [
                  for (var i = 0; i < _accents.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => _accentIdx = i),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: _accents[i],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _accentIdx == i
                                  ? c.ink
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text('${_ctrl.text.length} / $_max',
                      style: SeeUTypography.caption.copyWith(color: c.ink3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
