import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/library_provider.dart';
import '../../core/utils/format.dart';
import 'readers/open_reader.dart';
import 'library_design.dart';

/// Типичное время конвертации — «обычно меньше минуты». Бэкенд процентов не
/// отдаёт, поэтому прогресс и «осталось ~N сек» оцениваем по времени с момента,
/// когда файл впервые замечен в очереди (потолок 95%, чтобы не врать про 100).
const _typicalConversionSeconds = 60;

/// Страница слежения за подготовкой файлов к чтению.
///
/// Показывает собственные файлы пользователя форматов FB2/DOCX/RTF/ODT/PPTX/ODP.
/// Если готовится один файл — полноэкранная композиция с корешком и прогрессом;
/// несколько — текущий крупно, остальные компактным списком.
/// Обновляется каждые 3 секунды.
class FilePreparationScreen extends ConsumerStatefulWidget {
  const FilePreparationScreen({super.key});

  @override
  ConsumerState<FilePreparationScreen> createState() =>
      _FilePreparationScreenState();
}

class _FilePreparationScreenState extends ConsumerState<FilePreparationScreen> {
  Timer? _timer;

  /// Когда файл впервые замечен в подготовке — база оценки прогресса.
  final Map<String, DateTime> _firstSeen = {};

  @override
  void initState() {
    super.initState();
    // Опрашиваем каждые 3 секунды пока экран открыт
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final userId = ref.read(authProvider).user?.id ?? '';
      if (userId.isNotEmpty) ref.invalidate(userFilesProvider(userId));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Оценка прогресса конвертации (0..0.95) по времени в очереди.
  double _estimatedProgress(FileItem f) {
    final seen = _firstSeen.putIfAbsent(f.id, DateTime.now);
    final elapsed = DateTime.now().difference(seen).inSeconds;
    return (elapsed / _typicalConversionSeconds).clamp(0.0, 0.95);
  }

  /// «осталось ~15 сек» — по той же оценке; в конце честное «почти готово».
  String _estimatedRemaining(FileItem f) {
    final seen = _firstSeen.putIfAbsent(f.id, DateTime.now);
    final elapsed = DateTime.now().difference(seen).inSeconds;
    final left = _typicalConversionSeconds - elapsed;
    if (left <= 5) return 'почти готово';
    // Округляем до 5 сек, чтобы цифра не дёргалась каждый тик.
    final rounded = (left / 5).ceil() * 5;
    return 'осталось ~$rounded сек';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.seeuColors;
    final userId = ref.watch(authProvider).user?.id ?? '';
    final async = ref.watch(userFilesProvider(userId));

    final topInset = MediaQuery.of(context).padding.top + 60;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      body: PaperBackground(
        child: Stack(children: [
          async.when(
            data: (files) {
              final convertible =
                  files.where((f) => f.needsPreparation).toList();

              if (convertible.isEmpty) return _buildEmptyState(c);

              // Активная подготовка: в работе и в очереди.
              final active = convertible
                  .where((f) =>
                      f.pdfConversionStatus == 'pending' ||
                      f.pdfConversionStatus == 'converting' ||
                      f.pdfConversionStatus == 'none')
                  .toList();
              final failed = convertible
                  .where((f) => f.pdfConversionStatus == 'failed')
                  .toList();
              final done = convertible
                  .where((f) => f.pdfConversionStatus == 'done')
                  .toList();

              return RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(userFilesProvider(userId)),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(20, topInset + 8, 20, 120),
                  children: [
                    // Текущий файл — крупная композиция с корешком.
                    if (active.isNotEmpty) ...[
                      _ConversionHero(
                        file: active.first,
                        progress: _estimatedProgress(active.first),
                        remainingLabel: _estimatedRemaining(active.first),
                      ),
                      const SizedBox(height: 28),
                    ],
                    // Остальные в очереди — компактным списком.
                    if (active.length > 1) ...[
                      _sectionHeader(c, 'В очереди', active.length - 1),
                      const SizedBox(height: 10),
                      ...active.skip(1).map((f) => _CompactFileRow(
                            file: f,
                            trailing: const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: SeeUColors.accent),
                            ),
                            subtitle: 'Ждёт своей очереди',
                            subtitleColor: c.ink3,
                          )),
                      const SizedBox(height: 20),
                    ],
                    // Ошибки конвертации — честная карточка с «Повторить».
                    if (failed.isNotEmpty) ...[
                      _sectionHeader(c, 'Не получилось', failed.length),
                      const SizedBox(height: 10),
                      ...failed.map((f) => _FailedCard(
                            file: f,
                            onRetry: () => _retry(f),
                          )),
                      const SizedBox(height: 20),
                    ],
                    // Готовые к чтению.
                    if (done.isNotEmpty) ...[
                      _sectionHeader(c, 'Готово к чтению', done.length),
                      const SizedBox(height: 10),
                      ...done.map((f) => _CompactFileRow(
                            file: f,
                            subtitle: 'Конвертирован в PDF',
                            subtitleColor: SeeUColors.success,
                            trailing: Tappable.scaled(
                              onTap: () => openReader(context, f),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: SeeUColors.accent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Читать',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          )),
                    ],
                  ],
                ),
              );
            },
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(e.toString(),
                  style: SeeUTypography.caption.copyWith(
                      color: context.seeuColors.ink3)),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SeeUGlassBar(
              kicker: 'Библиотека',
              titleText: 'Подготовка файлов',
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: LibBackButton(),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildEmptyState(SeeUThemeColors c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: SeeUColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(PhosphorIcons.checkCircle(), size: 32,
                color: SeeUColors.success),
          ),
          const SizedBox(height: 20),
          Text('Все файлы готовы',
              style: SeeUTypography.displayS.copyWith(color: c.ink)),
          const SizedBox(height: 6),
          Text('Нет файлов в очереди подготовки',
              style: SeeUTypography.caption.copyWith(color: c.ink3)),
        ],
      ),
    );
  }

  Widget _sectionHeader(SeeUThemeColors c, String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: SeeUTypography.displayS.copyWith(fontSize: 20, color: c.ink),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: SeeUColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: SeeUColors.accent),
          ),
        ),
      ],
    );
  }

  Future<void> _retry(FileItem file) async {
    try {
      // GET /pdf инициирует повторную постановку в очередь (статус failed → pending)
      final dio = ref.read(libraryApiClientProvider);
      await dio.get(ApiEndpoints.filePdf(file.id));
    } catch (_) {}
    // Повторная попытка — оценка прогресса с нуля.
    _firstSeen.remove(file.id);
    final userId = ref.read(authProvider).user?.id ?? '';
    ref.invalidate(userFilesProvider(userId));
  }
}

// ─── Крупная композиция конвертации ─────────────────────────────────────────

/// Корешок 130×180 с песочными часами, кикер «FB2 → PDF», «Готовим к чтению»
/// и полоса прогресса с оценкой — как в дизайне.
class _ConversionHero extends StatelessWidget {
  final FileItem file;
  final double progress;
  final String remainingLabel;

  const _ConversionHero({
    required this.file,
    required this.progress,
    required this.remainingLabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final pct = (progress * 100).round();

    return Column(
      children: [
        const SizedBox(height: 16),
        // Корешок с песочными часами в нижней трети.
        SizedBox(
          width: 130,
          height: 180,
          child: Stack(
            children: [
              BookSpine(file: file, width: 130, height: 180, radius: 12),
              // Лёгкое затемнение, чтобы белые часы читались на любой обложке.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(5.4),
                        bottomLeft: const Radius.circular(5.4),
                        topRight: const Radius.circular(12),
                        bottomRight: const Radius.circular(12),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.35),
                        ],
                        stops: const [0.55, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Icon(PhosphorIconsFill.hourglass,
                    size: 22, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Кикер: формат исходника → PDF.
        Text(
          '${file.fileExtension.toUpperCase()} → PDF',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.5,
            color: LibColors.kicker(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Готовим к чтению',
          textAlign: TextAlign.center,
          style: SeeUTypography.displayS.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Конвертируем документ. Обычно меньше минуты.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.5, color: c.ink3),
        ),
        const SizedBox(height: 20),
        // Прогресс: «68%» слева, «осталось ~15 сек» справа, бар 6px градиент.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$pct%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: SeeUColors.accent,
                    ),
                  ),
                  Text(
                    remainingLabel,
                    style: TextStyle(fontSize: 12, color: c.ink3),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              LibProgressBar(
                value: progress,
                height: 6,
                gradient: const LinearGradient(
                  colors: [SeeUColors.accent, SeeUColors.accentSecondary],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Компактная строка файла ────────────────────────────────────────────────

class _CompactFileRow extends StatelessWidget {
  final FileItem file;
  final Widget trailing;
  final String subtitle;
  final Color subtitleColor;

  const _CompactFileRow({
    required this.file,
    required this.trailing,
    required this.subtitle,
    required this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.seeuColors;
    final fmtColor = colorForFileType(file.fileExtension);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: LibColors.line(context)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // Формат-бейдж
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: fmtColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                file.formatLabel,
                style: TextStyle(
                  fontFamily: AppFonts.I.sans,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: fmtColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        height: 1.3,
                        color: c.ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: subtitleColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }
}

// ─── Карточка ошибки ────────────────────────────────────────────────────────

/// Честная карточка неудачной конвертации: что случилось + «Повторить».
class _FailedCard extends StatelessWidget {
  final FileItem file;
  final VoidCallback onRetry;

  const _FailedCard({required this.file, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SeeUColors.error.withValues(alpha: 0.05),
          border:
              Border.all(color: SeeUColors.error.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: SeeUColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(PhosphorIcons.cloudWarning(),
                  size: 20, color: SeeUColors.error),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        height: 1.3,
                        color: c.ink),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Не удалось сконвертировать',
                    style: TextStyle(fontSize: 11, color: SeeUColors.error),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Tappable.scaled(
              onTap: onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: SeeUColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Повторить',
                  style: TextStyle(
                    color: SeeUColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
