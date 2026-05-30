import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/room.dart';
import '../../core/models/user.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/following_candidates_provider.dart';
import '../../core/providers/room_provider.dart';

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
  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final membersState = ref.watch(roomMembersProvider(widget.roomId));
    final myId = ref.watch(authProvider).user?.id ?? '';
    final isCreator = myId == widget.creatorId;
    final myMember = membersState.members.where((m) => m.userId == myId).firstOrNull;
    final isAdmin = isCreator || (myMember?.isAdmin ?? false);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Участники · ${membersState.members.length}',
                          style: SeeUTypography.title.copyWith(color: c.ink),
                        ),
                        Text(
                          'Приватная комната',
                          style: TextStyle(fontSize: 11, color: c.ink3),
                        ),
                      ],
                    ),
                  ),
                  if (isAdmin)
                    GestureDetector(
                      onTap: () => _showInvitePicker(c),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: SeeUColors.accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(PhosphorIcons.userPlus(), size: 14, color: Colors.white),
                            const SizedBox(width: 5),
                            const Text(
                              'Добавить',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Content
            Expanded(
              child: membersState.isLoading && membersState.members.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : membersState.error != null && membersState.members.isEmpty
                      ? _buildError(c, membersState.error!)
                      : _buildList(c, membersState.members, myId, isCreator, isAdmin),
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
    );
  }

  Widget _buildList(
    SeeUThemeColors c,
    List<RoomMember> members,
    String myId,
    bool isCreator,
    bool isAdmin,
  ) {
    return RefreshIndicator(
      onRefresh: () => ref.read(roomMembersProvider(widget.roomId).notifier).load(),
      color: SeeUColors.accent,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        itemCount: members.length,
        separatorBuilder: (_, __) => Divider(color: c.line, height: 1),
        itemBuilder: (_, i) {
          final m = members[i];
          final isSelf = m.userId == myId;
          // Can remove: admins can remove non-admins; creator can remove admins too
          final canRemove = isAdmin && !isSelf && !m.isCreator &&
              (isCreator || !m.isAdmin);
          // Only creator can toggle admin status on others
          final canToggleAdmin = isCreator && !isSelf && !m.isCreator;
          return _MemberTile(
            member: m,
            isSelf: isSelf,
            canRemove: canRemove,
            canToggleAdmin: canToggleAdmin,
            onRemove: canRemove ? () => _confirmRemove(c, m) : null,
            onToggleAdmin: canToggleAdmin
                ? () => _confirmToggleAdmin(c, m)
                : null,
            c: c,
          );
        },
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка: $e')),
                    );
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
                  ? '${member.fullName} сможет редактировать комнату и приглашать участников.'
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка: $e')),
                    );
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

  void _showInvitePicker(SeeUThemeColors c) {
    showModalBottomSheet(
      context: context, // this.context
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InvitePickerSheet(
        roomId: widget.roomId,
        existingIds: ref
            .read(roomMembersProvider(widget.roomId))
            .members
            .map((m) => m.userId)
            .toSet(),
      ),
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
      padding: const EdgeInsets.symmetric(vertical: 10),
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isSelf ? '${member.fullName} (вы)' : member.fullName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (member.isCreator) ...[
                      const SizedBox(width: 6),
                      _roleBadge('Создатель', SeeUColors.accent),
                    ] else if (member.isAdmin) ...[
                      const SizedBox(width: 6),
                      _roleBadge('Админ', const Color(0xFF6C63FF)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '@${member.username}',
                  style: TextStyle(fontSize: 12, color: c.ink3),
                ),
              ],
            ),
          ),
          // Toggle admin button (creator only, non-self, non-creator target)
          if (canToggleAdmin)
            GestureDetector(
              onTap: onToggleAdmin,
              child: Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  color: member.isAdmin
                      ? const Color(0xFF6C63FF).withValues(alpha: 0.12)
                      : c.surface2,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  member.isAdmin
                      ? PhosphorIcons.shieldSlash()
                      : PhosphorIcons.shieldStar(),
                  size: 16,
                  color: member.isAdmin ? const Color(0xFF6C63FF) : c.ink3,
                ),
              ),
            ),
          // Remove button (admins for non-admins, creator for all)
          if (canRemove)
            GestureDetector(
              onTap: onRemove,
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

  Widget _roleBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
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
    final c = context.seeuColors;
    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: c.surface,
            title: Text('Покинуть комнату?', style: TextStyle(color: c.ink, fontSize: 17)),
            content: Text(
              'Вы потеряете доступ. Создатель сможет пригласить вас снова.',
              style: TextStyle(color: c.ink2, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Отмена', style: TextStyle(color: c.ink3)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Покинуть', style: TextStyle(color: SeeUColors.error)),
              ),
            ],
          ),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e')),
          );
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

// ─── Invite picker sheet ──────────────────────────────────────────

class _InvitePickerSheet extends ConsumerStatefulWidget {
  final String roomId;
  final Set<String> existingIds;

  const _InvitePickerSheet({
    required this.roomId,
    required this.existingIds,
  });

  @override
  ConsumerState<_InvitePickerSheet> createState() => _InvitePickerSheetState();
}

class _InvitePickerSheetState extends ConsumerState<_InvitePickerSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<User> _candidates = [];
  bool _loading = true;
  final Set<String> _pendingIds = {};
  bool _inviting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load([String? q]) async {
    setState(() {
      _loading = true;
    });
    try {
      List<User> users;
      if (q == null || q.isEmpty) {
        users = await ref.read(followingCandidatesProvider.future);
      } else {
        final api = ref.read(apiClientProvider);
        final r = await api.get(
          ApiEndpoints.search,
          queryParameters: {'q': q, 'type': 'users'},
        );
        final data = r.data is Map && (r.data as Map).containsKey('data')
            ? r.data['data']
            : r.data;
        if (data is Map && data['users'] is List) {
          users = (data['users'] as List)
              .map((e) => User.fromJson(e as Map<String, dynamic>))
              .toList();
        } else if (data is List) {
          users = data.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
        } else {
          users = [];
        }
      }
      final me = ref.read(authProvider).user;
      if (me != null) users = users.where((u) => u.id != me.id).toList();
      // Exclude current members
      users = users.where((u) => !widget.existingIds.contains(u.id)).toList();
      if (mounted) setState(() => _candidates = users);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () => _load(q.trim()));
  }

  Future<void> _invite() async {
    if (_pendingIds.isEmpty || _inviting) return;
    setState(() => _inviting = true);
    HapticFeedback.mediumImpact();
    try {
      await Future.wait(
        _pendingIds.map(
          (userId) => ref
              .read(roomMembersProvider(widget.roomId).notifier)
              .invite(userId)
              .catchError((_) {}),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      height: screenH * 0.75,
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: c.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Добавить участников', style: SeeUTypography.title.copyWith(color: c.ink)),
                      if (_pendingIds.isNotEmpty)
                        Text(
                          'Выбрано: ${_pendingIds.length}',
                          style: TextStyle(fontSize: 12, color: SeeUColors.accent),
                        ),
                    ],
                  ),
                ),
                if (_pendingIds.isNotEmpty)
                  GestureDetector(
                    onTap: _invite,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: SeeUColors.accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _inviting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Пригласить',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearch,
                style: TextStyle(fontSize: 14, color: c.ink),
                decoration: InputDecoration(
                  hintText: 'Поиск',
                  hintStyle: TextStyle(fontSize: 14, color: c.ink3),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    child: Icon(PhosphorIcons.magnifyingGlass(), size: 16, color: c.ink3),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 40),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _candidates.isEmpty
                    ? Center(
                        child: Text(
                          'Никого не найдено',
                          style: TextStyle(color: c.ink3, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _candidates.length,
                        itemBuilder: (_, i) {
                          final u = _candidates[i];
                          final selected = _pendingIds.contains(u.id);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 22,
                              backgroundColor: c.surface2,
                              backgroundImage: (u.avatarUrl?.isNotEmpty ?? false)
                                  ? NetworkImage(u.avatarUrl!)
                                  : null,
                              child: (u.avatarUrl?.isEmpty ?? true)
                                  ? Icon(PhosphorIcons.user(), color: c.ink3, size: 18)
                                  : null,
                            ),
                            title: Text(u.fullName, style: SeeUTypography.subtitle),
                            subtitle: Text(
                              '@${u.username}',
                              style: SeeUTypography.caption.copyWith(color: c.ink3),
                            ),
                            trailing: AnimatedContainer(
                              duration: SeeUMotion.quick,
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: selected ? SeeUGradients.heroOrange : null,
                                border: selected
                                    ? null
                                    : Border.all(
                                        color: c.ink3.withValues(alpha: 0.5),
                                        width: 1.5,
                                      ),
                              ),
                              child: selected
                                  ? const Icon(PhosphorIconsBold.check,
                                      color: Colors.white, size: 14)
                                  : null,
                            ),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                if (selected) {
                                  _pendingIds.remove(u.id);
                                } else {
                                  _pendingIds.add(u.id);
                                }
                              });
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
