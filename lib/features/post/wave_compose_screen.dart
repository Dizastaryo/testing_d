import 'package:dio/dio.dart';
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
import 'widgets/music_picker_sheet.dart';
import 'package:image_picker/image_picker.dart';

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

  // §03 A4: к волне можно приложить фото и/или трек (звук-мост).
  XFile? _photo;
  Uint8List? _photoBytes;
  AudioTrack? _track;

  // §A4 chart-bar: опрос из 2–4 вариантов. null = опроса нет.
  List<TextEditingController>? _pollCtrls;
  static const _pollMaxOptions = 4;
  static const _pollOptionMax = 80;

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
    _disposePoll();
    super.dispose();
  }

  void _disposePoll() {
    if (_pollCtrls != null) {
      for (final ctrl in _pollCtrls!) {
        ctrl.dispose();
      }
    }
  }

  /// Тап по chart-bar: включить опрос (стартует с 2 пустых вариантов) или,
  /// если он уже открыт, ничего — убирают его крестиком в шапке блока.
  void _togglePoll() {
    if (_pollCtrls != null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _pollCtrls = [TextEditingController(), TextEditingController()];
    });
  }

  void _removePoll() {
    _disposePoll();
    setState(() => _pollCtrls = null);
  }

  void _addPollOption() {
    if (_pollCtrls == null || _pollCtrls!.length >= _pollMaxOptions) return;
    setState(() => _pollCtrls!.add(TextEditingController()));
  }

  void _removePollOption(int i) {
    if (_pollCtrls == null || _pollCtrls!.length <= 2) return;
    final removed = _pollCtrls!.removeAt(i);
    removed.dispose();
    setState(() {});
  }

  /// Непустые варианты опроса (для валидации кнопки «Опубликовать» и отправки).
  List<String> get _pollLabels => _pollCtrls == null
      ? const []
      : _pollCtrls!
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery, imageQuality: 88, maxWidth: 2048);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = picked;
        _photoBytes = bytes;
      });
    } catch (_) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Не удалось выбрать фото',
          tone: SeeUTone.danger);
    }
  }

  void _pickTrack() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MusicPickerSheet(
        onSelect: (track) => setState(() => _track = track),
      ),
    );
  }

  /// «@» — вставить упоминание в позицию курсора.
  void _insertMention() {
    final sel = _ctrl.selection;
    final text = _ctrl.text;
    final at = sel.isValid ? sel.start : text.length;
    final needsSpace =
        at > 0 && text[at - 1] != ' ' && text[at - 1] != '\n';
    final insert = needsSpace ? ' @' : '@';
    _ctrl.text = text.replaceRange(at, sel.isValid ? sel.end : at, insert);
    _ctrl.selection = TextSelection.collapsed(offset: at + insert.length);
    _focus.requestFocus();
  }

  Future<void> _publish() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _publishing) return;
    // Опрос открыт, но заполнен меньше 2 вариантов — не публикуем.
    if (_pollCtrls != null && _pollLabels.length < 2) {
      showSeeUSnackBar(context, 'Заполните минимум 2 варианта опроса',
          tone: SeeUTone.danger);
      return;
    }
    setState(() => _publishing = true);
    try {
      final api = ref.read(apiClientProvider);
      // Фото прикладывается к тексту (§03 A3): сперва загружаем медиа.
      final mediaUrls = <String>[];
      final mediaTypes = <String>[];
      if (_photoBytes != null && _photo != null) {
        final form = FormData.fromMap({
          'file': MultipartFile.fromBytes(_photoBytes!,
              filename: _photo!.name),
        });
        final up = await api.post(ApiEndpoints.mediaUpload, data: form);
        final d = up.data;
        final url = (d is Map && d['data'] is Map)
            ? d['data']['url'] as String?
            : d is Map
                ? d['url'] as String?
                : null;
        if (url == null || url.isEmpty) {
          throw Exception('media upload failed');
        }
        mediaUrls.add(url);
        mediaTypes.add('image');
      }
      final data = <String, dynamic>{
        'is_wave': true,
        'caption': text,
        'media_urls': mediaUrls,
        'media_types': mediaTypes,
        if (_track != null) 'audio_track_id': _track!.id,
        if (_pollCtrls != null && _pollLabels.length >= 2)
          'poll_options': _pollLabels,
      };
      await api.post(ApiEndpoints.posts, data: data);
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

  Widget _buildPollEditor(SeeUThemeColors c) {
    final ctrls = _pollCtrls!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(SeeURadii.medium),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(PhosphorIcons.chartBar(),
                        size: 15, color: SeeUColors.accent),
                    const SizedBox(width: 6),
                    Text('ОПРОС',
                        style: SeeUTypography.kicker.copyWith(
                            color: SeeUColors.accent,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    GestureDetector(
                      onTap: _removePoll,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          Icon(PhosphorIcons.trash(), size: 14, color: c.ink3),
                          const SizedBox(width: 4),
                          Text('Убрать',
                              style: SeeUTypography.micro
                                  .copyWith(color: c.ink3)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (int i = 0; i < ctrls.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 2),
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius:
                                  BorderRadius.circular(SeeURadii.small),
                              border: Border.all(color: c.line),
                            ),
                            child: TextField(
                              controller: ctrls[i],
                              maxLength: _pollOptionMax,
                              cursorColor: SeeUColors.accent,
                              onChanged: (_) => setState(() {}),
                              buildCounter: (_,
                                      {required currentLength,
                                      required isFocused,
                                      maxLength}) =>
                                  null,
                              style: SeeUTypography.body.copyWith(color: c.ink),
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: 'Вариант ${i + 1}',
                                hintStyle:
                                    SeeUTypography.body.copyWith(color: c.ink3),
                              ),
                            ),
                          ),
                        ),
                        // Удалять можно, пока вариантов больше двух.
                        if (ctrls.length > 2)
                          GestureDetector(
                            onTap: () => _removePollOption(i),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(PhosphorIcons.x(),
                                  size: 16, color: c.ink3),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (ctrls.length < _pollMaxOptions)
                  GestureDetector(
                    onTap: _addPollOption,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(PhosphorIcons.plusCircle(),
                              size: 17, color: SeeUColors.accent),
                          const SizedBox(width: 6),
                          Text('Добавить вариант',
                              style: SeeUTypography.caption.copyWith(
                                  color: SeeUColors.accent,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final user = ref.watch(authProvider).user;
    final canPost = _ctrl.text.trim().isNotEmpty &&
        !_publishing &&
        (_pollCtrls == null || _pollLabels.length >= 2);

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
            // §A4 chart-bar: редактор опроса (2–4 варианта).
            if (_pollCtrls != null) _buildPollEditor(c),
            // §03 A4: превью вложений + счётчик + тулбар прикреплений.
            if (_photoBytes != null || _track != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    if (_photoBytes != null)
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(_photoBytes!,
                                width: 84, height: 84, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: -6,
                            right: -6,
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _photo = null;
                                _photoBytes = null;
                              }),
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: c.ink,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(PhosphorIcons.x(),
                                    size: 11, color: c.bg),
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (_photoBytes != null && _track != null)
                      const SizedBox(width: 10),
                    if (_track != null)
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: SeeUColors.accentSoft,
                            borderRadius:
                                BorderRadius.circular(SeeURadii.pill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                  PhosphorIconsFill.musicNotesSimple,
                                  size: 13,
                                  color: SeeUColors.accent),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${_track!.title} · ${_track!.artist}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: SeeUTypography.micro.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: SeeUColors.accent),
                                ),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _track = null),
                                child: const Icon(PhosphorIconsRegular.x,
                                    size: 12, color: SeeUColors.accent),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            // Счётчик над тулбаром, справа (§03 A4).
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text('${_ctrl.text.length} / $_max',
                    style: SeeUTypography.micro.copyWith(
                        fontWeight: FontWeight.w600, color: c.ink3)),
              ),
            ),
            // Тулбар: фото · трек · @ + хинт (§03 A4).
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: c.line, width: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 18, 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _pickPhoto,
                      child: Icon(PhosphorIcons.image(),
                          size: 22, color: c.ink2),
                    ),
                    const SizedBox(width: 22),
                    GestureDetector(
                      onTap: _pickTrack,
                      child: Icon(PhosphorIcons.musicNotesSimple(),
                          size: 22, color: c.ink2),
                    ),
                    const SizedBox(width: 22),
                    GestureDetector(
                      onTap: _insertMention,
                      child:
                          Icon(PhosphorIcons.at(), size: 22, color: c.ink2),
                    ),
                    const SizedBox(width: 22),
                    GestureDetector(
                      onTap: _togglePoll,
                      child: Icon(PhosphorIcons.chartBar(),
                          size: 22,
                          // Активная подсветка, пока опрос открыт.
                          color: _pollCtrls != null
                              ? SeeUColors.accent
                              : c.ink2),
                    ),
                    const Spacer(),
                    Text('фото · трек — опционально',
                        style: SeeUTypography.micro.copyWith(
                            fontWeight: FontWeight.w500, color: c.ink4)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
