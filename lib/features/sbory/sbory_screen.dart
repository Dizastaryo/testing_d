import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/config/app_config.dart';
import '../../core/design/design.dart';
import '../../core/models/sbor.dart';
import '../../core/providers/sbory_city_provider.dart';
import 'sbory_widgets.dart';

// ─── Provider ────────────────────────────────────────────────────

/// Increment to force-refresh all sbory lists (after leave/cancel/create).
final sborRefreshProvider = StateProvider<int>((ref) => 0);

/// Параметр провайдера: тип-фильтр + категория + город.
typedef _SboryParams = ({String? type, String? category, String city});

final _sboryProvider = FutureProvider.autoDispose
    .family<List<Sbor>, _SboryParams>((ref, p) async {
  ref.watch(sborRefreshProvider);
  final api = ref.read(apiClientProvider);
  final params = <String, dynamic>{};
  if (p.type != null && p.type!.isNotEmpty) params['type'] = p.type;
  if (p.category != null && p.category!.isNotEmpty) params['category'] = p.category;
  if (p.city.isNotEmpty) params['city'] = p.city;
  final r = await api.get(ApiEndpoints.sbory, queryParameters: params);
  final data = r.data is Map ? r.data['data'] ?? r.data['items'] ?? [] : r.data;
  return (data as List<dynamic>)
      .map((e) => Sbor.fromJson(e as Map<String, dynamic>))
      .toList();
});

final _mySboryProvider = FutureProvider.autoDispose<List<Sbor>>((ref) async {
  ref.watch(sborRefreshProvider);
  final api = ref.read(apiClientProvider);
  final r = await api.get(ApiEndpoints.mySbory);
  final data = r.data is Map ? r.data['data'] ?? r.data['items'] ?? [] : r.data;
  return (data as List<dynamic>)
      .map((e) => Sbor.fromJson(e as Map<String, dynamic>))
      .toList();
});

final _bookmarkedSboryProvider = FutureProvider.autoDispose<List<Sbor>>((ref) async {
  ref.watch(sborRefreshProvider);
  final api = ref.read(apiClientProvider);
  final r = await api.get(ApiEndpoints.bookmarkedSbory);
  final data = r.data is Map ? r.data['data'] ?? r.data['items'] ?? [] : r.data;
  return (data as List<dynamic>)
      .map((e) => Sbor.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ─── Screen ──────────────────────────────────────────────────────

class SboryScreen extends ConsumerStatefulWidget {
  const SboryScreen({super.key});

  @override
  ConsumerState<SboryScreen> createState() => _SboryScreenState();
}

class _SboryScreenState extends ConsumerState<SboryScreen> {
  String? _typeFilter; // null = all, 'offline', 'online'
  bool _showMine = false;
  bool _showBookmarked = false;
  SborCategory? _catFilter;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Инициализируем город — только при первом заходе запрашивает геолокацию.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sboryCityProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openCityPicker() async {
    final c = context.seeuColors;
    final current = ref.read(sboryCityProvider);
    final controller = TextEditingController();
    String query = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final filtered = query.isEmpty
                ? kKazakhstanCities
                : kKazakhstanCities
                    .where((city) =>
                        city.name.toLowerCase().contains(query.toLowerCase()))
                    .toList();
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: c.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Title
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Row(
                      children: [
                        Text(
                          'Выбери город',
                          style: SeeUTypography.subtitle.copyWith(color: c.ink),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Icon(PhosphorIcons.x(), color: c.ink3, size: 20),
                        ),
                      ],
                    ),
                  ),
                  // Search
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.line),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(PhosphorIcons.magnifyingGlass(),
                              size: 16, color: c.ink3),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: controller,
                              autofocus: false,
                              decoration: InputDecoration(
                                hintText: 'Поиск города...',
                                hintStyle:
                                    TextStyle(fontSize: 14, color: c.ink3),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              style: TextStyle(fontSize: 14, color: c.ink),
                              onChanged: (v) => setSheet(() => query = v),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // City list
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 20),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final city = filtered[i];
                        final isSelected = city.name == current;
                        return ListTile(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            ref
                                .read(sboryCityProvider.notifier)
                                .selectCity(city.name);
                            Navigator.pop(ctx);
                          },
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          leading: Icon(
                            PhosphorIcons.mapPin(),
                            size: 18,
                            color: isSelected ? SeeUColors.accent : c.ink3,
                          ),
                          title: Text(
                            city.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: isSelected ? SeeUColors.accent : c.ink,
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(PhosphorIconsBold.checkCircle,
                                  size: 18, color: SeeUColors.accent)
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final city = ref.watch(sboryCityProvider);
    final catName = _catFilter?.name;
    final async = _showBookmarked
        ? ref.watch(_bookmarkedSboryProvider)
        : _showMine
            ? ref.watch(_mySboryProvider)
            : ref.watch(_sboryProvider((type: _typeFilter, category: catName, city: city)));

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(c),
            _buildSearchBar(c),
            _buildTypeToggle(c),
            _buildCategoryChips(c),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIcons.warning(),
                          size: 40, color: c.ink3),
                      const SizedBox(height: 12),
                      Text('Не удалось загрузить', style: TextStyle(color: c.ink3)),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          if (_showBookmarked) {
                            ref.invalidate(_bookmarkedSboryProvider);
                          } else if (_showMine) {
                            ref.invalidate(_mySboryProvider);
                          } else {
                            final c2 = ref.read(sboryCityProvider);
                            ref.invalidate(_sboryProvider((type: _typeFilter, category: _catFilter?.name, city: c2)));
                          }
                        },
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
                data: (items) {
                  // For Mine/Bookmarked: apply category client-side (no server-side param).
                  // For main feed: category is already server-filtered.
                  var filtered = (_catFilter != null && (_showMine || _showBookmarked))
                      ? items.where((s) => s.category == _catFilter).toList()
                      : items;
                  if (_searchQuery.isNotEmpty) {
                    final q = _searchQuery.toLowerCase();
                    filtered = filtered
                        .where((s) =>
                            s.title.toLowerCase().contains(q) ||
                            s.place.toLowerCase().contains(q))
                        .toList();
                  }
                  if (filtered.isEmpty) {
                    return _buildEmpty(c);
                  }
                  return _buildList(c, filtered);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SeeUThemeColors c) {
    final city = ref.watch(sboryCityProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _openCityPicker();
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'СБОРЫ РЯДОМ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: c.ink3,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      city,
                      style: SeeUTypography.displayM.copyWith(
                        color: c.ink,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(PhosphorIcons.caretDown(PhosphorIconsStyle.bold),
                        size: 14, color: c.ink2),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          _IconBtn(
            icon: PhosphorIcons.plus(PhosphorIconsStyle.bold),
            onTap: () {
              HapticFeedback.selectionClick();
              context.push('/sbory/create');
            },
            color: c.ink,
            iconColor: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            Icon(PhosphorIcons.magnifyingGlass(), size: 15, color: c.ink3),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Поиск сборов...',
                  hintStyle: TextStyle(fontSize: 14, color: c.ink3),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                style: TextStyle(fontSize: 14, color: c.ink),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(PhosphorIcons.x(), size: 14, color: c.ink3),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeToggle(SeeUThemeColors c) {
    final tabs = [
      (null, 'Все', null as IconData?),
      ('offline', 'Оффлайн', PhosphorIcons.mapPin()),
      ('online', 'Онлайн', PhosphorIcons.globe()),
    ];
    return SizedBox(
      height: 48,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        scrollDirection: Axis.horizontal,
        children: [
          for (final (type, label, icon) in tabs) ...[
            _TypeChip(
              label: label,
              icon: icon,
              active: _typeFilter == type && !_showMine && !_showBookmarked,
              color: c,
              onTap: () => setState(() {
                _typeFilter = type;
                _showMine = false;
                _showBookmarked = false;
              }),
            ),
            const SizedBox(width: 6),
          ],
          _TypeChip(
            label: 'Мои',
            icon: PhosphorIcons.user(PhosphorIconsStyle.fill),
            active: _showMine && !_showBookmarked,
            color: c,
            onTap: () => setState(() {
              _showMine = true;
              _showBookmarked = false;
              _typeFilter = null;
            }),
          ),
          const SizedBox(width: 6),
          _TypeChip(
            label: 'Сохранённые',
            icon: PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.fill),
            active: _showBookmarked,
            color: c,
            onTap: () => setState(() {
              _showBookmarked = true;
              _showMine = false;
              _typeFilter = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips(SeeUThemeColors c) {
    final chips = [
      (null, 'Любая', PhosphorIcons.star()),
      (SborCategory.basketball, 'Спорт', PhosphorIcons.basketball()),
      (SborCategory.games, 'Игры', PhosphorIcons.gameController()),
      (SborCategory.hike, 'Природа', PhosphorIcons.mountains()),
      (SborCategory.draw, 'Творчество', PhosphorIcons.paintBrush()),
      (SborCategory.board, 'Настолки', PhosphorIcons.diceFive()),
      (SborCategory.cinema, 'Кино', PhosphorIcons.filmStrip()),
      (SborCategory.music, 'Музыка', PhosphorIcons.musicNote()),
      (SborCategory.food, 'Готовим', PhosphorIcons.forkKnife()),
      (SborCategory.read, 'Книги', PhosphorIcons.book()),
      (SborCategory.other, 'Другое', PhosphorIcons.sparkle()),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final (cat, label, icon) = chips[i];
          final active = _catFilter == cat;
          return GestureDetector(
            onTap: () {
              setState(() => _catFilter = cat);
              if (!_showMine && !_showBookmarked) {
                final city2 = ref.read(sboryCityProvider);
                ref.invalidate(_sboryProvider((type: _typeFilter, category: cat?.name, city: city2)));
              }
            },
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: active ? c.ink : c.surface,
                borderRadius: BorderRadius.circular(999),
                border: active ? null : Border.all(color: c.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: active ? Colors.white : c.ink2),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: active ? Colors.white : c.ink2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildList(SeeUThemeColors c, List<Sbor> items) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final s = items[i];
        if (i == 0 && s.live) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SborHeroCard(sbor: s, onTap: () => _openDetail(s.id)),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SborCard(sbor: s, onTap: () => _openDetail(s.id)),
        );
      },
    );
  }

  bool get _hasActiveFilter =>
      _catFilter != null || _typeFilter != null || _showMine || _showBookmarked || _searchQuery.isNotEmpty;

  void _resetFilters() {
    setState(() {
      _catFilter = null;
      _typeFilter = null;
      _showMine = false;
      _showBookmarked = false;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  Widget _buildEmpty(SeeUThemeColors c) {
    final hasFilter = _hasActiveFilter;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasFilter ? PhosphorIcons.funnel() : PhosphorIcons.usersThree(),
            size: 48, color: c.ink4,
          ),
          const SizedBox(height: 12),
          Text(
            hasFilter ? 'Ничего не найдено' : 'Сборов пока нет',
            style: SeeUTypography.subtitle.copyWith(color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(
            hasFilter
                ? 'Попробуй другие фильтры'
                : 'Создай первый — остальные подтянутся',
            style: TextStyle(fontSize: 13, color: c.ink3),
          ),
          const SizedBox(height: 20),
          if (hasFilter)
            GestureDetector(
              onTap: _resetFilters,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIcons.arrowCounterClockwise(), size: 16, color: c.ink2),
                    const SizedBox(width: 8),
                    Text(
                      'Сбросить фильтры',
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            GestureDetector(
              onTap: () => context.push('/sbory/create'),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsBold.plus, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Создать сбор',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
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

  void _openDetail(String id) {
    HapticFeedback.selectionClick();
    context.push('/sbory/$id');
  }
}

// ─── Type toggle chip (scrollable row) ───────────────────────────

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool active;
  final SeeUThemeColors color;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? color.ink : color.surface,
          borderRadius: BorderRadius.circular(999),
          border: active ? null : Border.all(color: color.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: active ? Colors.white : color.ink2),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? Colors.white : color.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color iconColor;

  const _IconBtn({
    required this.icon,
    required this.onTap,
    required this.color,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Icon(icon, size: 17, color: iconColor),
      ),
    );
  }
}

// ─── SborCard ────────────────────────────────────────────────────

class SborCard extends StatelessWidget {
  final Sbor sbor;
  final VoidCallback? onTap;
  final bool compact;

  const SborCard({super.key, required this.sbor, this.onTap, this.compact = false});

  String? _resolvedCoverUrl(Sbor s) {
    final url = s.coverUrl;
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    return '${AppConfig.apiOrigin}$url';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final s = sbor;
    final meta = s.categoryMeta;
    final coverUrl = _resolvedCoverUrl(s);
    final headerH = coverUrl != null ? 140.0 : 96.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.line, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF161310).withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: const Color(0xFF161310).withValues(alpha: 0.04),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header strip ──────────────────────────────────────
            SizedBox(
              height: headerH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Background
                  if (coverUrl != null)
                    CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(color: meta.soft),
                    )
                  else
                    Container(color: meta.soft),
                  // Cover gradient overlay
                  if (coverUrl != null)
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.28),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.32),
                          ],
                        ),
                      ),
                    ),
                  // Watermark icon (no cover)
                  if (coverUrl == null)
                    Positioned(
                      right: -14, bottom: -34,
                      child: Opacity(
                        opacity: 0.16,
                        child: Icon(meta.icon, size: 150, color: meta.color),
                      ),
                    ),
                  // Pills (top-left): category + format + price + live
                  Positioned(
                    top: 12, left: 12,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _HeaderPill(
                          icon: meta.icon,
                          label: meta.name,
                          color: meta.color,
                          bg: Colors.white,
                        ),
                        _HeaderPill(
                          icon: s.type == SborType.online
                              ? PhosphorIcons.globe()
                              : PhosphorIcons.mapPin(),
                          label: s.type == SborType.online ? 'Онлайн' : 'Оффлайн',
                          color: c.ink2,
                          bg: Colors.white.withValues(alpha: 0.75),
                        ),
                        if (s.price > 0)
                          _HeaderPill(
                            label: '${s.price} ₸',
                            color: SeeUColors.accent,
                            bg: SeeUColors.accentSoft,
                          ),
                        if (s.live)
                          _HeaderPill(
                            icon: null,
                            label: '● СЕЙЧАС',
                            color: Colors.white,
                            bg: Colors.redAccent.withValues(alpha: 0.85),
                          ),
                      ],
                    ),
                  ),
                  // Date chip (top-right)
                  Positioned(
                    top: 12, right: 12,
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 8, offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIcons.calendarBlank(), size: 12, color: meta.color),
                          const SizedBox(width: 5),
                          Text(
                            s.when,
                            style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700,
                              color: Color(0xFF161310),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Body ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    s.title,
                    style: const TextStyle(
                      fontFamily: 'Fraunces',
                      fontSize: 21, fontWeight: FontWeight.w500,
                      letterSpacing: -0.3, height: 1.18,
                    ),
                  ),
                  const SizedBox(height: 9),
                  // Meta: place + dot + distance/whenSub
                  Row(
                    children: [
                      Icon(
                        s.type == SborType.online
                            ? PhosphorIcons.headphones()
                            : PhosphorIcons.mapPinLine(),
                        size: 14, color: c.ink3,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          s.place.isNotEmpty ? s.place : 'Онлайн',
                          style: TextStyle(fontSize: 13, color: c.ink2),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if ((s.distance ?? s.whenSub) != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Container(
                            width: 3, height: 3,
                            decoration: BoxDecoration(color: c.ink4, shape: BoxShape.circle),
                          ),
                        ),
                        Text(
                          s.distance ?? s.whenSub!,
                          style: TextStyle(fontSize: 13, color: c.ink3),
                        ),
                      ],
                    ],
                  ),
                  // Divider + footer
                  Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 14),
                    child: Container(height: 1, color: c.line),
                  ),
                  Row(
                    children: [
                      SboryAvatarStack(names: s.memberNames, avatarUrls: s.memberAvatarUrls, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.max != null
                                  ? '${s.joined} из ${s.max}'
                                  : '${s.joined} чел.',
                              style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600, color: c.ink,
                              ),
                            ),
                            Text(
                              s.isFull
                                  ? 'мест нет'
                                  : s.max != null
                                      ? 'нужно ещё ${s.remaining}'
                                      : 'открытый сбор',
                              style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w500,
                                color: s.isFull ? c.ink3 : SeeUColors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _JoinBtn(
                        isFull: s.isFull,
                        isJoined: s.isJoined,
                        requestStatus: s.myRequestStatus,
                        c: c,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── SborHeroCard ────────────────────────────────────────────────

class SborHeroCard extends StatelessWidget {
  final Sbor sbor;
  final VoidCallback? onTap;

  const SborHeroCard({super.key, required this.sbor, this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = sbor;
    final meta = s.categoryMeta;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [SeeUColors.accent, SeeUColors.accentSecondary, SeeUColors.amber],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0, 0.55, 1],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: SeeUColors.accent.withValues(alpha: 0.28),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Background category icon
            Positioned(
              right: -20, bottom: -28,
              child: Opacity(
                opacity: 0.22,
                child: Icon(meta.icon, size: 160, color: Colors.white),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.4),
                            blurRadius: 0,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'ПРЯМО СЕЙЧАС',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    if (s.whenSub != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          s.whenSub!,
                          style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  s.title,
                  style: const TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.4,
                    height: 1.1,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SboryAvatarStack(names: s.memberNames, size: 28, ringColor: Colors.transparent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.max != null
                            ? '${s.joined} из ${s.max} · ждём ${s.remaining}'
                            : '${s.joined} участников',
                        style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500,
                          color: Colors.white, height: 1,
                        ),
                      ),
                    ),
                    Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        children: [
                          Text(
                            'Зайти',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: SeeUColors.accent,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            PhosphorIcons.arrowRight(PhosphorIconsStyle.bold),
                            size: 13, color: SeeUColors.accent,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Small helpers ───────────────────────────────────────────────

class _HeaderPill extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color color;
  final Color bg;

  const _HeaderPill({
    this.icon,
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class _JoinBtn extends StatelessWidget {
  final bool isFull;
  final bool isJoined;
  final String requestStatus;
  final SeeUThemeColors c;

  const _JoinBtn({
    required this.isFull,
    required this.isJoined,
    required this.requestStatus,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    // Already a member
    if (isJoined) {
      return _pill(SeeUColors.accentSoft, 'Я иду', SeeUColors.accent);
    }
    // Full — no slots
    if (isFull) {
      return _pill(c.surface2, 'Нет мест', c.ink3);
    }
    // Pending request
    if (requestStatus == 'pending') {
      return _pill(c.surface2, 'Ждём', c.ink3);
    }
    // Default: can join / re-apply
    return _pill(c.ink, 'Участвую', Colors.white);
  }

  Widget _pill(Color bg, String label, Color textColor) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
        ),
      ),
    );
  }
}

