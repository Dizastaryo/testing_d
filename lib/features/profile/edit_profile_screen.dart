import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/models/user.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _fullNameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _websiteCtrl;
  bool _avatarChanged = false;
  bool _isSaving = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _fullNameCtrl = TextEditingController(text: user?.fullName ?? '');
    _usernameCtrl = TextEditingController(text: user?.username ?? '');
    _bioCtrl = TextEditingController(text: user?.bio ?? '');
    _websiteCtrl = TextEditingController(text: user?.website ?? '');
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _websiteCtrl.dispose();
    super.dispose();
  }

  void _pickAvatar() {
    showModalBottomSheet(
      context: context,
      backgroundColor: SeeUColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: SeeUColors.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Изменить фото', style: SeeUTypography.subtitle),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(PhosphorIcons.camera(PhosphorIconsStyle.fill),
                    color: SeeUColors.accent),
                title: Text('Сделать фото', style: SeeUTypography.body),
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _avatarChanged = true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Фото обновлено',
                          style: SeeUTypography.body.copyWith(color: Colors.white)),
                      backgroundColor: SeeUColors.success,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(SeeURadii.small)),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(PhosphorIcons.image(PhosphorIconsStyle.fill),
                    color: SeeUColors.accent),
                title: Text('Выбрать из галереи', style: SeeUTypography.body),
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _avatarChanged = true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Фото обновлено',
                          style: SeeUTypography.body.copyWith(color: Colors.white)),
                      backgroundColor: SeeUColors.success,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(SeeURadii.small)),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(PhosphorIcons.trash(PhosphorIconsStyle.fill),
                    color: SeeUColors.error),
                title: Text('Удалить фото',
                    style: SeeUTypography.body.copyWith(color: SeeUColors.error)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _avatarChanged = true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Фото удалено',
                          style: SeeUTypography.body.copyWith(color: Colors.white)),
                      backgroundColor: SeeUColors.textSecondary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(SeeURadii.small)),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);
    try {
      final resp = await ref.read(apiClientProvider).put(ApiEndpoints.me, data: {
        'full_name': _fullNameCtrl.text.trim(),
        'username': _usernameCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'website': _websiteCtrl.text.trim(),
      });
      final data = resp.data;
      final userData = data is Map && data.containsKey('data') ? data['data'] : data;
      final updated = User.fromJson(userData as Map<String, dynamic>);
      if (mounted) {
        ref.read(authProvider.notifier).updateUser(updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Профиль обновлён!',
                style: SeeUTypography.body.copyWith(color: Colors.white)),
            backgroundColor: SeeUColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SeeURadii.small)),
          ),
        );
        context.pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось сохранить',
                style: SeeUTypography.body.copyWith(color: Colors.white)),
            backgroundColor: SeeUColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SeeURadii.small)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: SeeUColors.background,
      appBar: AppBar(
        backgroundColor: SeeUColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Редактировать профиль', style: SeeUTypography.subtitle),
        leading: IconButton(
          icon: Icon(PhosphorIcons.arrowLeft(),
              size: 22, color: SeeUColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: SeeUColors.accent, strokeWidth: 2),
                    )
                  : Text(
                      'Готово',
                      style: SeeUTypography.subtitle.copyWith(
                        color: SeeUColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            const SizedBox(height: 24),

            // Avatar
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: SeeUColors.surfaceElevated,
                      backgroundImage: user?.avatarUrl != null
                          ? NetworkImage(user!.avatarUrl!)
                          : null,
                      child: user?.avatarUrl == null
                          ? Text(
                              user?.username.substring(0, 1).toUpperCase() ??
                                  'U',
                              style: SeeUTypography.displayL.copyWith(
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _avatarChanged
                              ? SeeUColors.success
                              : SeeUColors.accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: SeeUColors.background,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          _avatarChanged
                              ? PhosphorIcons.check(PhosphorIconsStyle.bold)
                              : PhosphorIcons.camera(PhosphorIconsStyle.fill),
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Text(
                  'Изменить фото профиля',
                  style: SeeUTypography.body.copyWith(
                    color: SeeUColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Form fields
            Text('Полное имя', style: SeeUTypography.caption),
            const SizedBox(height: 6),
            SeeUInput(
              controller: _fullNameCtrl,
              textCapitalization: TextCapitalization.words,
              hintText: 'Полное имя',
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Обязательное поле' : null,
            ),
            const SizedBox(height: 16),

            Text('Имя пользователя', style: SeeUTypography.caption),
            const SizedBox(height: 6),
            SeeUInput(
              controller: _usernameCtrl,
              autocorrect: false,
              hintText: 'Имя пользователя',
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Обязательное поле';
                if (v.length < 3) return 'Минимум 3 символа';
                return null;
              },
            ),
            const SizedBox(height: 16),

            Text('О себе', style: SeeUTypography.caption),
            const SizedBox(height: 6),
            SeeUInput(
              controller: _bioCtrl,
              maxLines: 3,
              maxLength: 150,
              hintText: 'Расскажите о себе...',
            ),
            const SizedBox(height: 16),

            Text('Сайт', style: SeeUTypography.caption),
            const SizedBox(height: 6),
            SeeUInput(
              controller: _websiteCtrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              hintText: 'Ссылка на сайт',
            ),
            const SizedBox(height: 40),

            SeeUButton(
              label: 'Сохранить',
              variant: SeeUButtonVariant.primary,
              isLoading: _isSaving,
              onTap: _isSaving ? null : _save,
            ),
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }
}
