import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/user.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/chat_provider.dart';
import '../../core/providers/realtime_provider.dart';

/// Список участников group-чата.
///
/// Возможности:
/// - Любой participant видит список + роли.
/// - Admin видит «✕» рядом с не-собой → kick.
/// - Любой participant (включая admin'а) видит «Покинуть группу» внизу.
/// - Admin может тапнуть «Добавить участников» → user-picker и POST на /members.
class ChatMembersScreen extends ConsumerStatefulWidget {
  final String chatId;
  const ChatMembersScreen({super.key, required this.chatId});

  @override
  ConsumerState<ChatMembersScreen> createState() => _ChatMembersScreenState();
}

class _ChatMembersScreenState extends ConsumerState<ChatMembersScreen> {
  bool _loading = true;
  String? _error;
  List<_Participant> _members = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.get(ApiEndpoints.chatMembers(widget.chatId));
      final data = r.data is Map && (r.data as Map).containsKey('data')
          ? r.data['data']
          : r.data;
      final list = data is List
          ? data
              .map((e) => _Participant.fromJson(e as Map<String, dynamic>))
              .toList()
          : <_Participant>[];
      if (mounted) {
        setState(() {
          _members = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _removeMember(_Participant p, {bool selfLeave = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    HapticFeedback.mediumImpact();
    try {
      final api = ref.read(apiClientProvider);
      await api.delete(
          ApiEndpoints.chatMember(widget.chatId, p.user.id));
      if (selfLeave) {
        // Покинул сам → перейти в chat-list, обновить.
        ref.read(chatListProvider.notifier).load();
        if (!mounted) return;
        context.go('/chat');
        messenger.showSnackBar(
            const SnackBar(content: Text('Вы вышли из группы')));
      } else {
        // Admin удалил кого-то → обновить локальный список.
        if (!mounted) return;
        setState(() {
          _members = _members.where((m) => m.user.id != p.user.id).toList();
        });
        messenger.showSnackBar(
          SnackBar(content: Text('@${p.user.username} удалён из группы')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось: $e')),
      );
    }
  }

  Future<void> _addMember() async {
    final picked = await Navigator.of(context).push<User?>(
      MaterialPageRoute(
        builder: (_) => _PickUserToAddScreen(
          chatId: widget.chatId,
          existingIds: _members.map((m) => m.user.id).toSet(),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      await api.post(
        ApiEndpoints.chatMembers(widget.chatId),
        data: {'user_id': picked.id},
      );
      messenger.showSnackBar(
        SnackBar(content: Text('@${picked.username} добавлен')),
      );
      _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось добавить: $e')),
      );
    }
  }

  Future<void> _confirmLeave() async {
    final me = ref.read(authProvider).user;
    if (me == null) return;
    final myMembership = _members.where((m) => m.user.id == me.id);
    if (myMembership.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Покинуть группу?'),
        content: const Text(
            'Вы перестанете получать сообщения и обновления этой группы.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SeeUColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Покинуть'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _removeMember(myMembership.first, selfLeave: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final me = ref.watch(authProvider).user;
    final myId = me?.id;
    final myMember = _members.where((m) => m.user.id == myId);
    final isMeAdmin = myMember.isNotEmpty && myMember.first.role == 'admin';

    // Live update: при WS-event'ах об изменении состава этой группы — refetch.
    // Не запускаем _load() напрямую из listener'а (анти-паттерн setState в build):
    // ставим флаг и микро-таск обновляет.
    ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (prev, next) {
      next.whenData((evt) {
        const interesting = {
          'chat.group.member.added',
          'chat.group.member.removed',
          'chat.group.member.role.changed',
        };
        if (!interesting.contains(evt.type)) return;
        if (evt.payload is! Map) return;
        final p = (evt.payload as Map).cast<String, dynamic>();
        final chatId = p['chat_id']?.toString() ?? '';
        if (chatId != widget.chatId) return;
        // Reload пост-frame, чтобы не пересекаться с текущим build pass'ом.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      });
    });

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Участники · ${_members.length}'),
      ),
      body: _loading
          ? const SeeUListSkeleton()
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Ошибка: $_error',
                        style: TextStyle(color: c.ink2)),
                  ),
                )
              : ListView(
                  children: [
                    if (isMeAdmin)
                      ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: SeeUColors.accent.withValues(alpha: 0.10),
                            border: Border.all(
                              color: SeeUColors.accent
                                  .withValues(alpha: 0.30),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.add,
                            color: SeeUColors.accent,
                          ),
                        ),
                        title: Text('Добавить участника',
                            style: SeeUTypography.subtitle.copyWith(
                              color: SeeUColors.accent,
                              fontWeight: FontWeight.w600,
                            )),
                        onTap: _addMember,
                      ),
                    ..._members.map((p) {
                      final isSelf = p.user.id == myId;
                      final canKick = isMeAdmin && !isSelf;
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundColor: c.surface2,
                          backgroundImage:
                              (p.user.avatarUrl?.isNotEmpty ?? false)
                                  ? NetworkImage(p.user.avatarUrl!)
                                  : null,
                          child: (p.user.avatarUrl?.isEmpty ?? true)
                              ? Icon(PhosphorIcons.user(),
                                  color: c.ink3, size: 18)
                              : null,
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                isSelf ? 'Вы' : p.user.fullName,
                                style: SeeUTypography.subtitle,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (p.role == 'admin') ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  gradient: SeeUGradients.heroOrange,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: const Text(
                                  'admin',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text('@${p.user.username}',
                            style: SeeUTypography.caption
                                .copyWith(color: c.ink3)),
                        trailing: canKick
                            ? IconButton(
                                onPressed: () => _showMemberMenu(p),
                                icon: Icon(
                                    PhosphorIcons.dotsThreeVertical(),
                                    color: c.ink3,
                                    size: 18),
                                tooltip: 'Действия',
                              )
                            : null,
                      );
                    }),
                    const Divider(height: 32),
                    ListTile(
                      leading: Icon(PhosphorIcons.signOut(),
                          color: SeeUColors.error),
                      title: Text(
                        'Покинуть группу',
                        style: SeeUTypography.subtitle.copyWith(
                          color: SeeUColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: _confirmLeave,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }

  Future<void> _confirmKick(_Participant p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить @${p.user.username}?'),
        content: const Text('Этот юзер потеряет доступ к группе.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SeeUColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) _removeMember(p);
  }

  Future<void> _changeRole(_Participant p, String newRole) async {
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      await api.put(
        ApiEndpoints.chatMemberRole(widget.chatId, p.user.id),
        data: {'role': newRole},
      );
      // Optimistic local update.
      if (mounted) {
        setState(() {
          _members = _members
              .map((m) => m.user.id == p.user.id
                  ? _Participant(
                      user: m.user,
                      role: newRole,
                      joinedAt: m.joinedAt,
                    )
                  : m)
              .toList();
        });
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(newRole == 'admin'
              ? '@${p.user.username} теперь админ'
              : '@${p.user.username} больше не админ'),
        ),
      );
    } catch (e) {
      // Backend возвращает 409 на last-admin demote — показываем понятное сообщение.
      String msg = 'Не удалось изменить роль';
      final estr = e.toString();
      if (estr.contains('409') || estr.contains('единственного')) {
        msg = 'Нельзя снять админа с единственного администратора группы';
      }
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _showMemberMenu(_Participant p) {
    final isAdmin = p.role == 'admin';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final c = sheetCtx.seeuColors;
        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(SeeURadii.sheet)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.ink3.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Icon(
                    isAdmin
                        ? PhosphorIcons.userMinus()
                        : PhosphorIcons.userPlus(),
                    color: SeeUColors.accent,
                  ),
                  title: Text(
                    isAdmin ? 'Снять админа' : 'Сделать админом',
                    style: SeeUTypography.subtitle,
                  ),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _changeRole(p, isAdmin ? 'member' : 'admin');
                  },
                ),
                ListTile(
                  leading: Icon(PhosphorIcons.x(), color: SeeUColors.error),
                  title: Text(
                    'Удалить из группы',
                    style: SeeUTypography.subtitle
                        .copyWith(color: SeeUColors.error),
                  ),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _confirmKick(p);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Локальная модель участника. Не выносим в models/, потому что используется
/// только в этом экране — добавлять в общий граф пока избыточно.
class _Participant {
  final User user;
  final String role;
  final DateTime? joinedAt;

  const _Participant({
    required this.user,
    required this.role,
    this.joinedAt,
  });

  factory _Participant.fromJson(Map<String, dynamic> j) {
    return _Participant(
      user: User.fromJson(j['user'] as Map<String, dynamic>),
      role: (j['role'] as String?) ?? 'member',
      joinedAt: j['joined_at'] != null
          ? DateTime.tryParse(j['joined_at'].toString())
          : null,
    );
  }
}

// ===========================================================================
// Picker для добавления нового члена в существующую группу.
// Вынесен сюда же — узкая и одноразовая фича, отдельный файл избыточен.
// ===========================================================================

class _PickUserToAddScreen extends ConsumerStatefulWidget {
  final String chatId;
  final Set<String> existingIds;

  const _PickUserToAddScreen({
    required this.chatId,
    required this.existingIds,
  });

  @override
  ConsumerState<_PickUserToAddScreen> createState() =>
      _PickUserToAddScreenState();
}

class _PickUserToAddScreenState extends ConsumerState<_PickUserToAddScreen> {
  bool _loading = true;
  String? _error;
  List<User> _candidates = [];

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  Future<void> _loadFollowing() async {
    final me = ref.read(authProvider).user;
    if (me == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.get(ApiEndpoints.userFollowing(me.username),
          queryParameters: {'limit': 100});
      final data = r.data is Map && (r.data as Map).containsKey('data')
          ? r.data['data']
          : r.data;
      final list = data is List
          ? data
              .map((e) => User.fromJson(e as Map<String, dynamic>))
              .where((u) =>
                  u.id != me.id && !widget.existingIds.contains(u.id))
              .toList()
          : <User>[];
      if (mounted) {
        setState(() {
          _candidates = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Кого добавить'),
      ),
      body: _loading
          ? const SeeUListSkeleton()
          : _error != null
              ? Center(child: Text('Ошибка: $_error'))
              : _candidates.isEmpty
                  ? const Center(child: Text('Все ваши подписки уже в группе'))
                  : ListView.builder(
                      itemCount: _candidates.length,
                      itemBuilder: (_, i) {
                        final u = _candidates[i];
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor: c.surface2,
                            backgroundImage:
                                (u.avatarUrl?.isNotEmpty ?? false)
                                    ? CachedNetworkImageProvider(
                                        u.avatarUrl!)
                                    : null,
                            child: (u.avatarUrl?.isEmpty ?? true)
                                ? Icon(PhosphorIcons.user(),
                                    color: c.ink3, size: 18)
                                : null,
                          ),
                          title: Text(u.fullName,
                              style: SeeUTypography.subtitle),
                          subtitle: Text('@${u.username}',
                              style: SeeUTypography.caption
                                  .copyWith(color: c.ink3)),
                          trailing: const Icon(Icons.add,
                              color: SeeUColors.accent),
                          onTap: () {
                            Navigator.of(context).pop(u);
                          },
                        );
                      },
                    ),
    );
  }
}
