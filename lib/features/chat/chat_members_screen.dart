import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/config/app_config.dart';
import '../../core/design/design.dart';
import '../../core/utils/format.dart';
import '../../core/models/user.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/following_candidates_provider.dart';
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
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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
        ref.read(chatListProvider.notifier).load(silent: true);
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
        SnackBar(content: Text('Не удалось: ${friendlyError(e)}')),
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
        SnackBar(content: Text('Не удалось добавить: ${friendlyError(e)}')),
      );
    }
  }

  /// Cover-пресеты для «Изменить группу». Дублируют пресеты из
  /// chat_create_group_screen — выносить в shared-файл пока нет смысла,
  /// набор крошечный и контекст разный.
  static List<String> get _coverPresets => [
    '${AppConfig.r2PublicUrl}/uploads/seed/highlights/h1.jpg',
    '${AppConfig.r2PublicUrl}/uploads/seed/highlights/h2.jpg',
    '${AppConfig.r2PublicUrl}/uploads/seed/highlights/h3.jpg',
    '${AppConfig.r2PublicUrl}/uploads/seed/highlights/h4.jpg',
    '${AppConfig.r2PublicUrl}/uploads/seed/highlights/h5.jpg',
  ];

  Future<void> _showEditGroupSheet() async {
    final chats = ref.read(chatListProvider).chats;
    final chat = chats.where((c) => c.id == widget.chatId).cast<Chat?>().firstWhere(
          (_) => true,
          orElse: () => null,
        );
    if (chat == null) return;

    final titleCtrl = TextEditingController(text: chat.title);
    String? coverUrl = chat.coverUrl.isEmpty ? null : chat.coverUrl;
    XFile? pickedImage;
    bool submitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return SafeArea(
          child: StatefulBuilder(builder: (innerCtx, setSheetState) {
            final c = innerCtx.seeuColors;
            final initialTitle = chat.title;
            final initialCover =
                chat.coverUrl.isEmpty ? null : chat.coverUrl;
            final dirty = titleCtrl.text.trim() != initialTitle ||
                coverUrl != initialCover ||
                pickedImage != null;
            final canSave =
                dirty && titleCtrl.text.trim().isNotEmpty && !submitting;
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(innerCtx).viewInsets.bottom + 16,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(SeeURadii.sheet)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: c.ink3.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Изменить группу', style: SeeUTypography.title),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleCtrl,
                      onChanged: (_) => setSheetState(() {}),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Название группы',
                        hintStyle: SeeUTypography.subtitle.copyWith(color: c.ink3),
                        filled: true,
                        fillColor: c.surface2,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      style: SeeUTypography.subtitle,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'ОБЛОЖКА',
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        letterSpacing: 0.8, color: c.ink3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 70,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        // +1 default, +1 gallery picker, +presets
                        itemCount: _coverPresets.length + 2,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          if (i == 0) {
                            final isSelected = coverUrl == null && pickedImage == null;
                            return _CoverChoice(
                              isSelected: isSelected,
                              onTap: () => setSheetState(() {
                                coverUrl = null;
                                pickedImage = null;
                              }),
                              gradient: SeeUGradients.heroOrange,
                              child: Icon(
                                PhosphorIcons.usersThree(
                                    PhosphorIconsStyle.bold),
                                color: Colors.white,
                                size: 26,
                              ),
                            );
                          }
                          if (i == 1) {
                            // Gallery picker button
                            final isSelected = pickedImage != null;
                            return _CoverChoice(
                              isSelected: isSelected,
                              onTap: () async {
                                final img = await ImagePicker().pickImage(
                                  source: ImageSource.gallery,
                                  imageQuality: 80,
                                );
                                if (img != null) {
                                  setSheetState(() {
                                    pickedImage = img;
                                    coverUrl = null;
                                  });
                                }
                              },
                              gradient: const LinearGradient(
                                colors: [Color(0xFF444444), Color(0xFF222222)],
                              ),
                              child: isSelected
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(
                                        File(pickedImage!.path),
                                        fit: BoxFit.cover,
                                        width: 60,
                                        height: 60,
                                      ),
                                    )
                                  : Icon(
                                      PhosphorIcons.image(PhosphorIconsStyle.bold),
                                      color: Colors.white,
                                      size: 26,
                                    ),
                            );
                          }
                          final url = _coverPresets[i - 2];
                          final isSelected = coverUrl == url && pickedImage == null;
                          return _CoverChoice(
                            isSelected: isSelected,
                            onTap: () => setSheetState(() {
                              coverUrl = url;
                              pickedImage = null;
                            }),
                            child: CachedNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.cover,
                              width: 60,
                              height: 60,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: canSave
                          ? () async {
                              HapticFeedback.mediumImpact();
                              setSheetState(() => submitting = true);
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                final api = ref.read(apiClientProvider);
                                // Upload gallery image if selected
                                String finalCoverUrl = coverUrl ?? '';
                                if (pickedImage != null) {
                                  final formData = FormData.fromMap({
                                    'file': await MultipartFile.fromFile(
                                      pickedImage!.path,
                                      filename: pickedImage!.name,
                                    ),
                                  });
                                  final uploadRes = await api.post(
                                      ApiEndpoints.mediaUpload, data: formData);
                                  final d = uploadRes.data is Map
                                      ? uploadRes.data
                                      : {};
                                  finalCoverUrl = (d['data']?['url'] ??
                                          d['url'] ??
                                          '') as String;
                                }
                                await api.put(
                                  ApiEndpoints.chatGroup(widget.chatId),
                                  data: {
                                    'title': titleCtrl.text.trim(),
                                    'cover_url': finalCoverUrl,
                                  },
                                );
                                // Refresh chat-list чтобы tile сразу показал
                                // новый title/cover. Members-screen
                                // обновлять не нужно — он показывает
                                // participants, не meta.
                                if (mounted) {
                                  ref
                                      .read(chatListProvider.notifier)
                                      .load(silent: true);
                                }
                                if (innerCtx.mounted) {
                                  Navigator.of(innerCtx).pop();
                                }
                                messenger.showSnackBar(const SnackBar(
                                    content: Text('Группа обновлена')));
                              } catch (e) {
                                if (innerCtx.mounted) {
                                  setSheetState(() => submitting = false);
                                }
                                // 403 если бэк решил что caller не admin —
                                // тогда показываем понятное сообщение.
                                final estr = e.toString();
                                final msg = estr.contains('403')
                                    ? 'Только админы могут менять группу'
                                    : 'Не удалось сохранить: $e';
                                messenger.showSnackBar(
                                    SnackBar(content: Text(msg)));
                              }
                            }
                          : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: 52,
                        decoration: BoxDecoration(
                          gradient:
                              canSave ? SeeUGradients.heroOrange : null,
                          color: canSave
                              ? null
                              : SeeUColors.accent.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'Сохранить',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                ),
              ),
            );
          }),
        );
      },
    );

    titleCtrl.dispose();
  }

  Future<void> _confirmLeave() async {
    final me = ref.read(authProvider).user;
    if (me == null) return;
    final myMembership = _members.where((m) => m.user.id == me.id);
    if (myMembership.isEmpty) return;

    final chats = ref.read(chatListProvider).chats;
    final chat = chats
        .where((c) => c.id == widget.chatId)
        .cast<Chat?>()
        .firstWhere((_) => true, orElse: () => null);
    final isSbor = chat?.sborId != null;
    final isOrganizer = chat?.isOrganizer == true;

    final String title, content, confirmLabel, successMsg;
    if (isOrganizer) {
      title = 'Отменить сбор?';
      content = 'Сбор будет отменён для всех участников.';
      confirmLabel = 'Отменить сбор';
      successMsg = 'Сбор отменён';
    } else if (isSbor) {
      title = 'Выйти из сбора?';
      content = 'Ты покинешь сбор и его групповой чат.';
      confirmLabel = 'Выйти';
      successMsg = 'Вы вышли из сбора';
    } else {
      title = 'Покинуть группу?';
      content = 'Вы перестанете получать сообщения и обновления этой группы.';
      confirmLabel = 'Покинуть';
      successMsg = 'Вы вышли из группы';
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SeeUColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      if (isOrganizer && chat?.sborId != null) {
        await api.delete(ApiEndpoints.cancelSbor(chat!.sborId!));
      } else if (isSbor && chat?.sborId != null) {
        await api.delete(ApiEndpoints.leaveSbor(chat!.sborId!));
      } else {
        await api.delete(ApiEndpoints.chatMember(widget.chatId, me.id));
      }
      ref.read(chatListProvider.notifier).load(silent: true);
      if (!mounted) return;
      context.go('/chat');
      messenger.showSnackBar(SnackBar(content: Text(successMsg)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось: ${friendlyError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final me = ref.watch(authProvider).user;
    final myId = me?.id;
    final myMember = _members.where((m) => m.user.id == myId);
    final isMeAdmin = myMember.isNotEmpty && myMember.first.role == 'admin';

    final chats = ref.watch(chatListProvider).chats;
    final chat = chats
        .where((ch) => ch.id == widget.chatId)
        .cast<Chat?>()
        .firstWhere((_) => true, orElse: () => null);
    final isSbor = chat?.sborId != null;
    final isOrganizer = chat?.isOrganizer == true;
    final leaveLabel = isOrganizer
        ? 'Отменить сбор'
        : isSbor
            ? 'Выйти из сбора'
            : 'Покинуть группу';

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

    final q = _searchQuery.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _members
        : _members.where((m) =>
            m.user.fullName.toLowerCase().contains(q) ||
            m.user.username.toLowerCase().contains(q)).toList();

    final admins = filtered.where((m) => m.role == 'admin').toList();
    final regular = filtered.where((m) => m.role != 'admin').toList();

    Widget sectionHeader(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
      child: Text(label, style: TextStyle(
        fontFamily: 'JetBrains Mono', fontSize: 11,
        fontWeight: FontWeight.w600, letterSpacing: 0.5, color: c.ink3,
      )),
    );

    Widget memberRow(_Participant p) {
      final isSelf = p.user.id == myId;
      final canKick = isMeAdmin && !isSelf;
      return GestureDetector(
        onTap: () => context.push('/profile/${p.user.username}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: c.surface2,
                backgroundImage: (p.user.avatarUrl?.isNotEmpty ?? false)
                    ? CachedNetworkImageProvider(p.user.avatarUrl!) : null,
                child: (p.user.avatarUrl?.isEmpty ?? true)
                    ? Icon(PhosphorIcons.user(), color: c.ink3, size: 18) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(child: Text(
                        isSelf ? 'Вы' : p.user.fullName,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink),
                        overflow: TextOverflow.ellipsis,
                      )),
                    ]),
                    Text('@${p.user.username}', style: TextStyle(fontSize: 12, color: c.ink3)),
                  ],
                ),
              ),
              if (p.role == 'admin')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: SeeUColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                  ),
                  child: Text('Админ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SeeUColors.accent)),
                )
              else if (canKick)
                GestureDetector(
                  onTap: () => _showMemberMenu(p),
                  child: Icon(PhosphorIcons.dotsThreeVertical(), color: c.ink3, size: 18),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(PhosphorIcons.caretLeft(PhosphorIconsStyle.bold), size: 22, color: c.ink),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Участники', style: SeeUTypography.title.copyWith(fontSize: 17, color: c.ink)),
                        Text('${_members.length} человека', style: TextStyle(fontSize: 12, color: c.ink3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(SeeURadii.small),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: TextStyle(fontSize: 14, color: c.ink),
                  decoration: InputDecoration(
                    hintText: 'Поиск по имени',
                    hintStyle: TextStyle(fontSize: 14, color: c.ink3),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 12, right: 8),
                      child: Icon(PhosphorIconsRegular.magnifyingGlass, size: 16, color: c.ink3),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 40),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const SeeUListSkeleton()
                  : _error != null
                      ? Center(child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(friendlyError(_error!), style: TextStyle(color: c.ink2)),
                        ))
                      : ListView(
                          children: [
                    // Add member + edit group rows
                    if (isMeAdmin) ...[
                      GestureDetector(
                        onTap: _addMember,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          child: Row(children: [
                            Container(
                              width: 44, height: 44,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: SeeUColors.accentSoft),
                              child: Icon(PhosphorIcons.userPlus(), color: SeeUColors.accent, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Text('Добавить участников', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SeeUColors.accent)),
                          ]),
                        ),
                      ),
                      GestureDetector(
                        onTap: _showEditGroupSheet,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          child: Row(children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: c.surface2),
                              child: Icon(PhosphorIcons.pencilSimple(), color: c.ink2, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Text('Изменить группу', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink)),
                          ]),
                        ),
                      ),
                    ],
                    if (admins.isNotEmpty) sectionHeader('АДМИНИСТРАТОРЫ'),
                    ...admins.map(memberRow),
                    if (regular.isNotEmpty) sectionHeader('УЧАСТНИКИ'),
                    ...regular.map(memberRow),
                    const Divider(height: 32),
                    GestureDetector(
                      onTap: _confirmLeave,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        child: Row(children: [
                          Icon(PhosphorIcons.signOut(), color: SeeUColors.error, size: 20),
                          const SizedBox(width: 12),
                          Text(leaveLabel, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SeeUColors.error)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
            ),
          ],
        ),
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
                // Grabber
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: c.ink3.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Person header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: c.surface2,
                        backgroundImage: (p.user.avatarUrl?.isNotEmpty ?? false)
                            ? CachedNetworkImageProvider(p.user.avatarUrl!)
                            : null,
                        child: (p.user.avatarUrl?.isEmpty ?? true)
                            ? Icon(PhosphorIcons.user(), color: c.ink3, size: 18)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.user.fullName,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: c.ink,
                            ),
                          ),
                          Text(
                            isAdmin ? 'Администратор' : 'Участник',
                            style: TextStyle(fontSize: 12, color: c.ink3),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.line),
                // Admin toggle
                ListTile(
                  leading: Icon(
                    PhosphorIcons.crownSimple(),
                    color: SeeUColors.accent,
                  ),
                  title: Text(
                    isAdmin
                        ? 'Снять права администратора'
                        : 'Назначить администратором',
                    style: SeeUTypography.subtitle,
                  ),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _changeRole(p, isAdmin ? 'member' : 'admin');
                  },
                ),
                // Write message
                ListTile(
                  leading: Icon(PhosphorIcons.chatCircle(), color: c.ink),
                  title: Text('Написать сообщение', style: SeeUTypography.subtitle),
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    final chatId = await ref
                        .read(chatListProvider.notifier)
                        .getOrCreateChat(p.user.id);
                    if (!mounted || chatId == null) return;
                    context.push('/chat/$chatId');
                  },
                ),
                // Block
                ListTile(
                  leading: Icon(PhosphorIcons.prohibit(), color: c.ink),
                  title: Text('Заблокировать', style: SeeUTypography.subtitle),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Скоро')),
                    );
                  },
                ),
                Divider(height: 1, color: c.line),
                // Remove
                ListTile(
                  leading: Icon(PhosphorIcons.userMinus(), color: SeeUColors.error),
                  title: Text(
                    'Удалить из группы',
                    style: SeeUTypography.subtitle.copyWith(color: SeeUColors.error),
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

/// Маленькая обёртка для cover-preset в edit-sheet'е. Дублирует виджет из
/// chat_create_group_screen — выносить в shared-файл пока преждевременно.
class _CoverChoice extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final Widget child;
  final Gradient? gradient;

  const _CoverChoice({
    required this.isSelected,
    required this.onTap,
    required this.child,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: gradient,
          border: Border.all(
            color: isSelected ? SeeUColors.accent : Colors.transparent,
            width: 3,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

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
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    try {
      final result = await ref.read(followingCandidatesProvider.future);
      if (mounted) {
        setState(() {
          _candidates = result
              .where((u) => !widget.existingIds.contains(u.id))
              .toList();
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
                          trailing: Icon(PhosphorIcons.plus(),
                              color: SeeUColors.accent, size: 20),
                          onTap: () {
                            Navigator.of(context).pop(u);
                          },
                        );
                      },
                    ),
    );
  }
}
