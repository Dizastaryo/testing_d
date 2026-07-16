import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/design/design.dart';
import '../../../core/models/audio_track.dart';
import '../audio_design.dart';

/// Мой загруженный трек и его статус модерации.
///
/// Отклонённый трек — самый болезненный момент во всём сервисе, и оставлять его
/// с «Ошибка» нельзя. Человек должен понять **что не так** (причина модератора
/// текстом) и **что делать дальше** («Изменить и отправить» — не начинать с
/// нуля). У «на проверке» назван срок и сказано, что трек виден только автору:
/// никакой тревоги «а он вообще загрузился?».
class ModerationCard extends ConsumerWidget {
  final AudioTrack track;
  final VoidCallback onChanged;

  const ModerationCard({
    super.key,
    required this.track,
    required this.onChanged,
  });

  bool get _rejected => track.status == 'rejected';
  bool get _pending => track.status == 'pending';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(_rejected ? 14 : 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _rejected ? AudioColors.rejectedBorder : c.line,
          width: _rejected ? 1.5 : 1,
        ),
        boxShadow: _rejected
            ? [
                BoxShadow(
                  color: SeeUColors.error.withValues(alpha: 0.3),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                  spreadRadius: -14,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _cover(context),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    _badge(context, dark),
                    if (_pending) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Пока виден только тебе',
                        style: TextStyle(fontSize: 11, color: c.ink3),
                      ),
                    ],
                  ],
                ),
              ),
              if (track.status == 'approved') ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _counter(c, formatCount(track.playsCount),
                        PhosphorIconsFill.play, c.ink3),
                    const SizedBox(height: 3),
                    _counter(c, formatCount(track.likesCount),
                        PhosphorIconsFill.heart, SeeUColors.like),
                  ],
                ),
              ],
            ],
          ),

          if (_rejected) ...[
            const SizedBox(height: 12),
            // Причина — человеческим текстом от модератора, а не кодом ошибки.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: dark
                    ? SeeUColors.error.withValues(alpha: 0.1)
                    : const Color(0xFFFDF4F3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AudioColors.rejectedBorder.withValues(alpha: 0.7),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ПРИЧИНА ОТ МОДЕРАТОРА',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: dark ? SeeUColors.error : AudioColors.rejected,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    track.rejectionReason.isNotEmpty
                        ? track.rejectionReason
                        : 'Модератор не оставил комментарий. Попробуй заменить '
                            'обложку или название и отправить снова.',
                    style:
                        TextStyle(fontSize: 13, height: 1.5, color: c.ink2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Tappable.scaled(
                    // Ведёт в ту же форму с заполненными полями — менять надо
                    // одно, а не загружать всё заново.
                    onTap: () => context.push('/music/upload',
                        extra: track),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: SeeUColors.accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(PhosphorIconsFill.pencilSimple,
                              size: 15, color: Colors.white),
                          SizedBox(width: 7),
                          Text(
                            'Изменить и отправить',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                // Удаление — вторичное: тихая иконка, а не красная кнопка во
                // всю ширину.
                Tappable.scaled(
                  onTap: () => _delete(context, ref),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(PhosphorIcons.trash(), size: 19, color: c.ink3),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _cover(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        TrackCover(track: track, size: 50, radius: 11),
        if (_pending)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Container(
                color: (dark ? Colors.black : Colors.white)
                    .withValues(alpha: 0.55),
                alignment: Alignment.center,
                child: Icon(PhosphorIconsFill.hourglassMedium,
                    size: 20, color: context.seeuColors.ink),
              ),
            ),
          ),
        if (_rejected)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Container(
                color: SeeUColors.error.withValues(alpha: 0.18),
                alignment: Alignment.center,
                child: const Icon(PhosphorIconsFill.warningCircle,
                    size: 20, color: SeeUColors.error),
              ),
            ),
          ),
      ],
    );
  }

  Widget _badge(BuildContext context, bool dark) {
    final (bg, fg, icon, text) = switch (track.status) {
      'pending' => (
          dark
              ? SeeUColors.warning.withValues(alpha: 0.14)
              : AudioColors.pendingBg,
          dark ? SeeUColors.amber : AudioColors.pending,
          PhosphorIconsFill.clock,
          'На проверке · ≈ до суток',
        ),
      'rejected' => (
          dark
              ? SeeUColors.error.withValues(alpha: 0.14)
              : AudioColors.rejectedBg,
          dark ? SeeUColors.error : AudioColors.rejected,
          PhosphorIconsFill.xCircle,
          'Отклонён',
        ),
      _ => (
          dark
              ? SeeUColors.success.withValues(alpha: 0.14)
              : AudioColors.approvedBg,
          dark ? SeeUColors.success : AudioColors.approved,
          PhosphorIconsFill.checkCircle,
          'Опубликован',
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _counter(SeeUThemeColors c, String value, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: TextStyle(fontSize: 11, color: c.ink3)),
        const SizedBox(width: 4),
        Icon(icon, size: 9, color: color),
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    final ok = await showSeeUConfirm(
      context,
      title: 'Удалить трек?',
      message:
          'Он исчезнет насовсем — из твоих загрузок, из плейлистов и у всех, '
          'кто его сохранил.',
      confirmLabel: 'Удалить',
      destructive: true,
      icon: PhosphorIcons.trash(),
    );
    if (!ok) return;

    try {
      await ref
          .read(apiClientProvider)
          .delete(ApiEndpoints.audioTrackDelete(track.id));
      onChanged();
      if (context.mounted) {
        showSeeUSnackBar(context, 'Трек удалён', tone: SeeUTone.success);
      }
    } catch (_) {
      if (context.mounted) {
        showSeeUSnackBar(context, 'Не удалось удалить',
            tone: SeeUTone.danger);
      }
    }
  }
}
