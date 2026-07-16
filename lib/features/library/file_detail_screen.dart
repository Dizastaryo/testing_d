import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/models/user.dart' show UserShort;
import '../../core/providers/library_provider.dart';
import '../../core/providers/offline_catalog_provider.dart';
import '../../core/providers/reading_provider.dart';
import '../../core/utils/format.dart'
    show colorForFileType, friendlyError, readableInk;
import '_file_download_web.dart'
    if (dart.library.io) '_file_download_io.dart' as downloader;
import 'author_screen.dart';
import 'bookmarks_screen.dart';
import 'collection_add_sheet.dart';
import 'library_design.dart';
import 'readers/open_reader.dart';
import 'widgets/file_cover_widget.dart';

/// Стеклянная кнопка поверх обложки в шапке карточки книги.
class _HeroGlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeroGlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tappable.scaled(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: 44,
            height: 44,
            color: dark
                ? const Color(0xFF141210).withValues(alpha: 0.62)
                : Colors.white.withValues(alpha: 0.78),
            child: Icon(icon, size: 20, color: c.ink),
          ),
        ),
      ),
    );
  }
}

String _formatCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

final _fileDetailProvider =
    FutureProvider.autoDispose.family<FileItem, String>((ref, id) async {
  final dio = ref.watch(libraryApiClientProvider);
  final r = await dio.get(ApiEndpoints.fileById(id));
  final raw = r.data;
  final data = raw is Map && raw.containsKey('data') ? raw['data'] : raw;
  return FileItem.fromJson(Map<String, dynamic>.from(data as Map));
});

// Community reviews provider
final _fileReviewsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, fileId) async {
  final dio = ref.watch(libraryApiClientProvider);
  try {
    final r = await dio.get(ApiEndpoints.fileReviews(fileId));
    final data = r.data?['data'] as List? ?? [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (_) {
    return [];
  }
});

// Text preview provider (first 500 chars of extracted text)
final _textPreviewProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, id) async {
  final dio = ref.watch(libraryApiClientProvider);
  try {
    final r = await dio.get(ApiEndpoints.fileText(id));
    final text = r.data is String ? r.data as String : r.data?['data'] as String?;
    if (text == null || text.trim().isEmpty) return null;
    final trimmed = text.trim();
    return trimmed.length > 500 ? trimmed.substring(0, 500) : trimmed;
  } catch (_) {
    return null;
  }
});

class FileDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const FileDetailScreen({super.key, required this.id});

  @override
  ConsumerState<FileDetailScreen> createState() => _FileDetailScreenState();
}

class _FileDetailScreenState extends ConsumerState<FileDetailScreen> {
  bool _downloading = false;
  double _downloadProgress = 0.0;
  bool _viewTracked = false;

  void _trackView() {
    if (_viewTracked) return;
    _viewTracked = true;
    // Fire-and-forget: don't await, don't show errors
    ref.read(libraryActionsProvider).trackView(widget.id).catchError((_) {});
  }

  Future<void> _setReadingStatus(String? status) async {
    HapticFeedback.selectionClick();
    final wasReading = ref.read(readingStatusProvider(widget.id));
    await ref.read(readingStatusProvider(widget.id).notifier).updateStatus(status);
    // Guard ref use after the await — виджет мог отмонтироваться за время запроса.
    if (!mounted) return;
    // Invalidate reading list and stats so they reflect the change
    ref.invalidate(readingStatsProvider);
    for (final s in ['reading', 'want', 'done']) {
      ref.invalidate(readingListProvider(s));
    }
    // Celebrate when marking as done
    if (status == 'done' && wasReading != 'done') {
      _showBookDoneCelebration();
    }
  }

  void _showBookDoneCelebration() {
    HapticFeedback.heavyImpact();
    // Get done count from stats for the message
    final stats = ref.read(readingStatsProvider).valueOrNull;
    final doneCount = ((stats?['books_done'] as num?)?.toInt() ?? 0) + 1;
    final msg = doneCount == 1
        ? 'Первая прочитанная книга!'
        : 'Книга #$doneCount прочитана!';

    showSeeUSnackBar(
      context,
      msg,
      icon: PhosphorIcons.confetti(),
      tone: SeeUTone.success,
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _toggleLike(FileItem file) async {
    HapticFeedback.lightImpact();
    try {
      await ref.read(libraryActionsProvider).setLike(file.id, liked: file.isLiked);
      ref.invalidate(_fileDetailProvider(file.id));
    } on DioException catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Не удалось: ${e.message ?? e.type}',
          tone: SeeUTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final async = ref.watch(_fileDetailProvider(widget.id));
    // Watch reading status so the UI rebuilds when it changes
    final readingStatus = ref.watch(readingStatusProvider(widget.id));

    // Track the view as a side-effect of the data arriving — never inside the
    // widget-building branch below (which can run on every rebuild).
    ref.listen(_fileDetailProvider(widget.id), (prev, next) {
      next.whenOrNull(data: (_) => _trackView());
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _buildErrorState(e, c),
        data: (file) => _buildBody(file, c, readingStatus),
      ),
    );
  }

  Widget _buildErrorState(Object e, SeeUThemeColors c) {
    return Stack(
      children: [
        SeeUErrorState(
          icon: PhosphorIconsRegular.warning,
          error: friendlyError(e),
          onRetry: () => ref.invalidate(_fileDetailProvider(widget.id)),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SeeUGlassBar(
            kicker: 'Библиотека',
            titleText: 'Файл',
            leading: Tappable(
              onTap: () => context.pop(),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(PhosphorIconsRegular.arrowLeft,
                    size: 20, color: c.ink),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(FileItem file, SeeUThemeColors c, [String? readingStatus]) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHero(file, c)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Название — серифом, как на корешке.
                Text(
                  file.displayTitle,
                  style: SeeUTypography.displayS.copyWith(
                    fontSize: 27,
                    height: 1.12,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                if (file.authorName.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          AuthorScreen(authorName: file.authorName),
                    )),
                    child: Text(
                      file.authorName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: LibColors.kicker(context),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 14),
                _buildChips(file, c),

                const SizedBox(height: 18),
                _buildActions(file, c),

                if (canRead(file)) ...[
                  const SizedBox(height: 12),
                  _buildStatusSegments(readingStatus, c),
                ],


                const SizedBox(height: 18),
                _RatingWidget(file: file),

                // Отзывы сообщества
                _ReviewsSection(fileId: file.id),

                // Личные заметки (приватные)
                _FileNotesSection(fileId: file.id),

                if (file.description.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _ExpandableDescription(text: file.description, c: c),
                ],

                _TextPreviewSection(fileId: file.id),

                const SizedBox(height: 20),
                _StatsBar(file: file),

                const SizedBox(height: 20),
                if (file.user != null) ...[
                  _AuthorSection(user: file.user!, c: c),
                  const SizedBox(height: 20),
                ],

                if (readingStatus == 'reading' && canRead(file))
                  _buildProgressCard(file.id, c),

                if (canRead(file)) _buildBookmarksSection(file, c),

                const SizedBox(height: 24),
                _RelatedFilesRow(fileId: file.id, authorName: file.authorName),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Hero карточки: фон — цвет обложки, растворяющийся в бумагу, поверх —
  /// стеклянные «Назад» и «Поделиться», снизу слева — сама обложка-корешок.
  Widget _buildHero(FileItem file, SeeUThemeColors c) {
    final top = MediaQuery.of(context).padding.top;
    final grad = coverGradientOf(file);

    return SizedBox(
      height: 290,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [grad.last, grad.first],
                ),
              ),
            ),
          ),
          // Растворение в фон страницы — обложка «перетекает» в бумагу.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [c.bg, c.bg.withValues(alpha: 0)],
                  stops: const [0.02, 0.48],
                ),
              ),
            ),
          ),
          Positioned(
            top: top + 6,
            left: 18,
            child: _HeroGlassButton(
              icon: PhosphorIcons.arrowLeft(),
              onTap: () => context.pop(),
            ),
          ),
          Positioned(
            top: top + 6,
            right: 18,
            child: _HeroGlassButton(
              icon: PhosphorIconsRegular.shareFat,
              onTap: () {
                final info = file.authorName.isNotEmpty
                    ? '${file.displayTitle} — ${file.authorName}'
                    : file.displayTitle;
                Share.share(
                  '$info\n\nОткрыть в SeeU: seeu://files/${file.id}',
                  subject: file.displayTitle,
                );
              },
            ),
          ),
          Positioned(
            left: 24,
            bottom: 6,
            child: BookSpine(file: file, width: 120, height: 170, radius: 12),
          ),
        ],
      ),
    );
  }

  /// Чипы книги: формат, объём, время чтения, язык, офлайн, категория.
  Widget _buildChips(FileItem file, SeeUThemeColors c) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        _InfoChip(
            label: file.formatLabel,
            color: colorForFileType(file.fileExtension),
            bordered: true),
        if (ref.watch(isOfflineProvider(file.id)))
          const _InfoChip(label: 'Офлайн', color: SeeUColors.success),
        if (file.pagesCount > 0) _InfoChip(label: '${file.pagesCount} стр.'),
        if (file.pagesCount >= 5)
          _InfoChip(
            label: totalReadingTime(file.pagesCount),
            color: SeeUColors.plum,
          ),
        _InfoChip(label: file.fileSizeFormatted),
        if (file.category case final cat? when cat.name.isNotEmpty)
          _CategoryChip(category: cat),
        if (file.language.isNotEmpty)
          _InfoChip(label: file.language.toUpperCase()),
      ],
    );
  }

  /// Статус чтения — сегментированный переключатель «Хочу · Читаю · Прочитано».
  Widget _buildStatusSegments(String? status, SeeUThemeColors c) {
    const items = [
      ('want', 'Хочу'),
      ('reading', 'Читаю'),
      ('done', 'Прочитано'),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: LibColors.chip(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final (key, label) in items)
            Expanded(
              child: Tappable(
                onTap: () => _setReadingStatus(status == key ? null : key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: status == key ? SeeUColors.accent : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          status == key ? FontWeight.w700 : FontWeight.w600,
                      color: status == key ? Colors.white : c.ink3,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActions(FileItem file, SeeUThemeColors c) {
    final readingStatus = ref.watch(readingStatusProvider(widget.id));
    final hasProgress = readingStatus == 'reading';
    final pct = ref.watch(readingProgressProvider(file.id)).valueOrNull
            ?.percentage ??
        0;

    // Главная кнопка несёт процент — сколько уже прочитано.
    final ctaLabel = !canRead(file)
        ? (_downloading && _downloadProgress > 0
            ? 'Скачивание ${(_downloadProgress * 100).toInt()}%'
            : _downloading
                ? 'Скачивание…'
                : 'Скачать')
        : hasProgress && pct > 0
            ? 'Продолжить · ${(pct * 100).round()}%'
            : hasProgress
                ? 'Продолжить'
                : 'Читать';

    return Row(
      children: [
        Expanded(
          child: Tappable.scaled(
            onTap: _downloading && !canRead(file)
                ? null
                : () => canRead(file)
                    ? openReader(context, file)
                    : _download(file),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: SeeUColors.accent,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: SeeUColors.accent.withValues(alpha: 0.6),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                    spreadRadius: -8,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    !canRead(file)
                        ? PhosphorIconsFill.downloadSimple
                        : hasProgress
                            ? PhosphorIconsFill.play
                            : PhosphorIconsFill.bookOpen,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      ctaLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _LikeButton(file: file, onTap: () => _toggleLike(file)),
        const SizedBox(width: 10),
        // «В коллекцию» — коллекция это плейлист в мире книг, и добавить книгу
        // в подборку можно только отсюда. Такое же первоклассное действие,
        // как «нравится» и «скачать».
        _ActionButton(
          icon: PhosphorIconsRegular.plus,
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => CollectionAddSheet(fileId: file.id),
          ),
          c: c,
        ),
        if (canRead(file)) ...[
          const SizedBox(width: 10),
          _ActionButton(
            icon: _downloading ? null : PhosphorIconsRegular.downloadSimple,
            isLoading: _downloading,
            progressText: _downloadProgress > 0
                ? '${(_downloadProgress * 100).toInt()}%'
                : null,
            onTap: _downloading ? null : () => _download(file),
            c: c,
          ),
        ],
      ],
    );
  }

  Widget _buildProgressCard(String fileId, SeeUThemeColors c) {
    final progressAsync = ref.watch(readingProgressProvider(fileId));
    return progressAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (progress) {
        if (progress == null || progress.percentage == 0) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SeeUColors.accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: SeeUColors.accent.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: SeeUColors.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Читаешь',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(progress.percentage * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: SeeUColors.accent,
                        fontFamily: AppFonts.I.sans,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.percentage,
                    minHeight: 6,
                    backgroundColor:
                        SeeUColors.accent.withValues(alpha: 0.15),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        SeeUColors.accent),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  progress.displayProgress,
                  style: TextStyle(fontSize: 12, color: c.ink3),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBookmarksSection(FileItem file, SeeUThemeColors c) {
    final bookmarksAsync = ref.watch(bookmarksProvider(file.id));
    return bookmarksAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (bookmarks) {
        if (bookmarks.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(PhosphorIconsFill.bookmarkSimple,
                      size: 16, color: SeeUColors.accent),
                  const SizedBox(width: 8),
                  Text('Закладки',
                      style: TextStyle(
                        fontSize: 13,
                        color: c.ink3,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: SeeUColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${bookmarks.length}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: SeeUColors.accent,
                        fontFamily: AppFonts.I.sans,
                      ),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => BookmarksScreen(
                        fileId: file.id,
                        fileTitle: file.displayTitle,
                        file: file,
                      ),
                    )),
                    child: Text(
                      'Все',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: SeeUColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(SeeURadii.small),
                ),
                child: Column(
                  children: [
                    for (int i = 0;
                        i < bookmarks.length && i < 3;
                        i++) ...[
                      if (i > 0)
                        Divider(height: 16, color: c.line),
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: SeeUColors.accent
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Center(
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: SeeUColors.accent,
                                  fontFamily: AppFonts.I.sans,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _bookmarkLabel(bookmarks[i].position),
                              style: TextStyle(
                                  fontSize: 13, color: c.ink2),
                            ),
                          ),
                          Icon(PhosphorIconsRegular.bookmarkSimple,
                              size: 14, color: c.ink4),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _bookmarkLabel(Map<String, dynamic> pos) {
    if (pos.containsKey('page') && pos.containsKey('total')) {
      return 'Стр. ${pos['page']} / ${pos['total']}';
    }
    if (pos.containsKey('offset') && pos.containsKey('total')) {
      final total = (pos['total'] as num).toDouble();
      if (total <= 0) return 'Закладка';
      final pct = ((pos['offset'] as num).toDouble() / total * 100).toInt();
      return '$pct% прочитано';
    }
    return 'Закладка';
  }

  Future<void> _download(FileItem file) async {
    setState(() {
      _downloading = true;
      _downloadProgress = 0.0;
    });
    try {
      final data = await ref.read(libraryActionsProvider).downloadInfo(file.id);
      final url = (data['file_url'] as String?) ?? file.fileUrl;
      final absUrl = url.startsWith('/')
          ? ApiEndpoints.libraryBaseUrl.replaceAll('/api/v1', '') + url
          : url;

      final saved = await downloader.saveDownload(
        url: absUrl,
        filename: file.filename,
        onProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );

      if (!mounted) return;
      ref.invalidate(_fileDetailProvider(widget.id));
      // «Сохранён» только если файл реально лёг на устройство; иначе открылся
      // в браузере (скачивание не удалось) — честно об этом и говорим.
      showSeeUSnackBar(
        context,
        saved ? 'Файл сохранён' : 'Открыто в браузере',
        tone: saved ? SeeUTone.success : SeeUTone.neutral,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Не удалось скачать: ${e.message ?? e.type}',
          tone: SeeUTone.danger);
    } catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Ошибка: $e', tone: SeeUTone.danger);
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadProgress = 0.0;
        });
      }
    }
  }
}

// ─── Cover Header ───────────────────────────────────────────────────────────

// ─── Stats Bar ──────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final FileItem file;
  const _StatsBar({required this.file});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatColumn(
            icon: PhosphorIconsFill.heart,
            iconColor: SeeUColors.like,
            value: '${file.likesCount}',
            label: 'Лайков',
          ),
          Container(width: 1, height: 28, color: c.line),
          _StatColumn(
            icon: PhosphorIconsFill.eye,
            iconColor: c.ink3,
            value: _formatCount(file.viewsCount),
            label: 'Просмотров',
          ),
          Container(width: 1, height: 28, color: c.line),
          _StatColumn(
            icon: PhosphorIconsFill.download,
            iconColor: SeeUColors.accent,
            value: file.downloadsFormatted,
            label: 'Скачиваний',
          ),
          if (file.pagesCount > 0) ...[
            Container(width: 1, height: 28, color: c.line),
            _StatColumn(
              icon: PhosphorIconsFill.fileText,
              iconColor: c.ink3,
              value: '${file.pagesCount}',
              label: 'Страниц',
            ),
          ],
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  const _StatColumn(
      {required this.icon,
      required this.iconColor,
      required this.value,
      required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontFamily: AppFonts.I.sans,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: c.ink3)),
      ],
    );
  }
}

// ─── Star Rating Widget ──────────────────────────────────────────────────────

class _RatingWidget extends ConsumerStatefulWidget {
  final FileItem file;
  const _RatingWidget({required this.file});

  @override
  ConsumerState<_RatingWidget> createState() => _RatingWidgetState();
}

class _RatingWidgetState extends ConsumerState<_RatingWidget> {
  int _hovered = 0;
  bool _showReviewField = false;
  late final TextEditingController _reviewCtrl;

  @override
  void initState() {
    super.initState();
    _reviewCtrl = TextEditingController();
    // Load existing review text
    _loadReview();
  }

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReview() async {
    final text =
        await ref.read(libraryActionsProvider).loadRatingReview(widget.file.id);
    if (text.isNotEmpty && mounted) {
      _reviewCtrl.text = text;
    }
  }

  Future<void> _setRating(int rating) async {
    HapticFeedback.selectionClick();
    try {
      await ref
          .read(libraryActionsProvider)
          .setRating(widget.file.id, rating, _reviewCtrl.text.trim());
      if (!mounted) return;
      ref.invalidate(_fileDetailProvider(widget.file.id));
      ref.invalidate(_fileReviewsProvider(widget.file.id));
      setState(() => _showReviewField = true);
    } catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Не удалось сохранить оценку: $e',
          tone: SeeUTone.danger);
    }
  }

  Future<void> _submitReview() async {
    final text = _reviewCtrl.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    final rating = widget.file.userRating > 0 ? widget.file.userRating : 3;
    try {
      await ref
          .read(libraryActionsProvider)
          .setRating(widget.file.id, rating, text);
      if (!mounted) return;
      ref.invalidate(_fileDetailProvider(widget.file.id));
      ref.invalidate(_fileReviewsProvider(widget.file.id));
      setState(() => _showReviewField = false);
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Не удалось сохранить отзыв: $e',
          tone: SeeUTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final file = widget.file;
    final avg = file.averageRating;
    final userRating = file.userRating;
    final display = _hovered > 0 ? _hovered : userRating;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Editorial-блок оценки: слева крупная средняя со звёздами-мини,
        // справа — моя оценка пятью крупными звёздами.
        Container(
          padding: const EdgeInsets.only(top: 16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: LibColors.line(context))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (file.ratingsCount > 0) ...[
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      avg.toStringAsFixed(1),
                      style: SeeUTypography.displayS.copyWith(
                        fontSize: 34,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, (i) {
                        final full = avg >= i + 1;
                        final half = !full && avg > i + 0.25;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: Icon(
                            full
                                ? PhosphorIconsFill.star
                                : half
                                    ? PhosphorIconsRegular.starHalf
                                    : PhosphorIconsRegular.star,
                            size: 11,
                            color: full || half ? SeeUColors.amber : c.ink4,
                          ),
                        );
                      }),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      file.ratingsCount > 0
                          ? 'Ваша оценка · ${file.ratingsCount} ${_pluralRatings(file.ratingsCount)}'
                          : 'Оцените книгу первым',
                      style: TextStyle(fontSize: 12, color: c.ink3),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, (i) {
                        final starValue = i + 1;
                        final filled = starValue <= display;
                        return GestureDetector(
                          onTap: () => _setRating(starValue),
                          child: MouseRegion(
                            onEnter: (_) =>
                                setState(() => _hovered = starValue),
                            onExit: (_) => setState(() => _hovered = 0),
                            child: Padding(
                              padding:
                                  const EdgeInsets.only(right: 5),
                              child: Icon(
                                filled
                                    ? PhosphorIconsFill.star
                                    : PhosphorIconsRegular.star,
                                size: 24,
                                color: filled ? SeeUColors.amber : c.ink4,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Spacer(),
            // Toggle review field
            if (userRating > 0)
              GestureDetector(
                onTap: () =>
                    setState(() => _showReviewField = !_showReviewField),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _showReviewField ? 'Скрыть' : 'Рецензия',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c.ink3),
                  ),
                ),
              ),
          ],
        ),
        // Review text field (shown after tapping a star or "Рецензия")
        if (_showReviewField && userRating > 0) ...[
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(SeeURadii.small),
              border: Border.all(color: c.line.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _reviewCtrl,
                  maxLines: 3,
                  minLines: 2,
                  maxLength: 500,
                  style: TextStyle(fontSize: 13, color: c.ink),
                  decoration: InputDecoration(
                    hintText: 'Напиши свою рецензию...',
                    hintStyle: TextStyle(fontSize: 13, color: c.ink4),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(12),
                    counterStyle:
                        TextStyle(fontSize: 10, color: c.ink4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: _submitReview,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: SeeUColors.accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Сохранить',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _pluralRatings(int n) {
    final m = n % 10;
    final h = n % 100;
    if (h >= 11 && h <= 19) return 'оценок';
    if (m == 1) return 'оценка';
    if (m >= 2 && m <= 4) return 'оценки';
    return 'оценок';
  }
}

// ─── Community Reviews Section ───────────────────────────────────────────────

class _ReviewsSection extends ConsumerWidget {
  final String fileId;
  const _ReviewsSection({required this.fileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(_fileReviewsProvider(fileId));
    final reviews = async.valueOrNull ?? [];
    if (reviews.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text(
          'Рецензии',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 8),
        ...reviews.take(3).map((r) => _ReviewTile(review: r)),
        if (reviews.length > 3) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _AllReviewsSheet(
                    fileId: fileId, reviews: reviews),
              );
            },
            child: Text(
              'Ещё ${reviews.length - 3} рецензий →',
              style: TextStyle(
                fontSize: 12,
                color: SeeUColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final username = review['username'] as String? ?? '';
    final fullName = review['full_name'] as String? ?? '';
    final avatarUrl = review['avatar_url'] as String? ?? '';
    final rating = review['rating'] as int? ?? 0;
    final text = review['review_text'] as String? ?? '';
    final displayName = fullName.isNotEmpty ? fullName : username;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(SeeURadii.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: c.line,
                backgroundImage:
                    avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl.isEmpty
                    ? Text(
                        username.isNotEmpty ? username[0].toUpperCase() : '?',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  displayName,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  return Icon(
                    i < rating
                        ? PhosphorIconsFill.star
                        : PhosphorIconsRegular.star,
                    size: 12,
                    color: i < rating
                        ? SeeUColors.amber
                        : c.ink4,
                  );
                }),
              ),
            ],
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 6),
            // Цитата отзыва — серифный италик в «кавычках-ёлочках».
            Text(
              '«$text»',
              style: TextStyle(
                fontFamily: AppFonts.I.serif,
                fontStyle: FontStyle.italic,
                fontSize: 14,
                color: c.ink2,
                height: 1.45,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _AllReviewsSheet extends StatelessWidget {
  final String fileId;
  final List<Map<String, dynamic>> reviews;
  const _AllReviewsSheet({required this.fileId, required this.reviews});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: c.ink4,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                Text(
                  'Рецензии',
                  style: SeeUTypography.displayXS.copyWith(
                    color: c.ink,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${reviews.length}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: c.ink3,
                        fontFamily: AppFonts.I.sans),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              itemCount: reviews.length,
              itemBuilder: (_, i) => _ReviewTile(review: reviews[i]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Author Section ─────────────────────────────────────────────────────────

class _AuthorSection extends StatelessWidget {
  final UserShort user;
  final SeeUThemeColors c;
  const _AuthorSection({required this.user, required this.c});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/profile/${user.username}'),
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: c.ink4,
            backgroundImage: user.avatarUrl.isNotEmpty
                ? NetworkImage(user.avatarUrl)
                : null,
            child: user.avatarUrl.isEmpty
                ? Icon(PhosphorIconsRegular.user,
                    size: 18, color: c.surface)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('@${user.username}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    if (user.isVerified) ...[
                      const SizedBox(width: 4),
                      Icon(PhosphorIconsFill.sealCheck,
                          size: 14, color: SeeUColors.accent),
                    ],
                  ],
                ),
                if (user.fullName.isNotEmpty)
                  Text(user.fullName,
                      style: TextStyle(fontSize: 12, color: c.ink3)),
              ],
            ),
          ),
          Text(
            'Загрузил',
            style: TextStyle(fontSize: 11, color: c.ink4),
          ),
        ],
      ),
      ),
    );
  }
}

// ─── Like Button ────────────────────────────────────────────────────────────

class _LikeButton extends StatelessWidget {
  final FileItem file;
  final VoidCallback onTap;
  const _LikeButton({required this.file, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        width: 52,
        decoration: BoxDecoration(
          color: file.isLiked
              ? SeeUColors.like.withValues(alpha: 0.12)
              : c.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: file.isLiked
                ? SeeUColors.like.withValues(alpha: 0.4)
                : c.line,
          ),
        ),
        child: Icon(
          file.isLiked
              ? PhosphorIcons.heart(PhosphorIconsStyle.fill)
              : PhosphorIcons.heart(),
          color: file.isLiked ? SeeUColors.like : c.ink2,
          size: 22,
        ),
      ),
    );
  }
}

// ─── Action Button ──────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData? icon;
  final VoidCallback? onTap;
  final SeeUThemeColors c;
  final bool isLoading;
  final String? progressText;

  const _ActionButton({
    this.icon,
    required this.onTap,
    required this.c,
    this.isLoading = false,
    this.progressText,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        width: 52,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: isLoading
            ? progressText != null
                ? Center(
                    child: Text(
                      progressText!,
                      style: TextStyle(
                        fontFamily: AppFonts.I.sans,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: SeeUColors.accent,
                      ),
                    ),
                  )
                : const Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)))
            : Icon(icon, color: c.ink2, size: 20),
      ),
    );
  }
}

// ─── Status Chip ────────────────────────────────────────────────────────────

// ─── Info Chip ──────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final String label;
  final Color? color;

  /// Обводка 1px цветом чипа — формат-чип («PDF» с бордером цвета формата).
  final bool bordered;

  const _InfoChip({required this.label, this.color, this.bordered = false});

  @override
  Widget build(BuildContext context) {
    final c = color ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        border: bordered ? Border.all(color: c) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppFonts.I.sans,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: c,
        ),
      ),
    );
  }
}

// ─── Category Chip (tappable, opens the category shelf) ─────────────────────

class _CategoryChip extends StatelessWidget {
  final FileCategory category;
  const _CategoryChip({required this.category});

  @override
  Widget build(BuildContext context) {
    final accent = category.colorValue;
    // Darken pale category colors so the small label keeps enough contrast.
    final ink = readableInk(accent, isDark: context.seeuColors.isDark);
    return GestureDetector(
      onTap: () => context.push('/library/category/${category.slug}',
          extra: category),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.iconData, size: 13, color: ink),
            const SizedBox(width: 5),
            Text(
              category.name,
              style: TextStyle(
                fontFamily: AppFonts.I.sans,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Author's Other Files ────────────────────────────────────────────────────

// ─── Related Files Row ────────────────────────────────────────────────────────

class _RelatedFilesRow extends ConsumerWidget {
  final String fileId;
  final String authorName;
  const _RelatedFilesRow({required this.fileId, required this.authorName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(fileRelatedProvider(fileId));
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (files) {
        if (files.isEmpty) return const SizedBox.shrink();
        final sameAuthor = authorName.isNotEmpty &&
            files.any((f) =>
                f.authorName.toLowerCase() == authorName.toLowerCase());
        final title = sameAuthor ? 'Ещё от автора' : 'Похожие файлы';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: SeeUTypography.displayXS.copyWith(
                        fontWeight: FontWeight.w500,
                        color: c.ink,
                      )),
                ),
                if (sameAuthor && files.length >= 4)
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AuthorScreen(authorName: authorName),
                    )),
                    child: Text('Все',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: SeeUColors.accent,
                        )),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: files.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) {
                  final f = files[i];
                  return GestureDetector(
                    onTap: () => ctx.push('/files/${f.id}'),
                    child: SizedBox(
                      width: 100,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: FileCoverWidget(
                              file: f,
                              width: 100,
                              height: 130,
                              borderRadius: 10,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            f.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: c.ink2,
                                height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}


// ─── File Notes ──────────────────────────────────────────────────────────────

class _FileNotesSection extends ConsumerStatefulWidget {
  final String fileId;
  const _FileNotesSection({required this.fileId});

  @override
  ConsumerState<_FileNotesSection> createState() => _FileNotesSectionState();
}

class _FileNotesSectionState extends ConsumerState<_FileNotesSection> {
  bool _editing = false;
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    // Sync the controller with the loaded note via a listener side-effect
    // instead of mutating it inline during build.
    ref.listen(fileNoteProvider(widget.fileId), (prev, next) {
      if (!_editing && _ctrl.text != next) _ctrl.text = next;
    });
    final note = ref.watch(fileNoteProvider(widget.fileId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(PhosphorIconsRegular.notePencil, size: 14, color: c.ink4),
            const SizedBox(width: 6),
            Text(
              'Мои заметки',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.ink3,
              ),
            ),
            const Spacer(),
            if (!_editing)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _editing = true;
                    _ctrl.text = note;
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    note.isEmpty ? 'Добавить' : 'Изменить',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.ink3,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_editing) ...[
          TextField(
            controller: _ctrl,
            maxLines: 5,
            minLines: 3,
            maxLength: 5000,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Личные заметки к файлу (только для вас)…',
              hintStyle: TextStyle(color: c.ink4, fontSize: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SeeURadii.small),
                borderSide: BorderSide(color: c.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SeeURadii.small),
                borderSide:
                    const BorderSide(color: SeeUColors.accent, width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              counterStyle: TextStyle(fontSize: 10, color: c.ink4),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (note.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    ref.read(fileNoteProvider(widget.fileId).notifier).delete();
                    setState(() => _editing = false);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    child: Text('Удалить',
                        style: TextStyle(
                            fontSize: 13,
                            color: SeeUColors.error.withValues(alpha: 0.8))),
                  ),
                ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => setState(() {
                  _editing = false;
                  _ctrl.text = note;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  child: Text('Отмена',
                      style: TextStyle(fontSize: 13, color: c.ink3)),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref
                      .read(fileNoteProvider(widget.fileId).notifier)
                      .save(_ctrl.text.trim());
                  setState(() => _editing = false);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: SeeUColors.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('Сохранить',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ] else if (note.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surface2.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(SeeURadii.small),
              border: Border.all(color: c.line.withValues(alpha: 0.4)),
            ),
            child: Text(
              note,
              style: TextStyle(
                fontSize: 13,
                color: c.ink2,
                height: 1.5,
              ),
            ),
          ),
        ] else ...[
          Text(
            'Ничего не записано',
            style: TextStyle(fontSize: 13, color: c.ink4),
          ),
        ],
      ],
    );
  }
}

// ─── Expandable Description ─────────────────────────────────────────────────

// ─── Text Preview ────────────────────────────────────────────────────────────

class _TextPreviewSection extends ConsumerWidget {
  final String fileId;
  const _TextPreviewSection({required this.fileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(_textPreviewProvider(fileId));
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (text) {
        if (text == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(PhosphorIconsRegular.textAlignLeft,
                        size: 14, color: c.ink3),
                    const SizedBox(width: 8),
                    Text('Фрагмент текста',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.ink3,
                        )),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  text,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: c.ink2,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ExpandableDescription extends StatefulWidget {
  final String text;
  final SeeUThemeColors c;
  const _ExpandableDescription({required this.text, required this.c});

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isLong = widget.text.length > 200;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _expanded || !isLong
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: Text(
            widget.text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: widget.c.ink2, height: 1.5, fontSize: 14),
          ),
          secondChild: Text(
            widget.text,
            style: TextStyle(color: widget.c.ink2, height: 1.5, fontSize: 14),
          ),
        ),
        if (isLong)
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _expanded ? 'Свернуть' : 'Читать далее',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: SeeUColors.accent,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
