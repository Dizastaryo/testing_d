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

/// Создание комнаты — двухшаговый флоу:
/// 1. Настройка (обложка, название, описание, приватность).
/// 2. Участники (опционально — можно создать без них).
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
  int _step = 0;
  late final PageController _pageController;

  final Set<String> _selectedIds = {};
  final Map<String, User> _selectedUsers = {};

  List<User> _candidates = [];
  bool _loadingCandidates = true;
  String? _candidatesError;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadCandidates();
    _nameCtrl.addListener(_onNameChanged);
  }

  void _onNameChanged() => setState(() {});

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.removeListener(_onNameChanged);
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _goToStep(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  // ─── Candidate loading ─────────────────────────────────────────────────────

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
          users = data
              .map((e) => User.fromJson(e as Map<String, dynamic>))
              .toList();
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

  // ─── Create ────────────────────────────────────────────────────────────────

  bool get _canProceed => _nameCtrl.text.trim().isNotEmpty;
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

      if (_selectedIds.isNotEmpty) {
        await Future.wait(
          _selectedIds.map((userId) async {
            try {
              await api.post(
                  ApiEndpoints.roomInvite(room.id), data: {'user_id': userId});
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
        SnackBar(content: Text('Не удалось создать: $e')),
      );
    }
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

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
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildInfoPage(c),
                  _buildMembersPage(c),
                ],
              ),
            ),
            _buildBottomBar(c),
          ],
        ),
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(SeeUThemeColors c) {
    final isStep2 = _step == 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 14, 6),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
      ),
      child: Row(
        children: [
          // Close / Back
          IconButton(
            onPressed: isStep2
                ? () => _goToStep(0)
                : () => Navigator.of(context).pop(),
            icon: Icon(
              isStep2
                  ? PhosphorIcons.caretLeft(PhosphorIconsStyle.bold)
                  : PhosphorIcons.x(PhosphorIconsStyle.bold),
              size: 20,
              color: c.ink,
            ),
          ),
          // Title + step dots
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isStep2 ? 'Участники' : 'Новая комната',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _StepDot(filled: true),
                    const SizedBox(width: 4),
                    _StepDot(filled: isStep2),
                    const SizedBox(width: 8),
                    Text(
                      isStep2 ? 'Шаг 2 из 2' : 'Шаг 1 из 2',
                      style: TextStyle(fontSize: 10, color: c.ink3),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Right action
          if (isStep2)
            AnimatedOpacity(
              opacity: _canCreate ? 1.0 : 0.45,
              duration: const Duration(milliseconds: 150),
              child: GestureDetector(
                onTap: _canCreate ? _create : null,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    gradient: _canCreate ? SeeUGradients.heroOrange : null,
                    color: _canCreate ? null : c.surface2,
                    borderRadius: BorderRadius.circular(SeeURadii.small),
                    boxShadow: _canCreate
                        ? [
                            BoxShadow(
                              color: SeeUColors.accent.withValues(alpha: 0.35),
                              offset: const Offset(0, 4),
                              blurRadius: 12,
                            )
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: _creating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          'Создать',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _canCreate ? Colors.white : c.ink3,
                          ),
                        ),
                ),
              ),
            )
          else
            AnimatedOpacity(
              opacity: _canProceed ? 1.0 : 0.42,
              duration: const Duration(milliseconds: 150),
              child: GestureDetector(
                onTap: _canProceed ? () => _goToStep(1) : null,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: _canProceed
                        ? SeeUColors.accent.withValues(alpha: 0.10)
                        : c.surface2,
                    borderRadius: BorderRadius.circular(SeeURadii.small),
                    border: Border.all(
                      color: _canProceed
                          ? SeeUColors.accent.withValues(alpha: 0.35)
                          : c.line,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Далее',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _canProceed ? SeeUColors.accent : c.ink3,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        PhosphorIconsBold.arrowRight,
                        size: 12,
                        color: _canProceed ? SeeUColors.accent : c.ink3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Step 1 — Info ─────────────────────────────────────────────────────────

  Widget _buildInfoPage(SeeUThemeColors c) {
    return ListView(
      children: [
        _buildCoverHero(c),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel('НАЗВАНИЕ'),
              const SizedBox(height: 8),
              _InputField(
                controller: _nameCtrl,
                hintText: 'Например, «Flutter Казахстан»',
                maxLength: 40,
                autofocus: true,
                onChanged: (_) {},
                c: c,
                showCounter: true,
              ),
              const SizedBox(height: 16),
              _SectionLabel('ОПИСАНИЕ'),
              const SizedBox(height: 8),
              _InputField(
                controller: _descCtrl,
                hintText: 'О чём эта комната? (необязательно)',
                maxLength: 500,
                maxLines: 4,
                fieldHeight: 88,
                c: c,
              ),
              const SizedBox(height: 26),
              _SectionLabel('ПРИВАТНОСТЬ'),
              const SizedBox(height: 10),
              _buildPrivacyControl(c),
              const SizedBox(height: 26),
              _buildInfoCard(c),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCoverHero(SeeUThemeColors c) {
    return GestureDetector(
      onTap: _coverImage == null ? _pickCoverImage : null,
      child: SizedBox(
        height: 210,
        width: double.infinity,
        child: _coverImage != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(_coverImage!.path), fit: BoxFit.cover),
                  // Gradient overlay
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x80000000)],
                        stops: [0.4, 1.0],
                      ),
                    ),
                  ),
                  // Change button bottom-right
                  Positioned(
                    bottom: 14,
                    right: 14,
                    child: GestureDetector(
                      onTap: _pickCoverImage,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(PhosphorIconsRegular.camera,
                                size: 13, color: Colors.white),
                            const SizedBox(width: 5),
                            const Text('Изменить',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Remove button bottom-left
                  Positioned(
                    bottom: 14,
                    left: 14,
                    child: GestureDetector(
                      onTap: () => setState(() => _coverImage = null),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 0.5),
                        ),
                        child: Icon(PhosphorIconsBold.x,
                            size: 13, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              )
            : Container(
                decoration: BoxDecoration(gradient: SeeUGradients.heroOrange),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        PhosphorIconsRegular.camera,
                        size: 25,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    const SizedBox(height: 13),
                    Text(
                      'Добавить обложку',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Необязательно',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPrivacyControl(SeeUThemeColors c) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _PrivacyOption(
            icon: PhosphorIconsRegular.globe,
            label: 'Открытая',
            sublabel: 'Видна в поиске',
            selected: _isPublic,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isPublic = true);
            },
            c: c,
          ),
          _PrivacyOption(
            icon: PhosphorIconsRegular.lockSimple,
            label: 'Закрытая',
            sublabel: 'Только по ссылке',
            selected: !_isPublic,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isPublic = false);
            },
            c: c,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(SeeUThemeColors c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SeeUColors.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(SeeURadii.medium),
        border:
            Border.all(color: SeeUColors.accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: SeeUColors.accent.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child:
                Icon(PhosphorIconsRegular.info, size: 15, color: SeeUColors.accent),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: RichText(
              text: TextSpan(
                style:
                    TextStyle(fontSize: 12.5, color: c.ink2, height: 1.55),
                children: [
                  const TextSpan(text: 'Внутри сразу появятся '),
                  TextSpan(
                    text: 'текстовый чат',
                    style: TextStyle(
                        color: c.ink, fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ' и '),
                  TextSpan(
                    text: 'голосовой канал',
                    style: TextStyle(
                        color: c.ink, fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(
                      text: ' с демонстрацией экрана — ничего настраивать не нужно.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Step 2 — Members ──────────────────────────────────────────────────────

  Widget _buildMembersPage(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected avatars strip
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: _selectedUsers.isEmpty
              ? const SizedBox.shrink()
              : _buildSelectedMembersRow(c),
        ),
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: _SearchField(
            controller: _searchCtrl,
            onChanged: _onSearch,
            c: c,
          ),
        ),
        // Sub-header row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Text(
                'Подписки',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: c.ink3,
                ),
              ),
              const Spacer(),
              if (_selectedIds.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: SeeUColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'Выбрано ${_selectedIds.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: SeeUColors.accent,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _buildCandidateList(c)),
      ],
    );
  }

  Widget _buildSelectedMembersRow(SeeUThemeColors c) {
    return Container(
      height: 94,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        children: _selectedUsers.values.map((u) {
          final palIdx = u.fullName.isEmpty
              ? 0
              : (u.fullName.codeUnitAt(0) + u.fullName.length) %
                  SeeUColors.avatarPalettes.length;
          final pal = SeeUColors.avatarPalettes[palIdx];
          return GestureDetector(
            onTap: () => _toggleUser(u),
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: (u.avatarUrl?.isNotEmpty ?? false)
                              ? null
                              : LinearGradient(colors: pal),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: (u.avatarUrl?.isNotEmpty ?? false)
                            ? CachedNetworkImage(
                                imageUrl: u.avatarUrl!, fit: BoxFit.cover)
                            : Center(
                                child: Text(
                                  u.fullName.isEmpty
                                      ? '?'
                                      : u.fullName[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                      ),
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: SeeUColors.accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.bg, width: 2),
                          ),
                          child: const Icon(PhosphorIconsBold.x,
                              size: 8, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    u.username,
                    style: TextStyle(fontSize: 10, color: c.ink3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCandidateList(SeeUThemeColors c) {
    if (_loadingCandidates) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: SeeUListSkeleton(count: 6),
      );
    }
    if (_candidatesError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsRegular.wifiSlash, size: 38, color: c.ink3),
            const SizedBox(height: 12),
            Text('Не удалось загрузить список',
                style: TextStyle(color: c.ink3, fontSize: 14)),
            const SizedBox(height: 8),
            TextButton(
                onPressed: _loadCandidates,
                child: const Text('Повторить')),
          ],
        ),
      );
    }
    if (_candidates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: c.surface2,
                  shape: BoxShape.circle,
                ),
                child: Icon(PhosphorIconsRegular.usersThree,
                    size: 28, color: c.ink3),
              ),
              const SizedBox(height: 14),
              Text(
                _searchCtrl.text.isEmpty
                    ? 'Нет подписок для приглашения'
                    : 'Никого не найдено',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.ink2),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                _searchCtrl.text.isEmpty
                    ? 'Можно создать комнату без участников\nи пригласить позже'
                    : 'Попробуйте другой запрос',
                style:
                    TextStyle(fontSize: 13, color: c.ink3, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _candidates.length,
      itemBuilder: (_, i) {
        final u = _candidates[i];
        final selected = _selectedIds.contains(u.id);
        return _UserTile(
          user: u,
          selected: selected,
          onTap: () => _toggleUser(u),
          c: c,
        );
      },
    );
  }

  // ─── Bottom bar ────────────────────────────────────────────────────────────

  Widget _buildBottomBar(SeeUThemeColors c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.line, width: 0.5)),
      ),
      child: _step == 0 ? _buildStep1Cta(c) : _buildStep2Cta(c),
    );
  }

  Widget _buildStep1Cta(SeeUThemeColors c) {
    return GestureDetector(
      onTap: _canProceed ? () => _goToStep(1) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 52,
        decoration: BoxDecoration(
          gradient: _canProceed ? SeeUGradients.heroOrange : null,
          color: _canProceed ? null : c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.small),
          boxShadow: _canProceed
              ? [
                  BoxShadow(
                    color: SeeUColors.accent.withValues(alpha: 0.34),
                    offset: const Offset(0, 6),
                    blurRadius: 18,
                  )
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Далее — выбор участников',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _canProceed ? Colors.white : c.ink3,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              PhosphorIconsBold.arrowRight,
              size: 15,
              color: _canProceed ? Colors.white : c.ink3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2Cta(SeeUThemeColors c) {
    return GestureDetector(
      onTap: _canCreate ? _create : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 52,
        decoration: BoxDecoration(
          gradient: _canCreate ? SeeUGradients.heroOrange : null,
          color: _canCreate ? null : c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.small),
          boxShadow: _canCreate
              ? [
                  BoxShadow(
                    color: SeeUColors.accent.withValues(alpha: 0.34),
                    offset: const Offset(0, 6),
                    blurRadius: 18,
                  )
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: _creating
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhosphorIcons.usersThree(PhosphorIconsStyle.bold),
                    size: 18,
                    color: _canCreate ? Colors.white : c.ink3,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selectedIds.isEmpty
                        ? 'Создать без участников'
                        : 'Создать с ${_selectedIds.length} участн.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _canCreate ? Colors.white : c.ink3,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _StepDot extends StatelessWidget {
  final bool filled;
  const _StepDot({required this.filled});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: filled ? 16 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: filled
            ? SeeUColors.accent
            : context.seeuColors.line,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
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
                contentPadding:
                    const EdgeInsets.fromLTRB(16, 14, 8, 14),
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

class _PrivacyOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final bool selected;
  final VoidCallback onTap;
  final SeeUThemeColors c;

  const _PrivacyOption({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: double.infinity,
          decoration: BoxDecoration(
            color: selected ? SeeUColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : c.ink3,
              ),
              const SizedBox(width: 6),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : c.ink,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: selected
                          ? Colors.white.withValues(alpha: 0.72)
                          : c.ink3,
                    ),
                  ),
                ],
              ),
            ],
          ),
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
      height: 42,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.line, width: 0.5),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 14, color: c.ink),
        decoration: InputDecoration(
          hintText: 'Поиск людей',
          hintStyle: TextStyle(fontSize: 14, color: c.ink3),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 13, right: 8),
            child: Icon(PhosphorIcons.magnifyingGlass(), size: 16, color: c.ink3),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 38, minHeight: 42),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        ),
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
    final palIdx = user.fullName.isEmpty
        ? 0
        : (user.fullName.codeUnitAt(0) + user.fullName.length) %
            SeeUColors.avatarPalettes.length;
    final pal = SeeUColors.avatarPalettes[palIdx];
    final hasAvatar = user.avatarUrl?.isNotEmpty ?? false;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? SeeUColors.accent.withValues(alpha: 0.07)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: hasAvatar ? null : LinearGradient(colors: pal),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasAvatar
                  ? CachedNetworkImage(
                      imageUrl: user.avatarUrl!, fit: BoxFit.cover)
                  : Center(
                      child: Text(
                        user.fullName.isEmpty
                            ? '?'
                            : user.fullName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            // Name + username
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '@${user.username}',
                    style: TextStyle(fontSize: 13, color: c.ink3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Checkbox
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: selected ? SeeUGradients.heroOrange : null,
                border: selected
                    ? null
                    : Border.all(color: c.line, width: 1.5),
              ),
              child: selected
                  ? const Icon(PhosphorIconsBold.check,
                      color: Colors.white, size: 13)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
