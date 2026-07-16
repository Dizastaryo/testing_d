import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/design/design.dart';
import '../../core/providers/card_provider.dart';
import '../../core/providers/scanner_provider.dart';
import '../spark/spark_send_sheet.dart';

/// Показ чужой карточки при открытии из сканера. Само открытие фиксируется как
/// просмотр (view-as-event) — владелец увидит, что его посмотрели. Никакой
/// реальной личности здесь нет: только карточка (фото/никнейм/текст).
class CardDetailSheet {
  static Future<void> show(
    BuildContext context,
    WidgetRef ref,
    ScanProfile card,
  ) async {
    final api = ref.read(apiClientProvider);
    ScanProfile shown = card;
    // Открытие карточки = событие. Если запись не удалась (нет браслета,
    // блокировка) — карточку не показываем.
    if (card.ownerId.isNotEmpty) {
      try {
        final fresh = await openCard(api, card.ownerId);
        if (fresh != null) shown = fresh;
      } on DioException catch (e) {
        if (context.mounted) {
          showSeeUSnackBar(context, apiErrorMessage(e), tone: SeeUTone.danger);
        }
        return;
      }
    }
    if (!context.mounted) return;
    await showSeeUBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CardDetailBody(card: shown),
    );
  }
}

class _CardDetailBody extends ConsumerStatefulWidget {
  final ScanProfile card;
  const _CardDetailBody({required this.card});

  @override
  ConsumerState<_CardDetailBody> createState() => _CardDetailBodyState();
}

class _CardDetailBodyState extends ConsumerState<_CardDetailBody> {
  bool _busy = false;

  Future<void> _block() async {
    final ok = await showSeeUConfirm(
      context,
      title: 'Заблокировать карточку?',
      message:
          'Этот человек больше не увидит твою карточку рядом, не сможет открыть '
          'её и отправить тебе Spark. Снять блокировку сможешь только ты.',
      confirmLabel: 'Заблокировать',
      destructive: true,
      icon: PhosphorIcons.prohibit(),
    );
    if (!ok || _busy) return;
    setState(() => _busy = true);
    final api = ref.read(apiClientProvider);
    final done = await blockCard(api, widget.card.ownerId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (done) {
      showSeeUSnackBar(context, 'Карточка заблокирована', tone: SeeUTone.success);
      Navigator.of(context).pop();
    } else {
      showSeeUSnackBar(context, 'Не удалось заблокировать',
          tone: SeeUTone.danger);
    }
  }

  void _spark() {
    Navigator.of(context).pop();
    SparkSendSheet.show(
      context,
      ref,
      receiverId: widget.card.ownerId,
      receiverName: widget.card.displayName,
      proofDeviceHash: widget.card.deviceHash,
      avatarUrl: widget.card.photoUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final card = widget.card;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 46,
              backgroundColor: c.surface2,
              backgroundImage: card.photoUrl.isNotEmpty
                  ? CachedNetworkImageProvider(card.photoUrl)
                  : null,
              child: card.photoUrl.isEmpty
                  ? Icon(PhosphorIcons.user(), size: 40, color: c.ink3)
                  : null,
            ),
            const SizedBox(height: 12),
            Text(card.displayName,
                style: SeeUTypography.subtitle
                    .copyWith(fontWeight: FontWeight.w800, color: c.ink)),
            if (card.text.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(card.text,
                  textAlign: TextAlign.center,
                  style: SeeUTypography.body.copyWith(color: c.ink2, height: 1.4)),
            ],
            const SizedBox(height: 8),
            Text(
              'Он увидит, что ты открыл его карточку.',
              style: SeeUTypography.caption.copyWith(color: c.ink3),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SeeUButton(
                    label: 'Spark',
                    onTap: _busy ? null : _spark,
                  ),
                ),
                const SizedBox(width: 12),
                Tappable.scaled(
                  onTap: _busy ? null : _block,
                  scaleFactor: 0.95,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: SeeUColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(SeeURadii.medium),
                    ),
                    child: Icon(PhosphorIcons.prohibit(),
                        color: SeeUColors.danger, size: 22),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
