import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/audio_category.dart';
import '../../core/providers/audio_discovery_provider.dart';
import 'audio_design.dart';
import 'music_search_screen.dart' show AudioErrorState;
import 'widgets/track_row.dart';

/// Экран категории.
///
/// У «Музыки» шестнадцать подкатегорий. Стена из шестнадцати чипов съедает
/// первый экран и пугает, поэтому здесь **рельс**: одна строка, листается вбок,
/// «Все» слева — точка возврата, активный чип красится цветом категории.
/// У «Новостей» и «Другого» подкатегорий нет — рельс не рисуется вовсе.
class CategoryScreen extends ConsumerStatefulWidget {
  final String categoryId;

  const CategoryScreen({super.key, required this.categoryId});

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  String _subcategory = '';
  String _sort = 'trending';

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final cat = findCategory(widget.categoryId);

    if (cat == null) {
      return Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                child: Row(
                  children: [
                    AudioSquareButton(
                      icon: PhosphorIcons.arrowLeft(),
                      onTap: () => context.pop(),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Категория не найдена',
                style: SeeUTypography.displayS
                    .copyWith(fontSize: 22, color: c.ink),
              ),
              const Spacer(),
            ],
          ),
        ),
      );
    }

    final params = CategoryTracksParams(
      category: cat.id,
      subcategory: _subcategory,
      sort: _sort,
    );
    final async = ref.watch(audioCategoryTracksProvider(params));

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
              child: AudioSquareButton(
                icon: PhosphorIcons.arrowLeft(),
                onTap: () => context.pop(),
              ),
            ),
            _hero(c, cat, async.valueOrNull?.total ?? cat.trackCount),
            if (cat.subcategories.isNotEmpty) _rail(c, cat),
            Expanded(
              child: async.when(
                loading: () => const Center(
                  child: AudioListSkeleton(rows: 7),
                ),
                error: (_, __) => AudioErrorState(
                  onRetry: () =>
                      ref.invalidate(audioCategoryTracksProvider(params)),
                ),
                data: (data) {
                  if (data.tracks.isEmpty) return _empty(c, cat);
                  return ListView(
                    padding: EdgeInsets.fromLTRB(
                        22, 16, 22, 24 + context.bottomBarInset),
                    children: [
                      Row(
                        children: [
                          Text(
                            'Треки',
                            style: SeeUTypography.displayS.copyWith(
                              fontSize: 19,
                              color: c.ink,
                            ),
                          ),
                          const Spacer(),
                          Tappable(
                            onTap: _cycleSort,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(PhosphorIcons.sortAscending(),
                                    size: 14, color: c.ink3),
                                const SizedBox(width: 6),
                                Text(
                                  _sortLabel,
                                  style:
                                      TextStyle(fontSize: 12.5, color: c.ink3),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (var i = 0; i < data.tracks.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 15),
                          child: TrackRow(
                            track: data.tracks[i],
                            queue: data.tracks,
                            index: i,
                            source: 'category',
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Шапка категории ───────────────────────────────────────────────────────

  Widget _hero(SeeUThemeColors c, AudioCategoryModel cat, int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: cat.color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(cat.iconData, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text(
                'КАТЕГОРИЯ',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: AudioColors.kicker(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Заголовок цветом категории — экран сразу «музыкальный» или
          // «подкастовый», без подписи.
          Text(
            cat.title,
            style: SeeUTypography.displayS.copyWith(
              fontSize: 36,
              letterSpacing: -1,
              color: cat.color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (total > 0) '$total ${_tracksWord(total)}',
              if (cat.description.isNotEmpty) cat.description,
            ].join(' · '),
            style: TextStyle(fontSize: 13, color: c.ink3),
          ),
        ],
      ),
    );
  }

  // ── Рельс подкатегорий ────────────────────────────────────────────────────

  Widget _rail(SeeUThemeColors c, AudioCategoryModel cat) {
    final items = <(String, String)>[
      ('', 'Все'),
      for (final s in cat.subcategories) (s.id, s.titleRu),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final (id, label) = items[i];
              final active = _subcategory == id;
              return Tappable.scaled(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _subcategory = id);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? cat.color : c.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: active ? cat.color : c.line),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active ? Colors.white : c.ink2,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (cat.subcategories.length > 4)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
            child: Text(
              '← листай вбок · ${cat.subcategories.length} подкатегорий',
              style: TextStyle(fontSize: 10.5, color: c.ink4),
            ),
          ),
      ],
    );
  }

  // ── Пусто ─────────────────────────────────────────────────────────────────

  Widget _empty(SeeUThemeColors c, AudioCategoryModel cat) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(44, 70, 44, 0),
      children: [
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cat.color.withValues(alpha: 0.12),
            ),
            child: Icon(cat.iconData, size: 38, color: cat.color),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _subcategory.isEmpty ? 'Здесь пока пусто' : 'В этой ветке пусто',
          textAlign: TextAlign.center,
          style: SeeUTypography.displayS.copyWith(fontSize: 22, color: c.ink),
        ),
        const SizedBox(height: 8),
        Text(
          _subcategory.isEmpty
              ? 'Загрузи первый трек в эту категорию — он появится здесь'
              : 'Попробуй соседнюю подкатегорию или вернись ко «Всем»',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: c.ink3),
        ),
        if (_subcategory.isNotEmpty) ...[
          const SizedBox(height: 20),
          Center(
            child: Tappable.scaled(
              onTap: () => setState(() => _subcategory = ''),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                decoration: BoxDecoration(
                  color: cat.color,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Показать все',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Сортировка ────────────────────────────────────────────────────────────

  static const _sorts = ['trending', 'new', 'popular'];

  String get _sortLabel => switch (_sort) {
        'new' => 'Новое',
        'popular' => 'Популярное',
        _ => 'Тренды',
      };

  void _cycleSort() {
    HapticFeedback.selectionClick();
    final i = _sorts.indexOf(_sort);
    setState(() => _sort = _sorts[(i + 1) % _sorts.length]);
  }

  static String _tracksWord(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m100 >= 11 && m100 <= 14) return 'треков';
    if (m10 == 1) return 'трек';
    if (m10 >= 2 && m10 <= 4) return 'трека';
    return 'треков';
  }
}
