import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../../../core/providers/access_provider.dart';

/// «Доступ» — единственный вход в управление доступом, живёт только на своём
/// профиле (раньше был спрятан в «Настройках», под «Чип», без видимости
/// входящих заявок). Ничего лишнего: счётчик круга + акцентный бейдж новых
/// заявок, если они есть. Тап → список контактов/входящих/отправленных.
class ProfileAccessCard extends ConsumerWidget {
  const ProfileAccessCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final partners = ref.watch(accessListProvider).valueOrNull ?? const [];
    final pending =
        ref.watch(incomingRequestsProvider).valueOrNull ?? const [];
    final pendingCount = pending.length;
    final hasCircle = partners.isNotEmpty;
    final hasPending = pendingCount > 0;

    return Tappable.scaled(
      onTap: () => context.push('/access/list'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.card),
          border: Border.all(
            color: hasPending
                ? SeeUColors.accent.withValues(alpha: 0.35)
                : SeeUColors.accent.withValues(alpha: 0.12),
            width: hasPending ? 1.2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SeeUGradients.heroOrange,
              ),
              child: const Center(
                child: Icon(PhosphorIconsFill.lockKey,
                    color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ДОСТУП',
                      style: SeeUTypography.kicker.copyWith(color: c.ink3)),
                  const SizedBox(height: 2),
                  Text(
                    hasCircle
                        ? '${partners.length} ${_peopleWord(partners.length)} в доступе'
                        : 'Пока никого нет',
                    style: SeeUTypography.displayXS.copyWith(color: c.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (hasPending)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  borderRadius: BorderRadius.circular(SeeURadii.pill),
                ),
                child: Text(
                  '$pendingCount ${_requestWord(pendingCount)}',
                  style: SeeUTypography.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              Icon(PhosphorIconsRegular.caretRight, size: 18, color: c.ink4),
          ],
        ),
      ),
    );
  }

  static String _peopleWord(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'человек';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return 'человека';
    }
    return 'человек';
  }

  static String _requestWord(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'заявка';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return 'заявки';
    }
    return 'заявок';
  }
}
