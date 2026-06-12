import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';

/// Экран редактирования scan-профиля — анонимная «личность» в BLE-сканере.
/// Псевдоним, аватар и переключатель видимости в сканере.
/// PUT /users/me/scan-profile { scan_alias, scan_avatar_url, scan_enabled }
class ScanProfileScreen extends ConsumerStatefulWidget {
  const ScanProfileScreen({super.key});

  @override
  ConsumerState<ScanProfileScreen> createState() => _ScanProfileScreenState();
}

class _ScanProfileScreenState extends ConsumerState<ScanProfileScreen> {
  final _aliasCtrl = TextEditingController();
  bool _scanEnabled = true;
  bool _busy = false;
  String _currentAvatarUrl = '';

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _aliasCtrl.text = user?.scanAlias ?? '';
    _scanEnabled = user?.scanEnabled ?? true;
    _currentAvatarUrl = user?.scanAvatarUrl ?? '';
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    if (file == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path,
            filename: 'scan_avatar.jpg'),
      });
      final res = await api.post(ApiEndpoints.mediaUpload, data: formData);
      final url = res.data['data']?['url']?.toString() ?? '';
      if (url.isNotEmpty && mounted) {
        setState(() => _currentAvatarUrl = url);
      }
    } on DioException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка загрузки: ${apiErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      await api.put(ApiEndpoints.myScanProfile, data: {
        'scan_alias': _aliasCtrl.text.trim(),
        'scan_avatar_url': _currentAvatarUrl,
        'scan_enabled': _scanEnabled,
      });
      await ref.read(authProvider.notifier).reloadMe();
      if (!mounted) return;
      messenger.showSnackBar(
          const SnackBar(content: Text('Scan-профиль сохранён')));
      context.pop();
    } on DioException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка: ${apiErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
          onPressed: () => context.pop(),
        ),
        title: Text('Scan-профиль',
            style: TextStyle(
                fontFamily: 'Fraunces',
                fontWeight: FontWeight.w400,
                fontSize: 22,
                color: c.ink)),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: Text('Сохранить',
                style: TextStyle(
                    color: SeeUColors.accent,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Privacy info
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SeeUColors.accentSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(PhosphorIcons.shieldCheck(),
                      size: 18, color: SeeUColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Это отдельная анонимная «личность» в сканере. '
                      'Реальный аккаунт не раскрывается тем, кого вы лайкаете.',
                      style: TextStyle(
                          fontSize: 12,
                          color: c.ink2,
                          height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Avatar
            Center(
              child: GestureDetector(
                onTap: _busy ? null : _pickAndUploadAvatar,
                child: Stack(
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.surface2,
                        border: Border.all(color: c.line, width: 2),
                      ),
                      child: ClipOval(
                        child: _currentAvatarUrl.isNotEmpty
                            ? Image.network(_currentAvatarUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _avatarPlaceholder(c))
                            : _avatarPlaceholder(c),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: SeeUColors.accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2),
                        ),
                        child: Icon(PhosphorIcons.camera(),
                            size: 13, color: Colors.white),
                      ),
                    ),
                    if (_busy)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('Аватар сканера',
                  style: SeeUTypography.caption.copyWith(color: c.ink3)),
            ),
            const SizedBox(height: 28),

            // Alias
            Text('Псевдоним', style: SeeUTypography.caption.copyWith(
                color: c.ink3, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _aliasCtrl,
              maxLength: 32,
              decoration: InputDecoration(
                hintText: 'Например: Путешественник',
                prefixIcon:
                    Icon(PhosphorIcons.ghost(), color: c.ink3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                counterText: '',
              ),
            ),
            const SizedBox(height: 6),
            Text('Это имя увидят другие пользователи в сканере вместо вашего.',
                style: SeeUTypography.micro.copyWith(color: c.ink4)),
            const SizedBox(height: 28),

            // Visibility toggle
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _scanEnabled
                          ? SeeUColors.accent.withValues(alpha: 0.1)
                          : c.surface2,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _scanEnabled
                          ? PhosphorIcons.eye()
                          : PhosphorIcons.eyeSlash(),
                      size: 20,
                      color: _scanEnabled ? SeeUColors.accent : c.ink3,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Видимость в сканере',
                            style: SeeUTypography.body.copyWith(
                                fontWeight: FontWeight.w600, color: c.ink)),
                        const SizedBox(height: 2),
                        Text(
                          _scanEnabled
                              ? 'Вас видят рядом другие пользователи'
                              : 'Вы скрыты от всех в сканере',
                          style: SeeUTypography.caption.copyWith(color: c.ink3),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _scanEnabled,
                    onChanged: (v) => setState(() => _scanEnabled = v),
                    activeThumbColor: SeeUColors.accent,
                    activeTrackColor: SeeUColors.accent.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            SeeUButton(
              label: 'Сохранить',
              isLoading: _busy,
              onTap: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarPlaceholder(SeeUThemeColors c) => Center(
        child: Icon(PhosphorIcons.ghost(), size: 36, color: c.ink3),
      );
}
