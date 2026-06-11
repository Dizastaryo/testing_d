import 'dart:async';

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

/// Параметр провайдера: тип-фильтр + категория + город + диапазон дат + поиск.
typedef _SboryParams = ({
  String? type,
  String? category,
  String city,
  DateTime? dateFrom,
  DateTime? dateTo,
  String q,
});

final _sboryProvider = FutureProvider.autoDispose
    .family<List<Sbor>, _SboryParams>((ref, p) async {
  ref.watch(sborRefreshProvider);
  final api = ref.read(apiClientProvider);
  final params = <String, dynamic>{};
  if (p.type != null && p.type!.isNotEmpty) params['type'] = p.type;
  if (p.category != null && p.category!.isNotEmpty) params['category'] = p.category;
  if (p.city.isNotEmpty) params['city'] = p.city;
  if (p.dateFrom != null) params['date_from'] = p.dateFrom!.toUtc().toIso8601String();
  if (p.dateTo != null) params['date_to'] = p.dateTo!.toUtc().toIso8601String();
  if (p.q.isNotEmpty) params['q'] = p.q;
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

final _sborHistoryProvider = FutureProvider.autoDispose<List<Sbor>>((ref) async {
  ref.watch(sborRefreshProvider);
  final api = ref.read(apiClientProvider);
  final r = await api.get(ApiEndpoints.mySboryHistory);
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
  DateTimeRange? _dateFilter;
  String? _datePreset;
  String _searchQuery = '';
  bool _showSearch = false;
  bool _isSearchPending = false; // true между вводом и срабатыванием debounce
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

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
    _searchDebounce?.cancel();
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
                    child: TextField(
                      controller: controller,
                      autofocus: false,
                      style: TextStyle(fontSize: 14, color: c.ink),
                      onChanged: (v) => setSheet(() => query = v),
                      decoration: InputDecoration(
                        hintText: 'Поиск города...',
                        hintStyle: TextStyle(fontSize: 14, color: c.ink3),
                        filled: true,
                        fillColor: c.surface,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 14, right: 10),
                          child: Icon(PhosphorIcons.magnifyingGlass(), size: 16, color: c.ink3),
                        ),
                        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: c.line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: c.line),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: c.line, width: 1.5),
                        ),
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
            : ref.watch(_sboryProvider((
                type: _typeFilter,
                category: catName,
                city: city,
                dateFrom: _dateFilter?.start,
                dateTo: _dateFilter?.end,
                q: _searchQuery,
              )));

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(c),
            if (_showSearch) _buildSearchBar(c),
            _buildCategoryChips(c),
            _buildTypeToggle(c),
            Expanded(
              child: _isSearchPending
                  ? const SeeUSborCardSkeleton()
                  : async.when(
                loading: () => const SeeUSborCardSkeleton(),
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
                            ref.invalidate(_sboryProvider((type: _typeFilter, category: _catFilter?.name, city: c2, dateFrom: _dateFilter?.start, dateTo: _dateFilter?.end, q: _searchQuery)));
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
                  // Search: server handles it for main feed (via ?q=).
                  // For Mine/Bookmarked: apply client-side since those endpoints don't accept ?q=.
                  if (_searchQuery.isNotEmpty && (_showMine || _showBookmarked)) {
                    final q = _searchQuery.toLowerCase();
                    filtered = filtered
                        .where((s) =>
                            s.title.toLowerCase().contains(q) ||
                            s.place.toLowerCase().contains(q))
                        .toList();
                  }
                  // Date filter: server handles it for main feed. Apply client-side
                  // only for Mine/Bookmarked tabs that don't send date params.
                  if (_dateFilter != null && (_showMine || _showBookmarked)) {
                    final df = _dateFilter!;
                    final endOfDay = df.end.add(const Duration(days: 1));
                    filtered = filtered.where((s) {
                      if (s.scheduledAt == null) return false;
                      return !s.scheduledAt!.isBefore(df.start) &&
                          s.scheduledAt!.isBefore(endOfDay);
                    }).toList();
                  }
                  if (filtered.isEmpty && !_showMine) {
                    return _buildEmpty(c);
                  }
                  if (_showMine) {
                    return _buildMineWithHistory(c, filtered);
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
            child: Row(
              children: [
                Text(
                  city,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(PhosphorIcons.caretDown(PhosphorIconsStyle.bold),
                    size: 14, color: c.ink2),
              ],
            ),
          ),
          const Spacer(),
          _IconBtn(
            icon: PhosphorIcons.magnifyingGlass(),
            onTap: () => setState(() => _showSearch = !_showSearch),
            color: c.surface,
            iconColor: c.ink2,
          ),
          const SizedBox(width: 8),
          _IconBtn(
            icon: PhosphorIcons.plus(PhosphorIconsStyle.bold),
            onTap: () {
              HapticFeedback.selectionClick();
              context.push('/sbory/create');
            },
            color: SeeUColors.accent,
            iconColor: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(SeeUThemeColors c) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c.line),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: TextField(
        controller: _searchController,
        style: TextStyle(fontSize: 14, color: c.ink),
        onChanged: (v) {
          _searchDebounce?.cancel();
          // Immediately show skeleton so user sees feedback before debounce fires.
          setState(() => _isSearchPending = true);
          _searchDebounce = Timer(const Duration(milliseconds: 350), () {
            if (mounted) setState(() { _searchQuery = v; _isSearchPending = false; });
          });
        },
        decoration: InputDecoration(
          hintText: 'Поиск сборов...',
          hintStyle: TextStyle(fontSize: 14, color: c.ink3),
          filled: true,
          fillColor: c.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: Icon(PhosphorIcons.magnifyingGlass(), size: 16, color: c.ink3),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(PhosphorIcons.x(), size: 14, color: c.ink3),
                  ),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          border: border,
          enabledBorder: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: c.line, width: 1.5),
          ),
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
    final dateActive = _dateFilter != null;
    final dateLabel = dateActive
        ? (_datePreset ?? _fmtDateRange(_dateFilter!))
        : 'Дата';
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        scrollDirection: Axis.horizontal,
        itemCount: chips.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          // Last item is date filter chip
          if (i == chips.length) {
            return GestureDetector(
              onTap: () async {
                final result = await showModalBottomSheet<SboryDateResult>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => SboryDateFilterSheet(initialRange: _dateFilter),
                );
                if (result != null) {
                  setState(() {
                    _dateFilter  = result.range;
                    _datePreset  = result.presetLabel;
                  });
                }
              },
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: dateActive ? SeeUColors.accent : c.surface,
                  borderRadius: BorderRadius.circular(SeeURadii.pill),
                  border: Border.all(
                    color: dateActive ? SeeUColors.accent : c.line,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIcons.calendarBlank(), size: 14,
                        color: dateActive ? Colors.white : c.ink2),
                    const SizedBox(width: 6),
                    Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: dateActive ? FontWeight.w600 : FontWeight.w500,
                        color: dateActive ? Colors.white : c.ink2,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final (cat, label, icon) = chips[i];
          final active = _catFilter == cat;
          return GestureDetector(
            onTap: () {
              setState(() => _catFilter = cat);
              if (!_showMine && !_showBookmarked) {
                final city2 = ref.read(sboryCityProvider);
                ref.invalidate(_sboryProvider((type: _typeFilter, category: cat?.name, city: city2, dateFrom: _dateFilter?.start, dateTo: _dateFilter?.end, q: _searchQuery)));
              }
            },
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: active ? SeeUColors.accent : c.surface,
                borderRadius: BorderRadius.circular(SeeURadii.pill),
                border: Border.all(
                  color: active ? SeeUColors.accent : c.line,
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: active ? Colors.white : c.ink2),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
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

  Future<void> _refresh() {
    if (_showBookmarked) {
      return ref.refresh(_bookmarkedSboryProvider.future);
    } else if (_showMine) {
      return ref.refresh(_mySboryProvider.future);
    } else {
      final city = ref.read(sboryCityProvider);
      return ref.refresh(
          _sboryProvider((type: _typeFilter, category: _catFilter?.name, city: city, dateFrom: _dateFilter?.start, dateTo: _dateFilter?.end, q: _searchQuery)).future);
    }
  }

  Widget _buildList(SeeUThemeColors c, List<Sbor> items) {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: SeeUColors.accent,
      child: ListView.builder(
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
      ),
    );
  }

  Widget _buildMineWithHistory(SeeUThemeColors c, List<Sbor> upcoming) {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: SeeUColors.accent,
      child: CustomScrollView(
        slivers: [
          // Upcoming
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            sliver: upcoming.isEmpty
                ? SliverToBoxAdapter(child: _buildMineEmptyUpcoming(c))
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SborCard(sbor: upcoming[i], onTap: () => _openDetail(upcoming[i].id)),
                      ),
                      childCount: upcoming.length,
                    ),
                  ),
          ),
          // History section
          SliverToBoxAdapter(
            child: Consumer(builder: (ctx, ref2, _) {
              final histAsync = ref2.watch(_sborHistoryProvider);
              return histAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (history) {
                  if (history.isEmpty) return const SizedBox(height: 24);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                        child: Row(
                          children: [
                            Icon(PhosphorIcons.clockCounterClockwise(), size: 14, color: c.ink3),
                            const SizedBox(width: 6),
                            Text(
                              'ИСТОРИЯ',
                              style: TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 11, fontWeight: FontWeight.w600,
                                letterSpacing: 0.8, color: c.ink3,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: c.surface2,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${history.length}',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c.ink3),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...history.map((s) => Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: Opacity(
                          opacity: 0.65,
                          child: SborCard(sbor: s, onTap: () => _openDetail(s.id)),
                        ),
                      )),
                      const SizedBox(height: 24),
                    ],
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildMineEmptyUpcoming(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIcons.usersThree(), size: 48, color: c.ink4),
          const SizedBox(height: 12),
          Text('Нет предстоящих сборов', style: SeeUTypography.subtitle.copyWith(color: c.ink)),
          const SizedBox(height: 6),
          Text(
            'Вы ещё не вступали в сборы или все уже прошли',
            style: TextStyle(fontSize: 13, color: c.ink3),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              context.push('/sbory/create');
            },
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: SeeUColors.accent,
                borderRadius: BorderRadius.circular(SeeURadii.pill),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsBold.plus, size: 16, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Создать сбор',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
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

  bool get _hasActiveFilter =>
      _catFilter != null || _typeFilter != null || _showMine || _showBookmarked ||
      _searchQuery.isNotEmpty || _dateFilter != null;

  void _resetFilters() {
    setState(() {
      _catFilter      = null;
      _typeFilter     = null;
      _showMine       = false;
      _showBookmarked = false;
      _dateFilter     = null;
      _datePreset     = null;
      _searchQuery    = '';
      _searchController.clear();
    });
  }

  static const _shortMonthsRu = [
    'янв', 'фев', 'мар', 'апр', 'май', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];

  String _fmtDateRange(DateTimeRange r) {
    final s  = r.start;
    final e  = r.end;
    final sm = _shortMonthsRu[s.month - 1];
    if (s.day == e.day && s.month == e.month && s.year == e.year) {
      return '${s.day} $sm';
    }
    if (s.month == e.month && s.year == e.year) {
      return '${s.day}–${e.day} $sm';
    }
    return '${s.day} $sm – ${e.day} ${_shortMonthsRu[e.month - 1]}';
  }

  Widget _buildEmpty(SeeUThemeColors c) {
    final hasFilter = _hasActiveFilter;
    return RefreshIndicator(
      onRefresh: _refresh,
      color: SeeUColors.accent,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: 400,
          child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasFilter ? PhosphorIcons.funnel() : PhosphorIcons.confetti(),
            size: 48, color: c.ink4,
          ),
          const SizedBox(height: 12),
          Text(
            hasFilter ? 'Ничего не найдено' : 'Здесь пока пусто',
            style: SeeUTypography.subtitle.copyWith(color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(
            hasFilter
                ? 'Попробуй другие фильтры'
                : 'В этой категории нет сборов. Создайте свой и позовите людей.',
            style: TextStyle(fontSize: 13, color: c.ink3),
            textAlign: TextAlign.center,
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
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF5A3C), Color(0xFFFF3B6B)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
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
          ),
        ),
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
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: Border.all(color: active ? color.ink : color.line, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: active ? color.bg : color.ink2),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? color.bg : color.ink2,
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
              color: color == SeeUColors.accent
                  ? SeeUColors.accent.withValues(alpha: 0.30)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: color == SeeUColors.accent ? 12 : 2,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, size: 17, color: iconColor),
      ),
    );
  }
}

// ─── SborCard ────────────────────────────────────────────────────

class SborCard extends ConsumerStatefulWidget {
  final Sbor sbor;
  final VoidCallback? onTap;
  final bool compact;

  const SborCard({super.key, required this.sbor, this.onTap, this.compact = false});

  @override
  ConsumerState<SborCard> createState() => _SborCardState();
}

class _SborCardState extends ConsumerState<SborCard> {
  late bool _bookmarked;
  bool _bookmarkLoading = false;

  @override
  void initState() {
    super.initState();
    _bookmarked = widget.sbor.isBookmarked;
  }

  @override
  void didUpdateWidget(SborCard old) {
    super.didUpdateWidget(old);
    if (old.sbor.isBookmarked != widget.sbor.isBookmarked) {
      _bookmarked = widget.sbor.isBookmarked;
    }
  }

  String? _resolvedCoverUrl(Sbor s) {
    final url = s.coverUrl;
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    return '${AppConfig.apiOrigin}$url';
  }

  Future<void> _toggleBookmark() async {
    if (_bookmarkLoading) return;
    HapticFeedback.selectionClick();
    setState(() { _bookmarkLoading = true; });
    try {
      final api = ref.read(apiClientProvider);
      await api.post(ApiEndpoints.bookmarkSbor(widget.sbor.id));
      if (mounted) {
        setState(() { _bookmarked = !_bookmarked; });
        ref.invalidate(_bookmarkedSboryProvider);
      }
    } catch (_) {
      // тихо игнорируем — state не меняется
    } finally {
      if (mounted) setState(() { _bookmarkLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final s = widget.sbor;
    final meta = s.categoryMeta;
    final coverUrl = _resolvedCoverUrl(s);
    // Cover status pill
    Widget? statusPill;
    if (s.myRole == SborRole.organizer) {
      statusPill = _StatusPill(
        bg: SeeUColors.accent.withValues(alpha: 0.95),
        fg: Colors.white,
        icon: PhosphorIcons.crownSimple(PhosphorIconsStyle.fill),
        label: 'Вы организатор',
      );
    } else if (s.isJoined) {
      statusPill = _StatusPill(
        bg: const Color(0xEF2FA84F),
        fg: Colors.white,
        icon: PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
        label: 'Вы идёте',
      );
    } else if (s.myRequestStatus == 'pending') {
      statusPill = _StatusPill(
        bg: const Color(0xF5FFB547),
        fg: const Color(0xFF3A2A05),
        icon: PhosphorIcons.hourglassMedium(),
        label: 'Заявка отправлена',
      );
    } else if (s.isFull) {
      statusPill = _StatusPill(
        bg: Colors.black.withValues(alpha: 0.60),
        fg: Colors.white,
        icon: PhosphorIcons.lockSimple(),
        label: 'Мест нет',
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.line, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF161310).withValues(alpha: 0.06),
              blurRadius: 16, offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: const Color(0xFF161310).withValues(alpha: 0.04),
              blurRadius: 2, offset: const Offset(0, 1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cover ─────────────────────────────────────────────
            SizedBox(
              height: 150,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (coverUrl != null)
                    CachedNetworkImage(
                      imageUrl: coverUrl, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(color: meta.soft),
                    )
                  else
                    Container(color: meta.soft),
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
                  if (coverUrl == null)
                    Positioned(
                      right: -14, bottom: -34,
                      child: Opacity(
                        opacity: 0.16,
                        child: Icon(meta.icon, size: 150, color: meta.color),
                      ),
                    ),
                  // Category pill — top-left
                  Positioned(
                    top: 12, left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(meta.icon, size: 11, color: Colors.white),
                          const SizedBox(width: 5),
                          Text(meta.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                          if (s.live) ...[
                            const SizedBox(width: 6),
                            const Text('● LIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.redAccent)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Bookmark — top-right (tappable, stops propagation to card)
                  Positioned(
                    top: 12, right: 12,
                    child: GestureDetector(
                      onTap: _toggleBookmark,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: _bookmarkLoading
                            ? const Padding(
                                padding: EdgeInsets.all(9),
                                child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                              )
                            : Icon(
                                _bookmarked
                                    ? PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.fill)
                                    : PhosphorIcons.bookmarkSimple(),
                                size: 17,
                                color: _bookmarked ? SeeUColors.amber : Colors.white,
                              ),
                      ),
                    ),
                  ),
                  // Location pill — bottom-left
                  Positioned(
                    bottom: 12, left: 12,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 140),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            s.type == SborType.online ? PhosphorIcons.globe() : PhosphorIcons.mapPin(),
                            size: 11, color: Colors.white,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              s.type == SborType.online ? 'Онлайн' : (s.place.isNotEmpty ? s.place : 'Оффлайн'),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Status pill — bottom-right
                  if (statusPill != null)
                    Positioned(bottom: 12, right: 12, child: statusPill),
                ],
              ),
            ),
            // ── Body ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          s.title,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        s.price == 0 ? 'Бесплатно' : '${s.price} ₸',
                        style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700,
                          color: s.price == 0 ? SeeUColors.success : c.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(PhosphorIcons.calendarBlank(), size: 13, color: c.ink3),
                      const SizedBox(width: 5),
                      Text(s.when, style: TextStyle(fontSize: 13, color: c.ink3)),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Container(height: 1, color: c.line),
                  ),
                  Row(
                    children: [
                      SboryAvatarStack(names: s.memberNames, avatarUrls: s.memberAvatarUrls, size: 26),
                      const SizedBox(width: 8),
                      Text(
                        s.max != null ? '${s.joined}/${s.max} идёт' : '${s.joined} идёт',
                        style: TextStyle(fontSize: 12, color: c.ink3),
                      ),
                      const Spacer(),
                      _CardAction(sbor: s, c: c),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 0.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  blurRadius: 0,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'ПРЯМО СЕЙЧАС',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: Colors.white,
                            ),
                          ),
                        ],
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

// ─── Status pill (cover overlay) ─────────────────────────────────

class _StatusPill extends StatelessWidget {
  final Color bg;
  final Color fg;
  final IconData icon;
  final String label;
  const _StatusPill({required this.bg, required this.fg, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}

// ─── Card footer action ───────────────────────────────────────────

class _CardAction extends StatelessWidget {
  final Sbor sbor;
  final SeeUThemeColors c;
  const _CardAction({required this.sbor, required this.c});

  @override
  Widget build(BuildContext context) {
    final s = sbor;
    if (s.myRole == SborRole.organizer) {
      if (s.pendingRequestsCount > 0) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: SeeUColors.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${s.pendingRequestsCount}',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 4),
            const Text('заявок', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SeeUColors.accent)),
          ],
        );
      }
      return const SizedBox.shrink();
    }
    if (s.isJoined || s.myRequestStatus == 'pending' || s.isFull) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Подать заявку', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SeeUColors.accent)),
        const SizedBox(width: 3),
        Icon(PhosphorIcons.arrowRight(), size: 13, color: SeeUColors.accent),
      ],
    );
  }
}

