import 'dart:async';

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

/// Создание group-чата. Multi-select picker (минимум 1 кроме creator'а),
/// поле title, опциональный quick-выбор cover'а из набора. После create
/// → push на /chat/{id}.
class ChatCreateGroupScreen extends ConsumerStatefulWidget {
  const ChatCreateGroupScreen({super.key});

  @override
  ConsumerState<ChatCreateGroupScreen> createState() =>
      _ChatCreateGroupScreenState();
}

class _ChatCreateGroupScreenState
    extends ConsumerState<ChatCreateGroupScreen> {
  final _titleCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  // Карточки для выбора cover'а — переиспользуем seed highlights.
  // На первом релизе достаточно 5 пресетов. Real-upload — отдельная задача.
  static const _coverPresets = [
    '/uploads/seed/highlights/h1.jpg',
    '/uploads/seed/highlights/h2.jpg',
    '/uploads/seed/highlights/h3.jpg',
    '/uploads/seed/highlights/h4.jpg',
    '/uploads/seed/highlights/h5.jpg',
  ];

  String? _coverUrl;
  final Set<String> _selectedIds = {};
  final Map<String, User> _selectedUsers = {};

  List<User> _candidates = [];
  bool _loading = true;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
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
              .where((u) => u.id != me.id)
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

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final query = q.trim();
      if (query.isEmpty) {
        _loadFollowing();
        return;
      }
      if (!mounted) return;
      setState(() {
        _loading = true;
        _error = null;
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
          users = data
              .map((e) => User.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        final me = ref.read(authProvider).user;
        if (me != null) users = users.where((u) => u.id != me.id).toList();
        if (mounted) {
          setState(() {
            _candidates = users;
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

  bool get _canSubmit =>
      _titleCtrl.text.trim().isNotEmpty && _selectedIds.isNotEmpty && !_submitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    HapticFeedback.mediumImpact();
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.post(
        ApiEndpoints.chats,
        data: {
          'kind': 'group',
          'title': _titleCtrl.text.trim(),
          'cover_url': _coverUrl ?? '',
          'member_ids': _selectedIds.toList(),
        },
      );
      final data = r.data is Map && (r.data as Map).containsKey('data')
          ? r.data['data']
          : r.data;
      final id = data is Map ? data['id']?.toString() : null;
      if (id == null || id.isEmpty) {
        throw Exception('сервер не вернул id чата');
      }
      if (!mounted) return;
      // Чат-лист не invalidatи'тся автоматически — refresh'нём вручную после
      // навигации (chat_screen и так загрузит messages).
      context.go('/chat/$id');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать группу: $e')),
      );
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
        title: const Text('Новая группа'),
        actions: [
          TextButton(
            onPressed: _canSubmit ? _submit : null,
            child: Text(
              _submitting ? '…' : 'Создать',
              style: TextStyle(
                color: _canSubmit ? SeeUColors.accent : c.ink3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Title input
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: TextField(
                controller: _titleCtrl,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Название группы',
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
            ),
            // Cover presets row
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _coverPresets.length + 1, // +1 = «без обложки»
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  if (i == 0) {
                    final isSelected = _coverUrl == null;
                    return _CoverChoice(
                      isSelected: isSelected,
                      onTap: () => setState(() => _coverUrl = null),
                      child: Icon(
                        PhosphorIcons.usersThree(PhosphorIconsStyle.bold),
                        color: Colors.white,
                        size: 28,
                      ),
                      gradient: SeeUGradients.heroOrange,
                    );
                  }
                  final url = _coverPresets[i - 1];
                  final isSelected = _coverUrl == url;
                  return _CoverChoice(
                    isSelected: isSelected,
                    onTap: () => setState(() => _coverUrl = url),
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      width: 64,
                      height: 64,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // Selected chips
            if (_selectedUsers.isNotEmpty)
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _selectedUsers.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final u = _selectedUsers.values.elementAt(i);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: SeeUColors.accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: SeeUColors.accent.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '@${u.username}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: SeeUColors.accent,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => _toggleUser(u),
                            child: Icon(PhosphorIcons.x(),
                                size: 12, color: SeeUColors.accent),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            if (_selectedUsers.isNotEmpty) const SizedBox(height: 8),
            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: 'Поиск пользователей',
                  prefixIcon: Icon(PhosphorIcons.magnifyingGlass(),
                      size: 18, color: c.ink3),
                  filled: true,
                  fillColor: c.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
                style: SeeUTypography.body,
              ),
            ),
            // Candidates list
            Expanded(
              child: _loading
                  ? const SeeUListSkeleton()
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('Ошибка: $_error',
                                style: TextStyle(color: c.ink2)),
                          ),
                        )
                      : _candidates.isEmpty
                          ? const Center(
                              child: Text('Никого не найдено'),
                            )
                          : ListView.builder(
                              itemCount: _candidates.length,
                              itemBuilder: (_, i) {
                                final u = _candidates[i];
                                final selected = _selectedIds.contains(u.id);
                                return ListTile(
                                  leading: CircleAvatar(
                                    radius: 22,
                                    backgroundColor: c.surface2,
                                    backgroundImage:
                                        (u.avatarUrl?.isNotEmpty ?? false)
                                            ? NetworkImage(u.avatarUrl!)
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
                                  trailing: AnimatedContainer(
                                    duration: SeeUMotion.quick,
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: selected
                                          ? SeeUGradients.heroOrange
                                          : null,
                                      border: selected
                                          ? null
                                          : Border.all(
                                              color: c.ink3
                                                  .withValues(alpha: 0.5),
                                              width: 1.5,
                                            ),
                                    ),
                                    child: selected
                                        ? const Icon(Icons.check,
                                            color: Colors.white, size: 16)
                                        : null,
                                  ),
                                  onTap: () => _toggleUser(u),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

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
        width: 64,
        height: 64,
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
