import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/design/design.dart';
import '../../core/providers/sticker_provider.dart';

/// Экран «Стикер готов» — предпросмотр, выбор набора, сохранение и отправка.
class StickerDoneScreen extends ConsumerWidget {
  final String imageUrl;

  const StickerDoneScreen({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final stickerCount = ref.watch(stickerListProvider).maybeWhen(
          data: (list) => list.length,
          orElse: () => 0,
        );

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(PhosphorIconsBold.caretLeft, color: c.ink),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text(
          'Стикер готов',
          style: SeeUTypography.subtitle.copyWith(color: c.ink),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Preview ───────────────────────────────────────
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 22),
                      child: _StickerPreview(imageUrl: imageUrl),
                    ),
                  ),

                  // ── Section label ─────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Добавить в набор',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.ink2,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),

                  // ── Pack card ─────────────────────────────────────
                  _PackCard(stickerCount: stickerCount, c: c),
                ],
              ),
            ),
          ),
          _BottomBar(
            c: c,
            onDownload: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Ссылка скопирована',
                    style: SeeUTypography.body.copyWith(color: Colors.white),
                  ),
                  backgroundColor: c.ink,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            onSaveAndSend: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }
}

// ─── Превью стикера ────────────────────────────────────────────────

class _StickerPreview extends StatelessWidget {
  final String imageUrl;
  const _StickerPreview({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SeeURadii.medium),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 36,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _CheckerPainter()),
          CachedNetworkImage(
            imageUrl: AppConfig.absUrl(imageUrl),
            fit: BoxFit.contain,
            placeholder: (_, __) => const Center(
              child: CircularProgressIndicator(),
            ),
            errorWidget: (_, __, ___) => const Icon(
              PhosphorIconsRegular.image,
              size: 48,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Карточка выбора набора ────────────────────────────────────────

class _PackCard extends StatefulWidget {
  final int stickerCount;
  final SeeUThemeColors c;
  const _PackCard({required this.stickerCount, required this.c});

  @override
  State<_PackCard> createState() => _PackCardState();
}

class _PackCardState extends State<_PackCard> {
  bool _myPackSelected = true;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(SeeURadii.medium),
        border: Border.all(color: c.line, width: 0.5),
      ),
      child: Column(
        children: [
          // ── Мои стикеры ──────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _myPackSelected = true),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFFB547), SeeUColors.accent],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        PhosphorIconsBold.stack,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Мои стикеры',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${widget.stickerCount} стикеров',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.ink3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_myPackSelected)
                    Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: SeeUColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          PhosphorIconsBold.check,
                          color: Colors.white,
                          size: 13,
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: c.line, width: 1.5),
                      ),
                    ),
                ],
              ),
            ),
          ),

          Divider(height: 1, color: c.line, indent: 10, endIndent: 10),

          // ── Новый набор ───────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _myPackSelected = false),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: c.accentSoft,
                    ),
                    child: const Center(
                      child: Icon(
                        PhosphorIconsRegular.plus,
                        color: SeeUColors.accent,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Новый набор',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: SeeUColors.accent,
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
}

// ─── Нижняя панель ────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final SeeUThemeColors c;
  final VoidCallback onDownload;
  final VoidCallback onSaveAndSend;

  const _BottomBar({
    required this.c,
    required this.onDownload,
    required this.onSaveAndSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // ── Скачать ────────────────────────────────────
            GestureDetector(
              onTap: onDownload,
              child: Container(
                width: 56,
                height: 50,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(SeeURadii.medium),
                  border: Border.all(color: c.line, width: 0.5),
                ),
                child: Center(
                  child: Icon(
                    PhosphorIconsRegular.downloadSimple,
                    color: c.ink,
                    size: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // ── Сохранить и отправить ─────────────────────
            Expanded(
              child: GestureDetector(
                onTap: onSaveAndSend,
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: SeeUGradients.heroOrange,
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                    boxShadow: [
                      BoxShadow(
                        color: SeeUColors.accent.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          PhosphorIconsRegular.paperPlaneRight,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Сохранить и отправить',
                          style: SeeUTypography.body.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
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

// ─── Шахматная подложка ───────────────────────────────────────────

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const double cell = 16;
    final paint = Paint();
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final light = ((x ~/ cell) + (y ~/ cell)) % 2 == 0;
        paint.color = light ? Colors.white : const Color(0xFFECE5DA);
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
