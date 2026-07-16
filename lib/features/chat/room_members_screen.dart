import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/room.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/room_provider.dart';
import '../../core/utils/format.dart';

/// Русское склонение слова по числу: [one] (1), [few] (2–4), [many] (5+).
String _plural(int n, String one, String few, String many) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14)) return few;
  return many;
}

/// Экран участников комнаты.
///
/// - Все участники видят список.
/// - Создатель: может удалять участников и добавлять новых.
/// - Не-создатель: внизу кнопка «Покинуть комнату».
class RoomMembersScreen extends ConsumerStatefulWidget {
  final String roomId;
  final String creatorId;

  const RoomMembersScreen({
    super.key,
    required this.roomId,
    required this.creatorId,
  });

  @override
  ConsumerState<RoomMembersScreen> createState() => _RoomMembersScreenState();
}

class _RoomMembersScreenState extends ConsumerState<RoomMembersScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final membersState = ref.watch(roomMembersProvider(widget.roomId));
    final myId = ref.watch(authProvider).user?.id ?? '';
    final isCreator = myId == widget.creatorId;
    final myMember = membersState.members.where((m) => m.userId == myId).firstOrNull;
    final isAdmin = isCreator || (myMember?.isAdmin ?? false);

    final q = _searchQuery.trim().toLowerCase();
    final filteredMembers = q.isEmpty
        ? membersState.members
        : membersState.members
            .where((m) =>
                m.fullName.toLowerCase().contains(q) ||
                m.username.toLowerCase().contains(q))
            .toList();

    final memberCount = membersState.members.length;

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          // Header
          SeeUGlassBar(
            titleText: 'Участники',
            kicker:
                '$memberCount ${_plural(memberCount, 'участник', 'участника', 'участников')}',
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(PhosphorIcons.caretLeft(PhosphorIconsStyle.bold),
                    size: 22, color: c.ink),
              ),
            ),
            actions: [
              // Поделиться кодом входа — доступно любому участнику (приглашений нет).
              GestureDetector(
                onTap: _showRoomCode,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(PhosphorIcons.key(), size: 22, color: c.ink),
                ),
              ),
            ],
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  const SizedBox(height: 8),

                  // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(SeeURadii.small),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 300),
                      () { if (mounted) setState(() => _searchQuery = v); },
                    );
                  },
                  style: SeeUTypography.body.copyWith(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Поиск участника',
                    hintStyle: SeeUTypography.body.copyWith(fontSize: 14, color: c.ink3),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 12, right: 8),
                      child: Icon(PhosphorIconsRegular.magnifyingGlass, color: c.ink3, size: 16),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 40),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchDebounce?.cancel();
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Icon(PhosphorIconsFill.xCircle, color: c.ink3, size: 16),
                            ),
                          )
                        : null,
                    suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 40),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ),

            // Hint when list is large: client-side search covers only loaded members.
            if (membersState.members.length >= 50 && _searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Row(
                  children: [
                    Icon(PhosphorIconsRegular.info, size: 12, color: c.ink3),
                    const SizedBox(width: 4),
                    Text(
                      'Поиск среди ${membersState.members.length} загруженных участников',
                      style: TextStyle(fontSize: 11, color: c.ink3),
                    ),
                  ],
                ),
              ),

            // Content
            Expanded(
              child: membersState.isLoading && membersState.members.isEmpty
                  ? const SeeUListSkeleton(count: 6)
                  : membersState.error != null && membersState.members.isEmpty
                      ? _buildError(c, membersState.error!)
                      : filteredMembers.isEmpty && _searchQuery.isNotEmpty
                          ? Center(
                              child: Text(
                                'Никого не найдено',
                                style: TextStyle(color: c.ink3, fontSize: 13),
                              ),
                            )
                          : _buildList(c, filteredMembers, myId, isCreator, isAdmin),
            ),

                  // Leave button for non-creators
                  if (!isCreator)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: _LeaveButton(
                        roomId: widget.roomId,
                        myId: myId,
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

  Widget _buildList(
    SeeUThemeColors c,
    List<RoomMember> members,
    String myId,
    bool isCreator,
    bool isAdmin,
  ) {
    final admins = members.where((m) => m.isCreator || m.isAdmin).toList();
    final regular = members.where((m) => !m.isCreator && !m.isAdmin).toList();

    Widget sectionHeader(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
      child: Text(
        label,
        style: SeeUTypography.kicker.copyWith(color: c.ink3),
      ),
    );

    final items = <Widget>[
      if (admins.isNotEmpty) sectionHeader('АДМИНИСТРАТОРЫ · ${admins.length}'),
      ...admins.map((m) {
        final isSelf = m.userId == myId;
        final canRemove = isAdmin && !isSelf && !m.isCreator && isCreator;
        final canToggleAdmin = isCreator && !isSelf && !m.isCreator;
        return _MemberTile(
          member: m, isSelf: isSelf,
          canRemove: canRemove, canToggleAdmin: canToggleAdmin,
          onRemove: canRemove ? () => _confirmRemove(c, m) : null,
          onToggleAdmin: canToggleAdmin ? () => _confirmToggleAdmin(c, m) : null,
          c: c,
        );
      }),
      if (regular.isNotEmpty) sectionHeader('УЧАСТНИКИ · ${regular.length}'),
      ...regular.map((m) {
        final isSelf = m.userId == myId;
        final canRemove = isAdmin && !isSelf && !m.isCreator && (isCreator || !m.isAdmin);
        return _MemberTile(
          member: m, isSelf: isSelf,
          canRemove: canRemove, canToggleAdmin: false,
          onRemove: canRemove ? () => _confirmRemove(c, m) : null,
          c: c,
        );
      }),
    ];

    return RefreshIndicator(
      onRefresh: () => ref.read(roomMembersProvider(widget.roomId).notifier).load(),
      color: SeeUColors.accent,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        children: items,
      ),
    );
  }

  Widget _buildError(SeeUThemeColors c, String error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIcons.warning(), size: 40, color: c.ink4),
          const SizedBox(height: 12),
          Text('Не удалось загрузить список', style: TextStyle(color: c.ink3)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => ref.read(roomMembersProvider(widget.roomId).notifier).load(),
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(SeeUThemeColors c, RoomMember member) {
    HapticFeedback.mediumImpact();
    showSeeUBottomSheet(
      context: context, // this.context — same as State.context
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Удалить участника?',
              style: SeeUTypography.title.copyWith(color: c.ink),
            ),
            const SizedBox(height: 6),
            Text(
              '${member.fullName} (@${member.username}) потеряет доступ к комнате.',
              style: SeeUTypography.body.copyWith(color: c.ink2),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                try {
                  await ref
                      .read(roomMembersProvider(widget.roomId).notifier)
                      .remove(member.userId);
                } catch (e) {
                  if (mounted) {
                    showSeeUSnackBar(context, friendlyError(e),
                        tone: SeeUTone.danger);
                  }
                }
              },
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: SeeUColors.error,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Удалить',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SeeUButton(
              label: 'Отмена',
              variant: SeeUButtonVariant.secondary,
              onTap: () => Navigator.of(sheetCtx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmToggleAdmin(SeeUThemeColors c, RoomMember member) {
    HapticFeedback.mediumImpact();
    final grant = !member.isAdmin;
    showSeeUBottomSheet(
      context: context,
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              grant ? 'Назначить администратором?' : 'Снять с администратора?',
              style: SeeUTypography.title.copyWith(color: c.ink),
            ),
            const SizedBox(height: 6),
            Text(
              grant
                  ? '${member.fullName} станет администратором и сможет приглашать участников. Вы потеряете роль администратора (если вы не создатель).'
                  : '${member.fullName} потеряет права администратора.',
              style: SeeUTypography.body.copyWith(color: c.ink2),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                try {
                  await ref
                      .read(roomMembersProvider(widget.roomId).notifier)
                      .setAdmin(member.userId, grant: grant);
                } catch (e) {
                  if (mounted) {
                    showSeeUSnackBar(context, friendlyError(e),
                        tone: SeeUTone.danger);
                  }
                }
              },
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: grant ? SeeUColors.accent : c.surface2,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  grant ? 'Назначить' : 'Снять',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: grant ? Colors.white : c.ink,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SeeUButton(
              label: 'Отмена',
              variant: SeeUButtonVariant.secondary,
              onTap: () => Navigator.of(sheetCtx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  void _showRoomCode() {
    final code = ref.read(roomDetailProvider(widget.roomId)).room?.code ?? '';
    HapticFeedback.selectionClick();
    showSeeUBottomSheet(
      context: context,
      builder: (ctx) {
        final c = ctx.seeuColors;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIcons.key(PhosphorIconsStyle.fill),
                    size: 30, color: SeeUColors.accent),
                const SizedBox(height: 12),
                Text('Код комнаты',
                    style: SeeUTypography.subtitle
                        .copyWith(fontWeight: FontWeight.w700, color: c.ink)),
                const SizedBox(height: 6),
                Text(
                  'Дай этот код тем, кого хочешь позвать — они введут его в «Войти по коду».',
                  textAlign: TextAlign.center,
                  style: SeeUTypography.caption.copyWith(color: c.ink3),
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(SeeURadii.medium),
                    border: Border.all(color: c.line),
                  ),
                  child: Text(
                    code.isEmpty ? '——' : code,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                      color: c.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SeeUButton(
                  label: 'Скопировать код',
                  onTap: code.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: code));
                          Navigator.of(ctx).pop();
                          showSeeUSnackBar(context, 'Код скопирован',
                              tone: SeeUTone.success);
                        },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Member tile ──────────────────────────────────────────────────

class _MemberTile extends StatelessWidget {
  final RoomMember member;
  final bool isSelf;
  final bool canRemove;
  final bool canToggleAdmin;
  final VoidCallback? onRemove;
  final VoidCallback? onToggleAdmin;
  final SeeUThemeColors c;

  const _MemberTile({
    required this.member,
    required this.isSelf,
    required this.canRemove,
    this.canToggleAdmin = false,
    this.onRemove,
    this.onToggleAdmin,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final seed = (member.fullName.isNotEmpty
            ? member.fullName.codeUnitAt(0) + member.fullName.length
            : 0) %
        SeeUColors.avatarPalettes.length;
    final pal = SeeUColors.avatarPalettes[seed];
    final initial =
        member.fullName.isNotEmpty ? member.fullName[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        children: [
          // Avatar
          Stack(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: pal),
                  shape: BoxShape.circle,
                  border: isSelf
                      ? Border.all(color: SeeUColors.accent, width: 2)
                      : null,
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              // Mute dot
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: member.isMuted ? c.surface2 : SeeUColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.bg, width: 2),
                  ),
                  child: Icon(
                    member.isMuted
                        ? PhosphorIcons.microphoneSlash(PhosphorIconsStyle.fill)
                        : PhosphorIcons.microphone(PhosphorIconsStyle.fill),
                    size: 6,
                    color: member.isMuted ? c.ink3 : Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Name + username
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSelf ? '${member.fullName} (вы)' : member.fullName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '@${member.username}',
                  style: TextStyle(fontSize: 12, color: c.ink3),
                ),
              ],
            ),
          ),
          // Role pill — right-aligned
          if (member.isCreator)
            const SeeURoleBadge(label: 'Создатель', primary: true)
          else if (member.isAdmin)
            const SeeURoleBadge(label: 'Админ'),
          // Toggle admin button (creator only, non-self, non-creator target)
          if (canToggleAdmin)
            Tappable.scaled(
              onTap: onToggleAdmin,
              enableHaptic: false,
              child: Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  color: member.isAdmin
                      ? SeeUColors.accent.withValues(alpha: 0.12)
                      : c.surface2,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  member.isAdmin
                      ? PhosphorIcons.shieldSlash()
                      : PhosphorIcons.shieldStar(),
                  size: 16,
                  color: member.isAdmin ? SeeUColors.accent : c.ink3,
                ),
              ),
            ),
          // Remove button (admins for non-admins, creator for all)
          if (canRemove)
            Tappable.scaled(
              onTap: onRemove,
              enableHaptic: false,
              child: Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  color: SeeUColors.error.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  PhosphorIcons.userMinus(),
                  size: 16,
                  color: SeeUColors.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

}

// ─── Leave button ────────────────────────────────────────────────

class _LeaveButton extends ConsumerWidget {
  final String roomId;
  final String myId;

  const _LeaveButton({required this.roomId, required this.myId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        final confirmed = await showSeeUConfirm(
          context,
          title: 'Покинуть комнату?',
          message: 'Вы потеряете доступ. Создатель сможет пригласить вас снова.',
          confirmLabel: 'Покинуть',
          destructive: true,
          icon: PhosphorIcons.signOut(),
        );
        if (confirmed != true || !context.mounted) return;
        try {
          final api = ref.read(apiClientProvider);
          await api.delete(ApiEndpoints.leaveRoom(roomId));
          ref.read(roomListProvider.notifier).load();
          if (!context.mounted) return;
          final nav = Navigator.of(context);
          nav.pop(); // pop members screen
          nav.pop(); // pop room screen
        } catch (e) {
          if (!context.mounted) return;
          showSeeUSnackBar(context, friendlyError(e), tone: SeeUTone.danger);
        }
      },
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: SeeUColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SeeUColors.error.withValues(alpha: 0.25)),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.signOut(), size: 18, color: SeeUColors.error),
            const SizedBox(width: 8),
            const Text(
              'Покинуть комнату',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: SeeUColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
