import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/utils/format.dart';
import '../../core/models/user.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/chat_provider.dart';
import '../../core/providers/following_candidates_provider.dart';

/// Создание группового чата — двухшаговый флоу:
/// 1. Настройка (обложка + название).
/// 2. Участники (мин. 1).
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

  // Cover: либо локальный файл (выбран из галереи), либо preset URL.
  // Загрузка происходит только в момент _submit() чтобы не тратить трафик впустую.
  XFile? _localCoverFile;
  String? _presetCoverUrl;
  bool _uploadingCover = false;

  static List<String> get _coverPresets => [
        '${AppConfig.r2PublicUrl}/uploads/seed/highlights/h1.jpg',
        '${AppConfig.r2PublicUrl}/uploads/seed/highlights/h2.jpg',
        '${AppConfig.r2PublicUrl}/uploads/seed/highlights/h3.jpg',
        '${AppConfig.r2PublicUrl}/uploads/seed/highlights/h4.jpg',
        '${AppConfig.r2PublicUrl}/uploads/seed/highlights/h5.jpg',
      ];

  final Set<String> _selectedIds = {};
  final Map<String, User> _selectedUsers = {};

  List<User> _candidates = [];
  bool _loading = true;
  String? _error;
  bool _submitting = false;

  int _step = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _titleCtrl.addListener(_onTitleChanged);
    _loadInitial();
  }

  void _onTitleChanged() => setState(() {});

  @override
  void dispose() {
    _pageController.dispose();
    _titleCtrl.removeListener(_onTitleChanged);
    _titleCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
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

  // ─── Candidates ────────────────────────────────────────────────────────────

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref.read(followingCandidatesProvider.future);
      if (mounted) setState(() => _candidates = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final query = q.trim();
      if (query.isEmpty) {
        _loadInitial();
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
        if (mounted) setState(() => _candidates = users);
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
      } finally {
        if (mounted) setState(() => _loading = false);
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

  // ─── Cover ─────────────────────────────────────────────────────────────────

  Future<void> _pickCoverFromGallery() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _localCoverFile = picked;
      _presetCoverUrl = null;
    });
  }

  void _selectPreset(String url) {
    HapticFeedback.selectionClick();
    setState(() {
      _presetCoverUrl = url;
      _localCoverFile = null;
    });
  }

  void _clearCover() => setState(() {
        _localCoverFile = null;
        _presetCoverUrl = null;
      });

  // ─── Submit ────────────────────────────────────────────────────────────────

  bool get _canProceed => _titleCtrl.text.trim().isNotEmpty;
  bool get _canSubmit => _selectedIds.isNotEmpty && !_submitting;

  Future<void> _submit() async {
    if (!_canSubmit || _titleCtrl.text.trim().isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);

      // Upload cover if local file was selected
      String finalCoverUrl = _presetCoverUrl ?? '';
      if (_localCoverFile != null) {
        setState(() => _uploadingCover = true);
        final bytes = await _localCoverFile!.readAsBytes();
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: _localCoverFile!.name),
        });
        final upload = await api.post(ApiEndpoints.mediaUpload, data: formData);
        finalCoverUrl = upload.data['data']['url'] as String;
        if (mounted) setState(() => _uploadingCover = false);
      }

      final r = await api.post(
        ApiEndpoints.chats,
        data: {
          'kind': 'group',
          'title': _titleCtrl.text.trim(),
          'cover_url': finalCoverUrl,
          'member_ids': _selectedIds.toList(),
        },
      );
      final data = r.data is Map && (r.data as Map).containsKey('data')
          ? r.data['data']
          : r.data;
      final id = data is Map ? data['id']?.toString() : null;
      if (id == null || id.isEmpty) throw Exception('сервер не вернул id чата');

      if (!mounted) return;
      ref.read(chatListProvider.notifier).load();
      context.pushReplacement('/chat/$id');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _uploadingCover = false;
      });
      showSeeUSnackBar(
        context,
        'Не удалось создать группу: ${friendlyError(e)}',
        tone: SeeUTone.danger,
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
        top: false,
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
    return SeeUGlassBar(
      leading: GestureDetector(
        onTap: isStep2
            ? () => _goToStep(0)
            : () => Navigator.of(context).pop(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            isStep2
                ? PhosphorIcons.caretLeft(PhosphorIconsStyle.bold)
                : PhosphorIcons.x(PhosphorIconsStyle.bold),
            size: 22,
            color: c.ink,
          ),
        ),
      ),
      kicker: 'НОВАЯ ГРУППА · ШАГ ${isStep2 ? 2 : 1} ИЗ 2',
      titleText: isStep2 ? 'Участники' : 'Настройка',
      actions: [
        // Right CTA
        if (isStep2)
            AnimatedOpacity(
              opacity: (_canSubmit && !_submitting) ? 1.0 : 0.45,
              duration: const Duration(milliseconds: 150),
              child: GestureDetector(
                onTap: (_canSubmit && !_submitting) ? _submit : null,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    gradient: (_canSubmit && !_submitting)
                        ? SeeUGradients.heroOrange
                        : null,
                    color: (_canSubmit && !_submitting) ? null : c.surface2,
                    borderRadius: BorderRadius.circular(SeeURadii.small),
                    boxShadow: (_canSubmit && !_submitting)
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
                  child: (_submitting || _uploadingCover)
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
                            color: _canSubmit ? Colors.white : c.ink3,
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
                      Icon(PhosphorIconsBold.arrowRight,
                          size: 12,
                          color: _canProceed ? SeeUColors.accent : c.ink3),
                    ],
                  ),
                ),
              ),
            ),
        ],
    );
  }

  // ─── Step 1 — Info ─────────────────────────────────────────────────────────

  Widget _buildInfoPage(SeeUThemeColors c) {
    return ListView(
      children: [
        _buildCoverHero(c),
        _buildPresetRow(c),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel('НАЗВАНИЕ ГРУППЫ'),
              const SizedBox(height: 8),
              _buildNameField(c),
              const SizedBox(height: 24),
              _buildInfoCard(c),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCoverHero(SeeUThemeColors c) {
    final hasLocal = _localCoverFile != null;
    final hasPreset = _presetCoverUrl != null;
    final hasCover = hasLocal || hasPreset;

    return GestureDetector(
      onTap: hasCover ? null : _pickCoverFromGallery,
      child: SizedBox(
        height: 210,
        width: double.infinity,
        child: hasCover
            ? Stack(
                fit: StackFit.expand,
                children: [
                  // Image
                  hasLocal
                      ? Image.file(File(_localCoverFile!.path), fit: BoxFit.cover)
                      : CachedNetworkImage(
                          imageUrl: _presetCoverUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: c.surface2,
                          ),
                        ),
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
                  // Change button
                  Positioned(
                    bottom: 14,
                    right: 14,
                    child: GestureDetector(
                      onTap: _pickCoverFromGallery,
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
                  // Remove button
                  Positioned(
                    bottom: 14,
                    left: 14,
                    child: GestureDetector(
                      onTap: _clearCover,
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
                decoration:
                    BoxDecoration(gradient: SeeUGradients.heroOrange),
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
                      'Добавить фото группы',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'или выберите тему ниже',
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

  Widget _buildPresetRow(SeeUThemeColors c) {
    return Container(
      color: c.surface,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: SizedBox(
        height: 62,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            // Без обложки (default gradient)
            _PresetTile(
              isSelected: _localCoverFile == null && _presetCoverUrl == null,
              onTap: _clearCover,
              child: Container(
                decoration: BoxDecoration(gradient: SeeUGradients.heroOrange),
                child: Icon(
                  PhosphorIcons.usersThree(PhosphorIconsStyle.bold),
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Загрузить своё
            _PresetTile(
              isSelected: _localCoverFile != null,
              onTap: _pickCoverFromGallery,
              child: _localCoverFile != null
                  ? Image.file(File(_localCoverFile!.path), fit: BoxFit.cover)
                  : Container(
                      color: c.surface2,
                      child: Icon(PhosphorIconsRegular.upload,
                          size: 20, color: c.ink3),
                    ),
            ),
            const SizedBox(width: 10),
            // Seed presets
            ..._coverPresets.map((url) {
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _PresetTile(
                  isSelected: _presetCoverUrl == url,
                  onTap: () => _selectPreset(url),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: c.surface2),
                    errorWidget: (_, __, ___) =>
                        Container(color: c.surface2),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildNameField(SeeUThemeColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _titleCtrl,
              autofocus: false,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(fontSize: 15, color: c.ink),
              decoration: InputDecoration(
                hintText: 'Например, «Наша банда»',
                hintStyle: TextStyle(fontSize: 15, color: c.ink3),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.fromLTRB(16, 14, 8, 14),
                counterText: '',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              '${_titleCtrl.text.length}/40',
              style: TextStyle(fontSize: 12, color: c.ink3),
            ),
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
        border: Border.all(color: SeeUColors.accent.withValues(alpha: 0.18)),
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
            child: Icon(PhosphorIconsRegular.info,
                size: 15, color: SeeUColors.accent),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                    fontSize: 12.5, color: c.ink2, height: 1.55),
                children: [
                  const TextSpan(text: 'На следующем шаге добавьте '),
                  TextSpan(
                    text: 'минимум одного участника',
                    style: TextStyle(
                        color: c.ink, fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(
                      text: '. Пригласить ещё можно будет позже из чата.'),
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
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: c.line, width: 0.5),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              style: TextStyle(fontSize: 14, color: c.ink),
              decoration: InputDecoration(
                hintText: 'Поиск людей',
                hintStyle: TextStyle(fontSize: 14, color: c.ink3),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 13, right: 8),
                  child: Icon(PhosphorIcons.magnifyingGlass(),
                      size: 16, color: c.ink3),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 38, minHeight: 42),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              ),
            ),
          ),
        ),
        // Sub-header
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 3),
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
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: SeeUListSkeleton(count: 6),
      );
    }
    if (_error != null) {
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
                onPressed: _loadInitial, child: const Text('Повторить')),
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
                decoration:
                    BoxDecoration(color: c.surface2, shape: BoxShape.circle),
                child: Icon(PhosphorIconsRegular.usersThree,
                    size: 28, color: c.ink3),
              ),
              const SizedBox(height: 14),
              Text(
                _searchCtrl.text.isEmpty
                    ? 'Нет подписок'
                    : 'Никого не найдено',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.ink2),
              ),
              const SizedBox(height: 6),
              Text(
                _searchCtrl.text.isEmpty
                    ? 'Подпишитесь на кого-нибудь,\nчтобы добавить в группу'
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
            user: u, selected: selected, onTap: () => _toggleUser(u), c: c);
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
                      blurRadius: 18)
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Далее — добавить участников',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _canProceed ? Colors.white : c.ink3),
            ),
            const SizedBox(width: 8),
            Icon(PhosphorIconsBold.arrowRight,
                size: 15, color: _canProceed ? Colors.white : c.ink3),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2Cta(SeeUThemeColors c) {
    final enabled = _canSubmit && !_submitting;
    return GestureDetector(
      onTap: enabled ? _submit : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 52,
        decoration: BoxDecoration(
          gradient: enabled ? SeeUGradients.heroOrange : null,
          color: enabled ? null : c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.small),
          boxShadow: enabled
              ? [
                  BoxShadow(
                      color: SeeUColors.accent.withValues(alpha: 0.34),
                      offset: const Offset(0, 6),
                      blurRadius: 18)
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: (_submitting || _uploadingCover)
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
                    color: enabled ? Colors.white : c.ink3,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selectedIds.isEmpty
                        ? 'Выберите участников'
                        : 'Создать группу · ${_selectedIds.length} чел.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: enabled ? Colors.white : c.ink3,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: context.seeuColors.ink3,
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final Widget child;

  const _PresetTile({
    required this.isSelected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? SeeUColors.accent : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: SeeUColors.accent.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text('@${user.username}',
                      style: TextStyle(fontSize: 13, color: c.ink3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
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
