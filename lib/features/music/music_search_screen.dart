import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/audio_category.dart';
import '../../core/models/audio_track.dart';
import '../../core/providers/audio_discovery_provider.dart';
import '../../core/providers/audio_provider.dart';
import 'audio_design.dart';
import 'widgets/track_row.dart';

/// Поиск. Три состояния, и ни одно из них не пустует:
/// **до ввода** — забирает за руку (недавнее, категории, что набирает);
/// **результаты** — фильтр по типу, сортировка, отдельный хит по автору;
/// **ничего не найдено** — предлагает выход, а не тупик.
class MusicSearchScreen extends ConsumerStatefulWidget {
  final String initialCategory;

  /// Запрос, с которым экран открыли — например, тап по имени автора.
  final String initialQuery;

  const MusicSearchScreen({
    super.key,
    this.initialCategory = '',
    this.initialQuery = '',
  });

  @override
  ConsumerState<MusicSearchScreen> createState() => _MusicSearchScreenState();
}

class _MusicSearchScreenState extends ConsumerState<MusicSearchScreen> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialQuery);
  Timer? _debounce;

  late String _query = widget.initialQuery.trim();
  late String _category = widget.initialCategory;
  String _sort = 'trending';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _query = v.trim());
    });
  }

  void _submit(String v) {
    final q = v.trim();
    if (q.length < 2) return;
    ref.read(audioSearchHistoryProvider.notifier).add(q);
    setState(() => _query = q);
  }

  void _useQuery(String q) {
    _ctrl.text = q;
    _submit(q);
  }

  void _clear() {
    _ctrl.clear();
    _debounce?.cancel();
    setState(() {
      _query = '';
      _category = '';
    });
  }

  bool get _searching => _query.length >= 2 || _category.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_searching)
              _compactBar(c)
            else ...[
              const AudioMainBar(title: 'Поиск'),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _field(c, focused: true),
              ),
            ],
            Expanded(child: _searching ? _results(c) : _showcase(c)),
          ],
        ),
      ),
    );
  }

  // ── Строка поиска ─────────────────────────────────────────────────────────

  Widget _field(SeeUThemeColors c, {bool focused = false}) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focused ? SeeUColors.accent : c.line,
          width: focused ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIcons.magnifyingGlass(),
            size: 18,
            color: focused ? SeeUColors.accent : c.ink3,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _ctrl,
              onChanged: _onChanged,
              onSubmitted: _submit,
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: 14, color: c.ink),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Трек, автор или звук',
                hintStyle: TextStyle(fontSize: 14, color: c.ink3),
              ),
            ),
          ),
          if (_ctrl.text.isNotEmpty)
            Tappable(
              onTap: _clear,
              child: Icon(PhosphorIconsFill.xCircle, size: 18, color: c.ink4),
            ),
        ],
      ),
    );
  }

  /// Как только пошёл поиск, шапка ужимается: результаты важнее заголовка.
  Widget _compactBar(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
      child: Row(
        children: [
          Tappable(
            onTap: _clear,
            child: SizedBox(
              width: 40,
              height: 44,
              child: Icon(PhosphorIcons.arrowLeft(), size: 22, color: c.ink),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(child: _field(c)),
        ],
      ),
    );
  }

  // ── До ввода ──────────────────────────────────────────────────────────────

  Widget _showcase(SeeUThemeColors c) {
    final history = ref.watch(audioSearchHistoryProvider);
    final trending = ref.watch(trendingTracksProvider).valueOrNull ?? const [];

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 22, 20, 24 + context.bottomBarInset),
      children: [
        if (history.isNotEmpty) ...[
          Row(
            children: [
              _kicker('НЕДАВНО ИСКАЛИ', c),
              const Spacer(),
              Tappable(
                onTap: () =>
                    ref.read(audioSearchHistoryProvider.notifier).clear(),
                child: Text(
                  'Очистить',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AudioColors.kicker(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in history)
                Tappable.scaled(
                  onTap: () => _useQuery(q),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: c.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIcons.clockCounterClockwise(),
                            size: 14, color: c.ink3),
                        const SizedBox(width: 7),
                        Text(q, style: TextStyle(fontSize: 13, color: c.ink)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],

        _kicker('ЗАЙТИ ПО КАТЕГОРИИ', c),
        const SizedBox(height: 12),
        // Здесь все девять: это каталог, а не витрина главной.
        for (var i = 0; i < kAudioCategories.length; i += 2) ...[
          Row(
            children: [
              Expanded(child: _categoryCard(kAudioCategories[i])),
              const SizedBox(width: 9),
              Expanded(
                child: i + 1 < kAudioCategories.length
                    ? _categoryCard(kAudioCategories[i + 1])
                    : const SizedBox(),
              ),
            ],
          ),
          const SizedBox(height: 9),
        ],

        if (trending.isNotEmpty) ...[
          const SizedBox(height: 16),
          _kicker('НАБИРАЮТ СЕЙЧАС', c),
          const SizedBox(height: 12),
          for (var i = 0; i < trending.length && i < 5; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: Text(
                      '${i + 1}',
                      style: SeeUTypography.displayS
                          .copyWith(fontSize: 18, color: c.ink4),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TrackRow(
                      track: trending[i],
                      queue: trending,
                      index: i,
                      source: 'trending',
                      trailing: TrackRowTrailing.none,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(PhosphorIcons.trendUp(),
                      size: 16, color: SeeUColors.success),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _categoryCard(AudioCategoryModel cat) {
    return Tappable.scaled(
      onTap: () => context.push('/music/category/${cat.id}'),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cat.color, Color.lerp(cat.color, Colors.black, 0.32)!],
          ),
        ),
        child: Row(
          children: [
            Icon(cat.iconData, size: 20, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                cat.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Результаты ────────────────────────────────────────────────────────────

  Widget _results(SeeUThemeColors c) {
    final params =
        AudioSearchParams(query: _query, category: _category, sort: _sort);
    final async = ref.watch(audioSearchProvider(params));

    return async.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: SeeUColors.accent),
      ),
      error: (_, __) =>
          AudioErrorState(onRetry: () => ref.invalidate(audioSearchProvider(params))),
      data: (res) {
        if (res.tracks.isEmpty) return _nothingFound(c);
        final author = _authorHit(res.tracks);

        return ListView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + context.bottomBarInset),
          children: [
            _filterChips(c),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '≈ ${res.total} ${_resultsWord(res.total)}',
                  style: TextStyle(fontSize: 13, color: c.ink3),
                ),
                const Spacer(),
                _sortSwitch(c),
              ],
            ),

            // Хит по автору: artist — строка, а не сущность, поэтому страницы
            // автора нет — есть поиск по его имени.
            if (author != null) ...[
              const SizedBox(height: 16),
              _kicker('АВТОР', c),
              const SizedBox(height: 8),
              Tappable.scaled(
                onTap: () => _useQuery(author),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.line),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.surface2,
                        ),
                        child:
                            Icon(PhosphorIcons.user(), size: 18, color: c.ink3),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '«$_query» у $author',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: c.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'искать по автору',
                              style: TextStyle(fontSize: 11.5, color: c.ink3),
                            ),
                          ],
                        ),
                      ),
                      Icon(PhosphorIcons.arrowUpRight(),
                          size: 16, color: c.ink3),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),
            _kicker('ТРЕКИ', c),
            const SizedBox(height: 10),
            for (var i = 0; i < res.tracks.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TrackRow(
                  track: res.tracks[i],
                  queue: res.tracks,
                  index: i,
                  source: 'search',
                  trailing: TrackRowTrailing.play,
                ),
              ),
          ],
        );
      },
    );
  }

  /// Имя автора из выдачи — по нему и предлагаем искать.
  String? _authorHit(List<AudioTrack> tracks) {
    if (_query.length < 2) return null;
    final q = _query.toLowerCase();
    for (final t in tracks) {
      if (t.artist.isNotEmpty && t.artist.toLowerCase() != q) return t.artist;
    }
    return null;
  }

  Widget _filterChips(SeeUThemeColors c) {
    final items = <(String, String)>[
      ('', 'Все'),
      for (final cat in kAudioCategories) (cat.id, cat.title),
    ];

    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (id, label) = items[i];
          final active = _category == id;
          return Tappable.scaled(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _category = id);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? c.ink : c.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: active ? c.ink : c.line),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? c.bg : c.ink2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sortSwitch(SeeUThemeColors c) {
    const sorts = [
      ('trending', 'Тренды'),
      ('new', 'Новое'),
      ('popular', 'Популярное'),
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (id, label) in sorts)
            Tappable(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _sort = id);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: _sort == id ? c.surface : null,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: _sort == id ? FontWeight.w600 : FontWeight.w500,
                    color: _sort == id ? c.ink : c.ink3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Ничего не найдено ─────────────────────────────────────────────────────

  Widget _nothingFound(SeeUThemeColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(44, 90, 44, 0),
      children: [
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.surface2),
            child: Icon(PhosphorIcons.waveformSlash(), size: 42, color: c.ink4),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Пусто по запросу',
          textAlign: TextAlign.center,
          style: SeeUTypography.displayS.copyWith(fontSize: 24, color: c.ink),
        ),
        const SizedBox(height: 10),
        Text(
          'Ничего не нашли по «$_query». Проверь опечатку или попробуй короче.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.55, color: c.ink3),
        ),
        const SizedBox(height: 22),
        Center(
          child: Tappable.scaled(
            onTap: () => context.push('/music/upload'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: c.ink,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsFill.uploadSimple, size: 16, color: c.bg),
                  const SizedBox(width: 8),
                  Text(
                    'Загрузить свой трек',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.bg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Tappable(
            onTap: _clear,
            child: Text(
              'Или загляни в «Набирают»',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AudioColors.kicker(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _kicker(String text, SeeUThemeColors c) => Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: c.ink3,
        ),
      );

  static String _resultsWord(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m100 >= 11 && m100 <= 14) return 'результатов';
    if (m10 == 1) return 'результат';
    if (m10 >= 2 && m10 <= 4) return 'результата';
    return 'результатов';
  }
}

/// «Пропала связь» — не «Ошибка 500». И честно: играющий трек не прервётся.
class AudioErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const AudioErrorState({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 44),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: c.surface2),
              child: Icon(PhosphorIcons.wifiSlash(), size: 42, color: c.ink3),
            ),
            const SizedBox(height: 22),
            Text(
              'Пропала связь',
              style:
                  SeeUTypography.displayS.copyWith(fontSize: 24, color: c.ink),
            ),
            const SizedBox(height: 10),
            Text(
              'Не смогли загрузить. Проверь интернет — трек, который играет, '
              'при этом не прервётся.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.55, color: c.ink3),
            ),
            const SizedBox(height: 22),
            Tappable.scaled(
              onTap: onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                decoration: BoxDecoration(
                  color: c.ink,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsBold.arrowClockwise,
                        size: 15, color: c.bg),
                    const SizedBox(width: 8),
                    Text(
                      'Повторить',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: c.bg,
                      ),
                    ),
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
