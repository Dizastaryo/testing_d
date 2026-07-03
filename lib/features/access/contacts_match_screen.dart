import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/contact.dart';
import '../../core/providers/access_provider.dart';
import '../../core/providers/chat_provider.dart';
import '../../core/providers/contacts_provider.dart';

/// Экран «Из контактов» (Фаза 2). Читает адресную книгу, нормализует номера и
/// шлёт ТОЛЬКО SHA-256 хэши на сервер — сырые номера устройство не покидают.
/// Показывает найденных в SeeU людей со статусом доступа и кнопкой действия.
class ContactsMatchScreen extends ConsumerStatefulWidget {
  const ContactsMatchScreen({super.key});

  @override
  ConsumerState<ContactsMatchScreen> createState() =>
      _ContactsMatchScreenState();
}

class _ContactsMatchScreenState extends ConsumerState<ContactsMatchScreen> {
  bool _reading = true;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _reading = true;
      _permissionDenied = false;
    });

    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) {
      if (!mounted) return;
      setState(() {
        _reading = false;
        _permissionDenied = true;
      });
      return;
    }

    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final phones = <String>[];
    for (final c in contacts) {
      for (final p in c.phones) {
        final n = p.number.trim();
        if (n.isNotEmpty) phones.add(n);
      }
    }

    if (!mounted) return;
    setState(() => _reading = false);
    await ref.read(contactsProvider.notifier).sync(phones);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: c.bg,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          _buildBody(c),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SeeUGlassBar(
              kicker: 'Найти друзей',
              titleText: 'Из контактов',
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
      ),
    );
  }

  Widget _buildBody(SeeUThemeColors c) {
    if (_permissionDenied) {
      return _PermissionView(onRetry: _load);
    }
    if (_reading) {
      return Center(child: CircularProgressIndicator(color: SeeUColors.accent));
    }

    final state = ref.watch(contactsProvider);
    return state.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: SeeUColors.accent)),
      error: (e, _) => SeeUErrorState(
        error: e.toString(),
        title: 'Не удалось загрузить контакты',
        onRetry: _load,
      ),
      data: (items) {
        if (items.isEmpty) {
          return SeeUEmptyState(
            icon: PhosphorIconsRegular.usersThree,
            title: 'Никого из контактов пока нет',
            subtitle:
                'Когда кто-то из ваших контактов зарегистрируется в SeeU, '
                'он появится здесь.',
            action: SeeUStateAction(
              label: 'Обновить',
              icon: PhosphorIconsRegular.arrowClockwise,
              onTap: _load,
            ),
          );
        }
        return RefreshIndicator(
          color: SeeUColors.accent,
          onRefresh: _load,
          child: ListView.builder(
            padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 56 + 8, bottom: 8),
            itemCount: items.length + 1,
            itemBuilder: (ctx, i) {
              if (i == 0) return const _PrivacyNote();
              return _ContactTile(match: items[i - 1]);
            },
          ),
        );
      },
    );
  }
}

/// Стеклянная заметка о приватности — «КОНФИДЕНЦИАЛЬНО»: номера не покидают
/// устройство, сверка идёт по хэшу.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SeeURadii.medium),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SeeUColors.accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(SeeURadii.medium),
              border: Border.all(
                  color: SeeUColors.accent.withValues(alpha: 0.18), width: 0.8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PhosphorIcon(PhosphorIconsRegular.lockKey,
                    size: 18, color: SeeUColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('КОНФИДЕНЦИАЛЬНО',
                          style: SeeUTypography.kicker
                              .copyWith(color: SeeUColors.accent)),
                      const SizedBox(height: 3),
                      Text(
                        'Номера остаются на устройстве — сверка идёт по защищённому хэшу.',
                        style: SeeUTypography.caption
                            .copyWith(color: c.ink2, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactTile extends ConsumerStatefulWidget {
  final ContactMatch match;
  const _ContactTile({required this.match});

  @override
  ConsumerState<_ContactTile> createState() => _ContactTileState();
}

class _ContactTileState extends ConsumerState<_ContactTile> {
  bool _loading = false;
  bool _requested = false;

  Future<void> _requestAccess() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final status = await ref
          .read(accessNotifierProvider.notifier)
          .requestAccess(widget.match.userId);
      if (!mounted) return;
      setState(() => _requested = true);
      final granted = status == 'granted';
      showSeeUSnackBar(
        context,
        granted ? 'Доступ открыт' : 'Заявка отправлена',
        icon: granted
            ? PhosphorIconsRegular.check
            : PhosphorIconsRegular.paperPlaneTilt,
        tone: granted ? SeeUTone.success : SeeUTone.neutral,
      );
    } catch (_) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Не удалось отправить заявку',
          tone: SeeUTone.danger);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openChat() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final chatId = await ref
          .read(chatListProvider.notifier)
          .getOrCreateChat(widget.match.userId);
      if (!mounted) return;
      if (chatId != null) {
        context.push('/chat/$chatId');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final m = widget.match;

    final Widget action;
    if (m.hasAccess) {
      action = SeeUButton(
        label: 'Написать',
        variant: SeeUButtonVariant.secondary,
        width: 120,
        height: 42,
        onTap: _loading ? null : _openChat,
      );
    } else if (m.requestSent || _requested) {
      action = SeeUButton(
        label: 'Отправлено',
        variant: SeeUButtonVariant.secondary,
        width: 120,
        height: 42,
        onTap: null,
      );
    } else {
      action = SeeUButton(
        label: 'Запросить',
        width: 130,
        height: 42,
        isLoading: _loading,
        onTap: _loading ? null : _requestAccess,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Tappable(
              onTap: () => context.push('/profile/${m.username}'),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: c.surface2,
                    backgroundImage: m.avatarUrl.isNotEmpty
                        ? CachedNetworkImageProvider(m.avatarUrl)
                        : null,
                    child: m.avatarUrl.isEmpty
                        ? Text(
                            m.username.isNotEmpty
                                ? m.username[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                                color: c.ink3, fontWeight: FontWeight.w600),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.fullName.isNotEmpty ? m.fullName : m.username,
                          style: SeeUTypography.body.copyWith(
                              fontWeight: FontWeight.w600, color: c.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text('@${m.username}',
                            style: SeeUTypography.caption
                                .copyWith(color: c.ink3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          action,
        ],
      ),
    );
  }
}

class _PermissionView extends StatelessWidget {
  final VoidCallback onRetry;
  const _PermissionView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SeeUColors.accent.withValues(alpha: 0.12),
              ),
              child: const Center(
                child: PhosphorIcon(PhosphorIconsRegular.addressBook,
                    size: 34, color: SeeUColors.accent),
              ),
            ),
            const SizedBox(height: 18),
            Text('Доступ к контактам',
                style: SeeUTypography.displayS.copyWith(color: c.ink)),
            const SizedBox(height: 8),
            Text(
              'Разрешите доступ к контактам, чтобы найти друзей в SeeU.',
              textAlign: TextAlign.center,
              style: SeeUTypography.body.copyWith(color: c.ink3, height: 1.45),
            ),
            const SizedBox(height: 20),
            const _PrivacyNote(),
            const SizedBox(height: 8),
            SeeUButton(
              label: 'Разрешить',
              icon: PhosphorIconsRegular.lockKeyOpen,
              width: 220,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
