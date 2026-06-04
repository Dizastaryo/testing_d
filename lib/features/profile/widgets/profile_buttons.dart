import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../../../core/models/user.dart';
import '../../../core/providers/blocks_provider.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../core/providers/user_provider.dart';

class ProfileStoryRingPainter extends CustomPainter {
  final bool seen;
  const ProfileStoryRingPainter({required this.seen});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..shader = seen
          ? const LinearGradient(
              colors: [SeeUColors.textQuaternary, SeeUColors.textQuaternary],
            ).createShader(rect)
          : const SweepGradient(
              colors: [
                Color(0xFFFFB547), Color(0xFFFF5A3C),
                Color(0xFFC04CFD), Color(0xFFFFB547),
              ],
              stops: [0.0, 0.33, 0.66, 1.0],
            ).createShader(rect);
    canvas.drawOval(
      Rect.fromLTWH(1.25, 1.25, size.width - 2.5, size.height - 2.5), paint);
  }

  @override
  bool shouldRepaint(ProfileStoryRingPainter old) => old.seen != seen;
}

class ProfileHeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  const ProfileHeaderIconButton({super.key, required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    Widget button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: c.surface, shape: BoxShape.circle,
          border: Border.all(color: c.line, width: 0.5),
        ),
        child: Center(child: Icon(icon, size: 18, color: c.ink)),
      ),
    );
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

class ProfileTabButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  const ProfileTabButton({super.key, required this.icon, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? c.ink : Colors.transparent, width: 1.5),
            ),
          ),
          child: Center(child: Icon(icon, size: 20, color: isActive ? c.ink : c.ink3)),
        ),
      ),
    );
  }
}

class ProfileActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isPrimary;
  const ProfileActionButton({super.key, required this.label, this.onTap, this.isPrimary = false});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: isPrimary ? SeeUColors.accent : c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
        ),
        child: Center(
          child: Text(label,
              style: SeeUTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isPrimary ? Colors.white : c.ink)),
        ),
      ),
    );
  }
}

class ProfileActionIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const ProfileActionIconButton({super.key, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
        ),
        child: Center(child: Icon(icon, size: 18, color: c.ink)),
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
          onTap: () => context.push('/profile/edit'),
        )),
        const SizedBox(width: 8),
        Expanded(child: ProfileActionButton(
          label: 'Поделиться',
          onTap: () {
            Clipboard.setData(ClipboardData(text: 'https://seeu.app/profile/${user.username}'));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ссылка на профиль скопирована')));
          },
        )),
        const SizedBox(width: 8),
        ProfileActionIconButton(
          icon: PhosphorIcons.userPlus(),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Скоро'))),
        ),
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

  Future<void> _toggleFollow() async {
    final err = await ref
        .read(userProfileProvider(widget.user.username).notifier)
        .toggleFollow();
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _unblock() async {
    final err =
        await ref.read(blocksProvider.notifier).unblock(widget.user.username);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось разблокировать: $err')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('@${widget.user.username} разблокирован')));
    ref.invalidate(userProfileProvider(widget.user.username));
  }

  /// Получаем или создаём переписку с пользователем, затем переходим в неё.
  /// Передавать user.id напрямую в /chat/:id нельзя — ChatScreen ждёт
  /// conversation ID, а не user ID.
  Future<void> _openChat() async {
    if (_chatLoading) return;
    setState(() => _chatLoading = true);
    try {
      final chatId = await ref
          .read(chatListProvider.notifier)
          .getOrCreateChat(widget.user.id);
      if (!mounted) return;
      if (chatId == null || chatId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось открыть переписку')));
        return;
      }
      context.push('/chat/$chatId');
    } finally {
      if (mounted) setState(() => _chatLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBlocked = ref.watch(blocksProvider).maybeWhen(
      data: (items) =>
          items.any((b) => b.username == widget.user.username),
      orElse: () => false,
    );
    if (isBlocked) {
      return ProfileActionButton(
          label: 'Разблокировать', onTap: _unblock);
    }
    final Widget followBtn;
    if (widget.user.isFollowing) {
      followBtn =
          ProfileActionButton(label: 'Отписаться', onTap: _toggleFollow);
    } else if (widget.user.hasPendingFollowRequest) {
      followBtn = ProfileActionButton(
          label: 'Запрос отправлен', onTap: _toggleFollow);
    } else {
      followBtn = ProfileActionButton(
          label: 'Подписаться', isPrimary: true, onTap: _toggleFollow);
    }
    return Row(
      children: [
        Expanded(child: followBtn),
        const SizedBox(width: 8),
        Expanded(
          child: _chatLoading
              ? Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: context.seeuColors.surface2,
                    borderRadius:
                        BorderRadius.circular(SeeURadii.medium),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: SeeUColors.accent),
                    ),
                  ),
                )
              : ProfileActionButton(
                  label: 'Сообщение', onTap: _openChat),
        ),
      ],
    );
  }
}
