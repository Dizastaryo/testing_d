import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

  Future<void> _create() async {
    if (!_canCreate) return;
    HapticFeedback.mediumImpact();
    setState(() => _creating = true);
    try {
      final api = ref.read(apiClientProvider);

      // 1. Create the room (backend forces type=voice, is_public=false).
      final resp = await api.post(ApiEndpoints.rooms, data: {
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
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
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  _buildRoomInfoSection(c),
                  const SizedBox(height: 28),
                  _buildMembersSection(c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(PhosphorIcons.x(), size: 22, color: c.ink),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Новая комната', style: SeeUTypography.title.copyWith(color: c.ink)),
                Text(
                  'Приватная · Голос + текст',
                  style: TextStyle(fontSize: 11, color: c.ink3),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _canCreate ? _create : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: _canCreate ? SeeUColors.accent : c.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _creating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      'Создать',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _canCreate ? Colors.white : c.ink3,
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
        _SectionLabel('НАЗВАНИЕ'),
        const SizedBox(height: 8),
        _InputField(
          controller: _nameCtrl,
          hintText: 'Например: «Вечерний джем»',
          maxLength: 120,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          c: c,
        ),
        const SizedBox(height: 20),
        _SectionLabel('ОПИСАНИЕ'),
        const SizedBox(height: 8),
        _InputField(
          controller: _descCtrl,
          hintText: 'О чём эта комната...',
          maxLength: 500,
          maxLines: 3,
          c: c,
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
            _SectionLabel('УЧАСТНИКИ'),
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
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
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
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
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
  final ValueChanged<String>? onChanged;
  final SeeUThemeColors c;

  const _InputField({
    required this.controller,
    required this.hintText,
    required this.maxLength,
    this.maxLines = 1,
    this.autofocus = false,
    this.onChanged,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
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
          contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          counterText: '',
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
            (user.avatarUrl?.isNotEmpty ?? false) ? NetworkImage(user.avatarUrl!) : null,
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
