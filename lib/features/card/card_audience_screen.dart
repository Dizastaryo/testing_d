import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/design/design.dart';
import '../../core/providers/card_provider.dart';
import 'card_portrait.dart';
import 'card_style.dart';
import 'card_warning_screen.dart' show CardGlassBar;

/// «Кто рядом смотрел» — симметрия видимости. Каждый, кто открыл твою карточку
/// или отправил Spark, показан ПО СВОЕЙ КАРТОЧКЕ (фото + ник + оформление),
/// никогда по реальному имени. Отсюда можно заблокировать.
class CardAudienceScreen extends ConsumerStatefulWidget {
  const CardAudienceScreen({super.key});

  @override
  ConsumerState<CardAudienceScreen> createState() => _CardAudienceScreenState();
}

class _CardAudienceScreenState extends ConsumerState<CardAudienceScreen> {
  bool _loading = true;
  String? _error;
  CardStats _stats = const CardStats();
  List<CardAudienceEntry> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        fetchCardStats(api),
        fetchCardAudience(api),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as CardStats;
        _items = results[1] as List<CardAudienceEntry>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить';
        _loading = false;
      });
    }
  }

  Future<void> _block(CardAudienceEntry e) async {
    HapticFeedback.mediumImpact();
    final ok = await showSeeUConfirm(
      context,
      title: 'Заблокировать?',
      message:
          'Этот человек больше не увидит твою карточку рядом и не сможет '
          'отправить тебе Spark. Снять блокировку сможешь только ты.',
      confirmLabel: 'Заблокировать',
      destructive: true,
      icon: PhosphorIcons.prohibit(),
    );
    if (!ok) return;
    final api = ref.read(apiClientProvider);
    final done = await blockCard(api, e.card.ownerId);
    if (!mounted) return;
    if (done) {
      setState(() => _items.remove(e));
      showSeeUSnackBar(context, 'Заблокировано', tone: SeeUTone.success);
    } else {
      showSeeUSnackBar(context, 'Не удалось заблокировать',
          tone: SeeUTone.danger);
    }
  }

  /// Лист заблокированных карточек с действием «Разблокировать».
  Future<void> _openBlockedSheet() async {
    final api = ref.read(apiClientProvider);
    await showSeeUBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => _BlockedCardsSheet(api: api),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          CardGlassBar(
            kicker: 'КАРТОЧКА',
            title: 'Кто рядом смотрел',
            onBack: () => context.pop(),
            // Доступ к списку заблокированных карточек — раньше вечная
            // блокировка не имела никакого способа снятия из UI, вопреки
            // обещанию «снять сможешь только ты».
            action: IconButton(
              icon: Icon(PhosphorIcons.prohibitInset(), color: c.ink2),
              tooltip: 'Заблокированные',
              onPressed: _openBlockedSheet,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: TextStyle(color: SeeUColors.danger)),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _items.isEmpty
                            ? _empty(c)
                            : ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 16, 20, 28),
                                children: [
                                  _statsCard(c),
                                  const SizedBox(height: 16),
                                  for (final e in _items) ...[
                                    _audienceCard(e),
                                    const SizedBox(height: 12),
                                  ],
                                  const SizedBox(height: 4),
                                  Center(
                                    child: Text(
                                      'Каждый показан по своей карточке · '
                                      'заблокировать снимаешь только ты',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 11.5, color: c.ink3),
                                    ),
                                  ),
                                ],
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  // ── Стат-карточка: крупное число + 7-дневный чарт ─────────────────────────

  Widget _statsCard(SeeUThemeColors c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFEDE5), Color(0xFFFFE1D6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ТЕБЯ ПОСМОТРЕЛИ',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: Color(0xFFC08A78),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${_stats.viewsTotal}',
                          style: SeeUTypography.displayS.copyWith(
                            fontSize: 44,
                            fontWeight: FontWeight.w600,
                            height: 0.85,
                            letterSpacing: -1.5,
                            color: const Color(0xFF161310),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'раз',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF8A5546),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_stats.viewersCount}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      color: SeeUColors.accent,
                    ),
                  ),
                  const Text(
                    'человек',
                    style: TextStyle(fontSize: 10.5, color: Color(0xFF8A5546)),
                  ),
                ],
              ),
            ],
          ),
          if (_stats.days.isNotEmpty) ...[
            const SizedBox(height: 16),
            _barChart(),
            const SizedBox(height: 7),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '7 дней назад',
                  style: TextStyle(fontSize: 10, color: Color(0xFFC08A78)),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(PhosphorIconsFill.fireSimple,
                        size: 11, color: SeeUColors.accent),
                    const SizedBox(width: 4),
                    Text(
                      '${_stats.sparksCount} отправили Spark',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: SeeUColors.accent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Бар-чарт просмотров за 7 дней. Высоты нормируются по максимуму,
  /// прозрачность нарастает к сегодняшнему дню (как в дизайне).
  Widget _barChart() {
    final days = _stats.days;
    final maxV = days.fold<int>(0, (m, v) => v > m ? v : m);
    return SizedBox(
      height: 38,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < days.length; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(
              child: FractionallySizedBox(
                heightFactor:
                    maxV == 0 ? 0.06 : (days[i] / maxV).clamp(0.06, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        SeeUColors.accentSecondary,
                        SeeUColors.accent,
                      ],
                    ),
                  ),
                  // Прозрачность нарастает от старого дня к сегодняшнему.
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: const Color(0xFFFFE1D6).withValues(
                      alpha: days.length == 1
                          ? 0
                          : (1 - (0.35 + 0.65 * (i / (days.length - 1)))),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Карточка человека из аудитории ────────────────────────────────────────

  Widget _audienceCard(CardAudienceEntry e) {
    final t = templateFromStyle(e.card.style);
    return CardPortrait(
      template: t,
      photoUrl: e.card.photoUrl,
      nickname: e.card.displayName,
      text: e.card.text,
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      nickSize: 21,
      textSize: 13.5,
      barWidth: 32,
      photoGlow: false,
      meta: CardMetaRow(
        template: t,
        sparked: e.sparked,
        label: _metaLabel(e),
      ),
      trailing: CardCircleButton(
        icon: PhosphorIcons.prohibit(),
        onTap: () => _block(e),
      ),
    );
  }

  String _metaLabel(CardAudienceEntry e) {
    final views = e.viewCount;
    if (e.sparked && views > 0) return 'Spark · смотрел $views ${_times(views)}';
    if (e.sparked) return 'отправил Spark';
    return 'смотрел $views ${_times(views)}';
  }

  String _times(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m100 >= 11 && m100 <= 14) return 'раз';
    if (m10 == 1) return 'раз';
    if (m10 >= 2 && m10 <= 4) return 'раза';
    return 'раз';
  }

  // ── Пусто ─────────────────────────────────────────────────────────────────

  Widget _empty(SeeUThemeColors c) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 44),
      children: [
        const SizedBox(height: 120),
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.surface2,
            ),
            alignment: Alignment.center,
            child: Icon(PhosphorIcons.usersThree(), size: 46, color: c.ink4),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Пока никто не смотрел\nтвою карточку',
          textAlign: TextAlign.center,
          style: SeeUTypography.displayS
              .copyWith(fontSize: 23, height: 1.2, color: c.ink),
        ),
        const SizedBox(height: 12),
        Text(
          'Включи браслет и будь рядом с людьми — кто откроет карточку, '
          'появится здесь',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.55, color: c.ink3),
        ),
      ],
    );
  }
}

/// Лист заблокированных карточек с действием «Разблокировать».
class _BlockedCardsSheet extends StatefulWidget {
  final ApiClient api;
  const _BlockedCardsSheet({required this.api});

  @override
  State<_BlockedCardsSheet> createState() => _BlockedCardsSheetState();
}

class _BlockedCardsSheetState extends State<_BlockedCardsSheet> {
  bool _loading = true;
  String? _error;
  List<CardAudienceEntry> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await fetchCardBlocks(widget.api);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить';
        _loading = false;
      });
    }
  }

  Future<void> _unblock(CardAudienceEntry e) async {
    HapticFeedback.selectionClick();
    try {
      await unblockCard(widget.api, e.card.ownerId);
      if (!mounted) return;
      setState(() => _items.remove(e));
      showSeeUSnackBar(context, 'Разблокировано', tone: SeeUTone.success);
    } catch (_) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Не удалось разблокировать',
          tone: SeeUTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Text('Заблокированные',
                      style: SeeUTypography.subtitle.copyWith(color: c.ink)),
                ],
              ),
            ),
            Divider(height: 1, color: c.line),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()))
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                              child: Text(_error!,
                                  style: TextStyle(color: SeeUColors.danger))))
                      : _items.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(40),
                              child: Center(
                                  child: Text('Никто не заблокирован',
                                      style: SeeUTypography.body
                                          .copyWith(color: c.ink3))))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              itemCount: _items.length,
                              itemBuilder: (_, i) {
                                final e = _items[i];
                                final t = templateFromStyle(e.card.style);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: CardPortrait(
                                    template: t,
                                    photoUrl: e.card.photoUrl,
                                    nickname: e.card.displayName,
                                    text: e.card.text,
                                    photoGlow: false,
                                    trailing: TextButton(
                                      onPressed: () => _unblock(e),
                                      child: Text('Разблокировать',
                                          style: SeeUTypography.caption.copyWith(
                                              color: SeeUColors.accent)),
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
