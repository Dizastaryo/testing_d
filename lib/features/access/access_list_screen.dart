import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/access.dart';
import '../../core/providers/access_provider.dart';

/// Экран «Доступы» — три вкладки: входящие заявки, открытые контакты,
/// отправленные заявки. Дизайн спокойный, без давления: нет статуса «отклонено»
/// и счётчиков «сколько висит заявка» (см. спеку, раздел 2.5).
class AccessListScreen extends ConsumerWidget {
  const AccessListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
            onPressed: () => context.pop(),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('КРУГ ОБЩЕНИЯ',
                  style:
                      SeeUTypography.kicker.copyWith(color: SeeUColors.accent)),
              Text(
                'Доступы',
                style: SeeUTypography.displayS.copyWith(color: c.ink),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Знакомство по NFC',
              icon: Icon(PhosphorIcons.wifiHigh(), size: 22, color: c.ink),
              onPressed: () => context.push('/nfc/scan'),
            ),
            IconButton(
              tooltip: 'Стать парой',
              icon: Icon(PhosphorIcons.fireSimple(), size: 22, color: c.ink),
              onPressed: () => context.push('/pairs/prompts'),
            ),
            IconButton(
              tooltip: 'Найти из контактов',
              icon: Icon(PhosphorIcons.addressBook(), size: 22, color: c.ink),
              onPressed: () => context.push('/access/contacts'),
            ),
          ],
          bottom: TabBar(
            labelColor: SeeUColors.accent,
            unselectedLabelColor: c.ink3,
            indicatorColor: SeeUColors.accent,
            labelStyle: SeeUTypography.body.copyWith(fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Входящие'),
              Tab(text: 'Контакты'),
              Tab(text: 'Отправленные'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _IncomingTab(),
            _PartnersTab(),
            _SentTab(),
          ],
        ),
      ),
    );
  }
}

// ── Входящие заявки ─────────────────────────────────────────────────────────────

class _IncomingTab extends ConsumerWidget {
  const _IncomingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(incomingRequestsProvider);

    return state.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: SeeUColors.accent),
      ),
      error: (e, _) => SeeUErrorState(
        error: e.toString(),
        onRetry: () => ref.read(incomingRequestsProvider.notifier).load(),
      ),
      data: (items) {
        if (items.isEmpty) {
          return SeeUEmptyState(
            icon: PhosphorIconsRegular.handWaving,
            title: 'Нет входящих заявок',
            subtitle: 'Здесь появятся люди, которые хотят начать общение.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          itemBuilder: (ctx, i) => _RequestTile(
            request: items[i],
            onAccept: () async {
              final req = items[i];
              await ref.read(incomingRequestsProvider.notifier).accept(req.id);
              ref.read(accessListProvider.notifier).load();
              ref.invalidate(accessCheckProvider(req.user.id));
              if (ctx.mounted) {
                showSeeUSnackBar(ctx, 'Доступ открыт',
                    icon: PhosphorIconsRegular.check, tone: SeeUTone.success);
              }
            },
            onReject: () =>
                ref.read(incomingRequestsProvider.notifier).reject(items[i].id),
          ),
        );
      },
    );
  }
}

class _RequestTile extends StatelessWidget {
  final AccessRequest request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _RequestTile({
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final u = request.user;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
      ),
      child: Row(
        children: [
          _Avatar(username: u.username, avatarUrl: u.avatarUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'НОВАЯ ЗАЯВКА'.toUpperCase(),
                  style: SeeUTypography.kicker.copyWith(color: SeeUColors.accent),
                ),
                const SizedBox(height: 3),
                Text(
                  u.fullName.isNotEmpty ? u.fullName : u.username,
                  style: SeeUTypography.body
                      .copyWith(fontWeight: FontWeight.w600, color: c.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text('@${u.username}',
                    style: SeeUTypography.caption.copyWith(color: c.ink3)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Отклонить (тихо — заявитель не узнаёт, спека 2.5)
          IconButton(
            onPressed: onReject,
            icon: Icon(PhosphorIcons.x(), size: 20, color: c.ink3),
          ),
          SeeUButton(
            label: 'Принять',
            onTap: onAccept,
            width: 104,
            height: 44,
          ),
        ],
      ),
    );
  }
}

// ── Мои контакты (открытый доступ) ──────────────────────────────────────────────

class _PartnersTab extends ConsumerWidget {
  const _PartnersTab();

  Future<void> _confirmRevoke(
      BuildContext context, WidgetRef ref, AccessPartner p) async {
    final ok = await showSeeUConfirm(
      context,
      title: 'Отозвать доступ?',
      message: 'Вы больше не сможете общаться с @${p.username}.',
      confirmLabel: 'Отозвать',
      cancelLabel: 'Отмена',
      destructive: true,
      icon: PhosphorIconsRegular.lockOpen,
    );
    if (ok) {
      await ref.read(accessListProvider.notifier).revoke(p.userId);
      if (context.mounted) {
        showSeeUSnackBar(context, 'Доступ отозван',
            icon: PhosphorIconsRegular.lockOpen, tone: SeeUTone.neutral);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accessListProvider);
    return state.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: SeeUColors.accent),
      ),
      error: (e, _) => SeeUErrorState(
        error: e.toString(),
        onRetry: () => ref.read(accessListProvider.notifier).load(),
      ),
      data: (partners) {
        if (partners.isEmpty) {
          return SeeUEmptyState(
            icon: PhosphorIconsRegular.usersThree,
            title: 'Нет открытого доступа',
            subtitle:
                'Поднесите телефон к браслету или отсканируйте QR — и отправьте заявку.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: partners.length,
          itemBuilder: (ctx, i) => _AccessTile(
            partner: partners[i],
            onRevoke: () => _confirmRevoke(context, ref, partners[i]),
          ),
        );
      },
    );
  }
}

class _AccessTile extends StatelessWidget {
  final AccessPartner partner;
  final VoidCallback onRevoke;

  const _AccessTile({required this.partner, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Dismissible(
      key: Key('access_${partner.userId}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onRevoke();
        return false; // list refreshes via notifier
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: SeeUColors.danger.withValues(alpha: 0.15),
        child: Icon(PhosphorIcons.lockOpen(), color: SeeUColors.danger, size: 22),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: _Avatar(
              username: partner.username, avatarUrl: partner.avatarUrl),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  partner.fullName.isNotEmpty
                      ? partner.fullName
                      : partner.username,
                  style: SeeUTypography.body
                      .copyWith(fontWeight: FontWeight.w600, color: c.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (partner.isVerified) ...[
                const SizedBox(width: 4),
                Icon(PhosphorIcons.sealCheck(),
                    size: 14, color: SeeUColors.accent),
              ],
            ],
          ),
          subtitle: Text('@${partner.username}',
              style: SeeUTypography.caption.copyWith(color: c.ink3)),
          trailing: Icon(PhosphorIcons.caretRight(), size: 16, color: c.ink4),
          onTap: () => context.push('/profile/${partner.username}'),
        ),
      ),
    );
  }
}

// ── Отправленные заявки (ожидание) ──────────────────────────────────────────────

class _SentTab extends ConsumerWidget {
  const _SentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final state = ref.watch(sentRequestsProvider);
    return state.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: SeeUColors.accent),
      ),
      error: (e, _) => SeeUErrorState(
        error: e.toString(),
        onRetry: () => ref.read(sentRequestsProvider.notifier).load(),
      ),
      data: (items) {
        if (items.isEmpty) {
          return SeeUEmptyState(
            icon: PhosphorIconsRegular.paperPlaneTilt,
            title: 'Нет отправленных заявок',
            subtitle: 'Заявки, которые вы отправили, появятся здесь.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final u = items[i].user;
            return Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: _Avatar(username: u.username, avatarUrl: u.avatarUrl),
                title: Text(
                  u.fullName.isNotEmpty ? u.fullName : u.username,
                  style: SeeUTypography.body
                      .copyWith(fontWeight: FontWeight.w600, color: c.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('@${u.username}',
                    style: SeeUTypography.caption.copyWith(color: c.ink3)),
                trailing: Text('ОЖИДАНИЕ'.toUpperCase(),
                    style: SeeUTypography.kicker.copyWith(color: c.ink4)),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Shared bits ─────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String username;
  final String avatarUrl;
  const _Avatar({required this.username, required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return CircleAvatar(
      radius: 24,
      backgroundColor: c.surface2,
      backgroundImage:
          avatarUrl.isNotEmpty ? CachedNetworkImageProvider(avatarUrl) : null,
      child: avatarUrl.isEmpty
          ? Text(
              username.isNotEmpty ? username[0].toUpperCase() : '?',
              style: TextStyle(color: c.ink3, fontWeight: FontWeight.w600),
            )
          : null,
    );
  }
}
