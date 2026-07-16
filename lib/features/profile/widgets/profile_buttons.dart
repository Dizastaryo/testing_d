import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../../../core/models/user.dart';
import '../../../core/providers/access_provider.dart';
import '../../../core/providers/blocks_provider.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../core/providers/user_provider.dart';


class ProfileHeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  const ProfileHeaderIconButton({super.key, required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    Widget button = SeeUGlassCircleButton(
      onTap: onTap,
      size: 44,
      icon: Icon(icon, size: 18, color: c.ink),
    );
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// Стили кнопок профиля (§05):
/// [primary] — коралловая CTA 44 r13 («Подписаться»);
/// [outline] — белая с коралловым бордюром 1.5 («Написать»);
/// [soft] — тихая surface2 36 r12 (свой профиль: «Редактировать»);
/// [muted] — приглушённая недоступность («Запросить доступ» / «Заявка отправлена»).
enum ProfileButtonStyle { primary, outline, soft, muted }

class ProfileActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final ProfileButtonStyle style;
  final Widget? icon;
  /// Высота: свой профиль 36, чужой 44 (по дизайну).
  final double height;
  const ProfileActionButton({
    super.key,
    required this.label,
    this.onTap,
    this.style = ProfileButtonStyle.soft,
    this.icon,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final Color bg;
    final Color fg;
    Border? border;
    List<BoxShadow>? shadow;
    switch (style) {
      case ProfileButtonStyle.primary:
        bg = SeeUColors.accent;
        fg = Colors.white;
        shadow = SeeUShadows.sm;
        break;
      case ProfileButtonStyle.outline:
        bg = c.surface;
        fg = SeeUColors.accent;
        border = Border.all(color: SeeUColors.accent, width: 1.5);
        break;
      case ProfileButtonStyle.soft:
        bg = c.surface2;
        fg = c.ink;
        break;
      case ProfileButtonStyle.muted:
        bg = c.surface2;
        fg = c.ink4;
        border = Border.all(color: c.line);
        break;
    }
    // Радиусы из дизайна: 13 для ряда чужого профиля (44), 12 для своего (36).
    final radius = height >= 44 ? 13.0 : 12.0;
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          border: border,
          boxShadow: shadow,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 7)],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SeeUTypography.caption.copyWith(
                      fontSize: height >= 44 ? 14 : 13,
                      fontWeight: FontWeight.w600,
                      color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileOwnButtons extends StatelessWidget {
  final User user;
  const ProfileOwnButtons({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: ProfileActionButton(
          label: 'Редактировать',
          height: 36,
          onTap: () => context.push('/profile/edit'),
        )),
        const SizedBox(width: 8),
        Expanded(child: ProfileActionButton(
          label: 'Поделиться профилем',
          height: 36,
          onTap: () {
            Clipboard.setData(ClipboardData(text: 'https://seeu.app/profile/${user.username}'));
            showSeeUSnackBar(context, 'Ссылка на профиль скопирована',
                tone: SeeUTone.success);
          },
        )),
      ],
    );
  }
}

class ProfileOtherButtons extends ConsumerStatefulWidget {
  final User user;
  const ProfileOtherButtons({super.key, required this.user});

  @override
  ConsumerState<ProfileOtherButtons> createState() => _ProfileOtherButtonsState();
}

class _ProfileOtherButtonsState extends ConsumerState<ProfileOtherButtons> {
  bool _chatLoading = false;
  bool _accessLoading = false;
  bool _accessRequested = false;

  Future<void> _toggleFollow() async {
    final err = await ref
        .read(userProfileProvider(widget.user.username).notifier)
        .toggleFollow();
    if (err != null && mounted) {
      showSeeUSnackBar(context, err, tone: SeeUTone.danger);
    }
  }

  Future<void> _unblock() async {
    final err =
        await ref.read(blocksProvider.notifier).unblock(widget.user.username);
    if (!mounted) return;
    if (err != null) {
      showSeeUSnackBar(context, 'Не удалось разблокировать: $err',
          tone: SeeUTone.danger);
      return;
    }
    showSeeUSnackBar(context, '@${widget.user.username} разблокирован',
        tone: SeeUTone.success);
    ref.invalidate(userProfileProvider(widget.user.username));
  }

  Future<void> _openChat() async {
    if (_chatLoading) return;
    setState(() => _chatLoading = true);
    try {
      final chatId = await ref
          .read(chatListProvider.notifier)
          .getOrCreateChat(widget.user.id);
      if (!mounted) return;
      if (chatId != null) {
        context.push('/chat/$chatId');
      } else {
        showSeeUSnackBar(context, 'Не удалось открыть чат',
            tone: SeeUTone.danger);
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final body = e.response?.data;
      final msg = (body is Map ? body['error']?.toString() : null) ??
          'Не удалось открыть чат';
      showSeeUSnackBar(context, msg, tone: SeeUTone.danger);
    } finally {
      if (mounted) setState(() => _chatLoading = false);
    }
  }

  // Профиль — удалённый контекст: общение закрыто, отправляем заявку на доступ
  // (очный мгновенный доступ — это отдельный QR/NFC-сценарий вживую).
  Future<void> _requestAccess() async {
    if (_accessLoading) return;
    setState(() => _accessLoading = true);
    try {
      final status = await ref
          .read(accessNotifierProvider.notifier)
          .requestAccess(widget.user.id);
      if (!mounted) return;
      if (status == 'granted') {
        ref.invalidate(accessCheckProvider(widget.user.id));
      } else {
        setState(() => _accessRequested = true);
        // Обновляем серверный список отправленных заявок — pending-состояние
        // кнопки теперь переживает уход/возврат на профиль (раньше жило
        // только в локальном флаге и сбрасывалось, позволяя слать дубли).
        ref.read(sentRequestsProvider.notifier).load();
        showSeeUSnackBar(context, 'Заявка отправлена',
            tone: SeeUTone.success);
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final body = e.response?.data;
      final msg = (body is Map ? body['error']?.toString() : null) ??
          'Не удалось отправить заявку';
      showSeeUSnackBar(context, msg, tone: SeeUTone.danger);
    } finally {
      if (mounted) setState(() => _accessLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBlocked = ref.watch(blocksProvider).maybeWhen(
      data: (items) => items.any((b) => b.username == widget.user.username),
      orElse: () => false,
    );
    if (isBlocked) {
      return ProfileActionButton(label: 'Разблокировать', onTap: _unblock);
    }

    final Widget followBtn;
    if (widget.user.isFollowing) {
      followBtn = ProfileActionButton(label: 'Отписаться', onTap: _toggleFollow);
    } else if (widget.user.hasPendingFollowRequest) {
      followBtn = ProfileActionButton(
          label: 'Запрос отправлен',
          style: ProfileButtonStyle.muted,
          onTap: _toggleFollow);
    } else {
      followBtn = ProfileActionButton(
          label: 'Подписаться',
          style: ProfileButtonStyle.primary,
          icon: Icon(PhosphorIcons.plus(), size: 16, color: Colors.white),
          onTap: _toggleFollow);
    }

    // Access-gated messaging button
    final accessState = ref.watch(accessCheckProvider(widget.user.id));
    final hasAccess = accessState.maybeWhen(data: (v) => v, orElse: () => false);

    // Pending-заявка выводится и из серверного списка sentRequests — не
    // только из локального флага, поэтому переживает возврат на профиль.
    final serverPending = ref.watch(sentRequestsProvider).maybeWhen(
          data: (list) => list.any((r) => r.user.id == widget.user.id),
          orElse: () => false,
        );
    final accessRequested = _accessRequested || serverPending;

    // Без доступа кнопка «Запросить доступ» реально работает только если есть
    // NFC-касание браслетом или совпадение в контактах (сервер иначе отклонит
    // заявку 403) — для случайного чужого профиля из BLE-сканера кнопку не
    // показываем вовсе, чтобы не давать заведомо нерабочее действие.
    if (!hasAccess && !widget.user.canRequestAccess && !accessRequested) {
      return Row(children: [Expanded(child: followBtn)]);
    }

    final Widget messageBtn;
    if (hasAccess) {
      // Доступ есть → активная «Написать» (белая с коралловым бордюром,
      // chat-circle fill — §05 B).
      messageBtn = _chatLoading
          ? const ProfileActionButton(
              label: 'Открытие...', style: ProfileButtonStyle.outline)
          : ProfileActionButton(
              label: 'Написать',
              style: ProfileButtonStyle.outline,
              icon: const Icon(PhosphorIconsFill.chatCircle,
                  size: 16, color: SeeUColors.accent),
              onTap: _openChat);
    } else if (accessRequested) {
      messageBtn = const ProfileActionButton(
          label: 'Заявка отправлена', style: ProfileButtonStyle.muted);
    } else {
      // Доступа нет → приглушённая «Запросить доступ» с фирменной
      // пунктирной иконкой доступа (§05 B, состояние 2).
      messageBtn = _accessLoading
          ? const ProfileActionButton(
              label: 'Отправка...', style: ProfileButtonStyle.muted)
          : ProfileActionButton(
              label: 'Запросить доступ',
              style: ProfileButtonStyle.muted,
              icon: SeeUAccessIcon(
                  size: 16, color: context.seeuColors.ink4),
              onTap: _requestAccess);
    }

    return Row(
      children: [
        Expanded(child: followBtn),
        const SizedBox(width: 8),
        Expanded(child: messageBtn),
      ],
    );
  }
}
