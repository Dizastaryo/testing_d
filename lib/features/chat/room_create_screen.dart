import 'dart:async';
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
import '../../core/design/design.dart';
import '../../core/models/room.dart';
import '../../core/models/user.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/following_candidates_provider.dart';
import '../../core/providers/room_provider.dart';

/// Создание приватной голосовой+текстовой комнаты.
///
/// Флоу:
/// 1. Название (обязательно) + описание (необязательно).
/// 2. Выбор участников (опционально при создании — можно пригласить позже).
/// 3. POST /rooms → POST /rooms/:id/invite × N (параллельно) → /room/:id.
class RoomCreateScreen extends ConsumerStatefulWidget {
  const RoomCreateScreen({super.key});

  @override
  ConsumerState<RoomCreateScreen> createState() => _RoomCreateScreenState();
}

class _RoomCreateScreenState extends ConsumerState<RoomCreateScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  XFile? _coverImage;
  bool _isPublic = true;

  final Set<String> _selectedIds = {};
  final Map<String, User> _selectedUsers = {};

  List<User> _candidates = [];
  bool _loadingCandidates = true;
  String? _candidatesError;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ─── Candidate loading ──────────────────────────────────────────

  Future<void> _loadCandidates() async {
    setState(() {
      _loadingCandidates = true;
      _candidatesError = null;
    });
    try {
      final result = await ref.read(followingCandidatesProvider.future);
      if (mounted) setState(() => _candidates = result);
    } catch (e) {
      if (mounted) setState(() => _candidatesError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingCandidates = false);
    }
  }

  void _onSearch(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () async {
      final query = q.trim();
      if (query.isEmpty) {
        _loadCandidates();
        return;
      }
      if (!mounted) return;
      setState(() {
        _loadingCandidates = true;
        _candidatesError = null;
      });
      try {
        final api = ref.read(apiClientProvider);
        final r = await api.get(
          ApiEndpoints.search,
          queryParameters: {'q': query, 'type': 'users'},
        );
        final data = r.data is Map && (r.data as Map).containsKey('data')
            ? r.data['data']
            : r.data;
        List<User> users = const [];
        if (data is Map && data['users'] is List) {
          users = (data['users'] as List)
              .map((e) => User.fromJson(e as Map<String, dynamic>))
              .toList();
        } else if (data is List) {
          users = data.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
        }
        final me = ref.read(authProvider).user;
        if (me != null) users = users.where((u) => u.id != me.id).toList();
        if (mounted) setState(() => _candidates = users);
      } catch (e) {
        if (mounted) setState(() => _candidatesError = e.toString());
      } finally {
        if (mounted) setState(() => _loadingCandidates = false);
      }
    });
  }

  void _toggleUser(User u) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(u.id)) {
        _selectedIds.remove(u.id);
        _selectedUsers.remove(u.id);
      } else {
        _selectedIds.add(u.id);
        _selectedUsers[u.id] = u;
      }
    });
  }

  // ─── Create ─────────────────────────────────────────────────────

  bool get _canCreate => _nameCtrl.text.trim().isNotEmpty && !_creating;

  Future<void> _pickCoverImage() async {
    HapticFeedback.selectionClick();
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (file != null && mounted) setState(() => _coverImage = file);
  }

  Future<void> _create() async {
    if (!_canCreate) return;
    HapticFeedback.mediumImpact();
    setState(() => _creating = true);
    try {
      final api = ref.read(apiClientProvider);

      // Upload cover image if selected
      String coverUrl = '';
      if (_coverImage != null) {
        final formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(
            _coverImage!.path,
            filename: _coverImage!.name,
          ),
        });
        final up = await api.post(ApiEndpoints.mediaUpload, data: formData);
        final upData = up.data is Map ? up.data : {};
        coverUrl = (upData['data']?['url'] ?? upData['url'] ?? '') as String;
      }

      // 1. Create the room (all rooms are voice, invite-only).
      final resp = await api.post(ApiEndpoints.rooms, data: {
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        if (coverUrl.isNotEmpty) 'cover_url': coverUrl,
        'is_public': _isPublic,
      });
      final data = resp.data is Map && resp.data.containsKey('data')
          ? resp.data['data'] as Map<String, dynamic>
          : resp.data as Map<String, dynamic>;
      final room = Room.fromJson(data);
      ref.read(roomListProvider.notifier).addRoom(room);

      // 2. Invite selected members in parallel (best-effort — errors are silently ignored
      //    so the room is still created even if some invites fail).
      if (_selectedIds.isNotEmpty) {
        await Future.wait(
          _selectedIds.map((userId) async {
            try {
              await api.post(ApiEndpoints.roomInvite(room.id), data: {'user_id': userId});
            } catch (_) {}
          }),
        );
      }

      if (!mounted) return;
      context.replace('/room/${room.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать комнату: $e')),
      );
    }
  }

  // ─── UI ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(c),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
                children: [
                  _buildRoomInfoSection(c),
                  const SizedBox(height: 28),
                  _buildMembersSection(c),
                ],
              ),
            ),
            _buildBottomCta(c),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Icon(PhosphorIcons.caretLeft(PhosphorIconsStyle.bold), size: 22, color: c.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Новая комната', style: SeeUTypography.title.copyWith(color: c.ink)),
          ),
          AnimatedOpacity(
            opacity: _canCreate ? 1.0 : 0.45,
            duration: const Duration(milliseconds: 150),
            child: GestureDetector(
              onTap: _canCreate ? _create : null,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  borderRadius: BorderRadius.circular(SeeURadii.small),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Создать',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomInfoSection(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCoverPicker(c),
        const SizedBox(height: 20),
        _SectionLabel('НАЗВАНИЕ'),
        const SizedBox(height: 8),
        _InputField(
          controller: _nameCtrl,
          hintText: 'Например, «Flutter Казахстан»',
          maxLength: 40,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          c: c,
          showCounter: true,
        ),
        const SizedBox(height: 16),
        _SectionLabel('ОПИСАНИЕ'),
        const SizedBox(height: 8),
        _InputField(
          controller: _descCtrl,
          hintText: 'О чём эта комната?',
          maxLength: 500,
          maxLines: 3,
          fieldHeight: 52,
          c: c,
        ),
        const SizedBox(height: 16),
        // Info card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(SeeURadii.medium),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(PhosphorIconsRegular.info, size: 19, color: SeeUColors.accent),
              const SizedBox(width: 11),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 12.5, color: c.ink2, height: 1.5),
                    children: [
                      const TextSpan(text: 'Внутри сразу появятся '),
                      TextSpan(text: 'текстовый чат', style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
                      const TextSpan(text: ' и '),
                      TextSpan(text: 'голосовой канал', style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
                      const TextSpan(text: ' с демонстрацией экрана — настраивать ничего не нужно.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionLabel('КТО МОЖЕТ ВОЙТИ'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _PrivacyCard(
                icon: PhosphorIconsRegular.globe,
                title: 'Открытая',
                subtitle: 'Видна в поиске и по ссылке',
                selected: _isPublic,
                onTap: () => setState(() => _isPublic = true),
                c: c,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PrivacyCard(
                icon: PhosphorIconsRegular.lockSimple,
                title: 'Закрытая',
                subtitle: 'Только по приглашению',
                selected: !_isPublic,
                onTap: () => setState(() => _isPublic = false),
                c: c,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCoverPicker(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumb
            Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: _pickCoverImage,
                  child: Container(
                    width: 78, height: 78,
                    decoration: BoxDecoration(
                      gradient: _coverImage == null ? SeeUGradients.heroOrange : null,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: SeeUShadows.md,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _coverImage != null
                        ? Image.file(File(_coverImage!.path), fit: BoxFit.cover)
                        : Center(
                            child: Icon(
                              PhosphorIcons.usersThree(PhosphorIconsStyle.bold),
                              size: 27,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                          ),
                  ),
                ),
                Positioned(
                  right: -4, bottom: -4,
                  child: GestureDetector(
                    onTap: _coverImage != null
                        ? () => setState(() => _coverImage = null)
                        : _pickCoverImage,
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: SeeUColors.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.bg, width: 3),
                      ),
                      child: Icon(
                        _coverImage != null ? PhosphorIconsBold.x : PhosphorIconsRegular.camera,
                        size: 13, color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Обложка комнаты', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink)),
                  const SizedBox(height: 4),
                  Text('Загрузите фото или выберите тему', style: TextStyle(fontSize: 12, color: c.ink3, height: 1.45)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'ГАЛЕРЕЯ · ТЕМЫ',
          style: TextStyle(fontFamily: 'JetBrains Mono', fontSize: 10, letterSpacing: 1.0, color: c.ink3),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickCoverImage,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: SeeUColors.accent, width: 1.5),
                ),
                child: Icon(PhosphorIconsRegular.imageSquare, size: 21, color: SeeUColors.accent),
              ),
              Positioned(
                right: -4, bottom: -4,
                child: Container(
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    color: SeeUColors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.bg, width: 2),
                  ),
                  child: Icon(PhosphorIconsRegular.plus, size: 9, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMembersSection(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _SectionLabel('КОГО ПОЗВАТЬ'),
            if (_selectedIds.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${_selectedIds.length}',
                  style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Можно пригласить позже из комнаты',
          style: TextStyle(fontSize: 12, color: c.ink3),
        ),
        const SizedBox(height: 12),

        // Selected chips
        if (_selectedUsers.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _selectedUsers.values.map((u) => _SelectedChip(
              user: u,
              onRemove: () => _toggleUser(u),
            )).toList(),
          ),
          const SizedBox(height: 12),
        ],

        // Search
        _SearchField(
          controller: _searchCtrl,
          onChanged: _onSearch,
          c: c,
        ),
        const SizedBox(height: 8),

        // Candidate list (non-scrollable — inside outer ListView)
        _buildCandidateList(c),
      ],
    );
  }

  Widget _buildCandidateList(SeeUThemeColors c) {
    if (_loadingCandidates) {
      return const SeeUListSkeleton(count: 5);
    }
    if (_candidatesError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Column(
            children: [
              Text('Не удалось загрузить список', style: TextStyle(color: c.ink3)),
              const SizedBox(height: 8),
              TextButton(onPressed: _loadCandidates, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }
    if (_candidates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            _searchCtrl.text.isEmpty ? 'Начните вводить имя для поиска' : 'Никого не найдено',
            style: TextStyle(fontSize: 13, color: c.ink3),
          ),
        ),
      );
    }
    return Column(
      children: _candidates.map((u) {
        final selected = _selectedIds.contains(u.id);
        return _UserTile(
          user: u,
          selected: selected,
          onTap: () => _toggleUser(u),
          c: c,
        );
      }).toList(),
    );
  }
}

// ─── Shared sub-widgets ───────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'JetBrains Mono',
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
        color: c.ink3,
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final int maxLength;
  final int maxLines;
  final bool autofocus;
  final bool showCounter;
  final double? fieldHeight;
  final ValueChanged<String>? onChanged;
  final SeeUThemeColors c;

  const _InputField({
    required this.controller,
    required this.hintText,
    required this.maxLength,
    this.maxLines = 1,
    this.autofocus = false,
    this.showCounter = false,
    this.fieldHeight,
    this.onChanged,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: fieldHeight,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              maxLength: maxLength,
              maxLines: maxLines,
              style: TextStyle(fontSize: 15, color: c.ink),
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(fontSize: 15, color: c.ink3),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                counterText: '',
              ),
            ),
          ),
          if (showCounter)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '${controller.text.length}/$maxLength',
                style: TextStyle(fontSize: 12, color: c.ink3),
              ),
            ),
        ],
      ),
    );
  }
}

// Bottom CTA is part of _RoomCreateScreenState
extension _RoomCreateBottomCta on _RoomCreateScreenState {
  Widget _buildBottomCta(SeeUThemeColors c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line, width: 0.5)),
      ),
      child: GestureDetector(
        onTap: _canCreate ? _create : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 52,
          decoration: BoxDecoration(
            gradient: _canCreate ? SeeUGradients.heroOrange : null,
            color: _canCreate ? null : c.surface2,
            borderRadius: BorderRadius.circular(SeeURadii.small),
            boxShadow: _canCreate
                ? [BoxShadow(color: SeeUColors.accent.withValues(alpha: 0.32), offset: const Offset(0, 6), blurRadius: 18)]
                : null,
          ),
          alignment: Alignment.center,
          child: _creating
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIcons.usersThree(PhosphorIconsStyle.regular), size: 20, color: _canCreate ? Colors.white : c.ink3),
                    const SizedBox(width: 8),
                    Text(
                      'Создать комнату',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _canCreate ? Colors.white : c.ink3),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final SeeUThemeColors c;

  const _PrivacyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? SeeUColors.accentSoft : c.surface,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          border: Border.all(
            color: selected ? SeeUColors.accent : c.line,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: selected ? SeeUColors.accent : c.ink2),
            const SizedBox(height: 6),
            Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 11, color: c.ink3, height: 1.35)),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final SeeUThemeColors c;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 14, color: c.ink),
        decoration: InputDecoration(
          hintText: 'Поиск пользователей',
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
    );
  }
}

class _SelectedChip extends StatelessWidget {
  final User user;
  final VoidCallback onRemove;

  const _SelectedChip({required this.user, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: SeeUColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: SeeUColors.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '@${user.username}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: SeeUColors.accent,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(PhosphorIcons.x(), size: 12, color: SeeUColors.accent),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final User user;
  final bool selected;
  final VoidCallback onTap;
  final SeeUThemeColors c;

  const _UserTile({
    required this.user,
    required this.selected,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: c.surface2,
        backgroundImage:
            (user.avatarUrl?.isNotEmpty ?? false) ? CachedNetworkImageProvider(user.avatarUrl!) : null,
        child: (user.avatarUrl?.isEmpty ?? true)
            ? Icon(PhosphorIcons.user(), color: c.ink3, size: 18)
            : null,
      ),
      title: Text(user.fullName, style: SeeUTypography.subtitle),
      subtitle: Text(
        '@${user.username}',
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
              : Border.all(color: c.ink3.withValues(alpha: 0.5), width: 1.5),
        ),
        child: selected
            ? const Icon(PhosphorIconsBold.check, color: Colors.white, size: 14)
            : null,
      ),
      onTap: onTap,
    );
  }
}
