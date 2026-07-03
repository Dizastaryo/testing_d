import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/user_provider.dart';
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
  XFile? _pickedFile;
  Uint8List? _pickedBytes;
  bool _avatarRemoved = false;
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

  Future<void> _pickFromSource(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 800);
    if (picked != null && mounted) {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedFile = picked;
        _pickedBytes = bytes;
        _avatarRemoved = false;
      });
    }
  }

  void _pickAvatar() {
    showSeeUBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Изменить фото', style: SeeUTypography.subtitle),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(PhosphorIcons.camera(PhosphorIconsStyle.fill),
                    color: SeeUColors.accent),
                title: Text('Сделать фото', style: SeeUTypography.body),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickFromSource(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(PhosphorIcons.image(PhosphorIconsStyle.fill),
                    color: SeeUColors.accent),
                title: Text('Выбрать из галереи', style: SeeUTypography.body),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickFromSource(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Icon(PhosphorIcons.trash(PhosphorIconsStyle.fill),
                    color: SeeUColors.error),
                title: Text('Удалить фото',
                    style: SeeUTypography.body.copyWith(color: SeeUColors.error)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() {
                    _pickedFile = null;
                    _pickedBytes = null;
                    _avatarRemoved = true;
                  });
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
    final oldUsername = ref.read(authProvider).user?.username;
    try {
      final api = ref.read(apiClientProvider);

      // Upload avatar if a new file was picked
      String? avatarUrl;
      if (_pickedFile != null && _pickedBytes != null) {
        final form = FormData.fromMap({
          'file': MultipartFile.fromBytes(_pickedBytes!, filename: _pickedFile!.name),
        });
        final uploadResp = await api.post(ApiEndpoints.mediaUpload, data: form);
        final uploadData = uploadResp.data;
        avatarUrl = (uploadData is Map && uploadData['data'] is Map)
            ? uploadData['data']['url'] as String?
            : uploadData is Map
                ? uploadData['url'] as String?
                : null;
      } else if (_avatarRemoved) {
        avatarUrl = '';
      }

      final body = <String, dynamic>{
        'full_name': _fullNameCtrl.text.trim(),
        'username': _usernameCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'website': _websiteCtrl.text.trim(),
      };
      if (avatarUrl != null) {
        body['avatar_url'] = avatarUrl;
      }

      final resp = await api.put(ApiEndpoints.me, data: body);
      final data = resp.data;
      final userData = data is Map && data.containsKey('data') ? data['data'] : data;
      final updated = User.fromJson(userData as Map<String, dynamic>);
      if (mounted) {
        ref.read(authProvider.notifier).updateUser(updated);
        // Профиль читается из отдельного userProfileProvider — без инвалидации
        // экран профиля показывал бы старые данные после сохранения. Сбрасываем
        // и старый, и новый username (ник мог смениться).
        ref.invalidate(userProfileProvider(updated.username));
        if (oldUsername != null && oldUsername != updated.username) {
          ref.invalidate(userProfileProvider(oldUsername));
        }
        showSeeUSnackBar(context, 'Профиль обновлён!',
            tone: SeeUTone.success);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        // Показываем реальную причину с бэка (ник занят / неверный формат и т.п.),
        // а не общий текст — иначе непонятно, почему не сохраняется.
        String msg = 'Не удалось сохранить';
        if (e is DioException) {
          final body = e.response?.data;
          final serverMsg = body is Map ? body['error']?.toString() : null;
          if (serverMsg != null && serverMsg.isNotEmpty) msg = serverMsg;
        }
        showSeeUSnackBar(context, msg, tone: SeeUTone.danger);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: SeeUColors.background,
      body: Column(
        children: [
          SeeUGlassBar(
            titleText: 'Профиль',
            kicker: 'РЕДАКТИРОВАНИЕ',
            leading: Tappable.scaled(
              onTap: () => context.pop(),
              scaleFactor: 0.9,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(PhosphorIcons.caretLeft(),
                    size: 22, color: SeeUColors.textPrimary),
              ),
            ),
          ),
          Expanded(
            child: Form(
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
                      backgroundImage: _pickedBytes != null
                          ? MemoryImage(_pickedBytes!)
                          : (_avatarRemoved || user?.avatarUrl == null
                              ? null
                              : NetworkImage(user!.avatarUrl!)) as ImageProvider?,
                      child: (_pickedBytes == null && (_avatarRemoved || user?.avatarUrl == null))
                          ? Text(
                              (user?.username.isNotEmpty ?? false)
                                  ? user!.username[0].toUpperCase()
                                  : 'U',
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
                          color: (_pickedFile != null || _avatarRemoved)
                              ? SeeUColors.success
                              : SeeUColors.accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: SeeUColors.background,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          (_pickedFile != null || _avatarRemoved)
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
            Text('Полное имя',
                style: SeeUTypography.kicker
                    .copyWith(color: SeeUColors.textTertiary)),
            const SizedBox(height: 6),
            SeeUInput(
              controller: _fullNameCtrl,
              textCapitalization: TextCapitalization.words,
              hintText: 'Полное имя',
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Обязательное поле' : null,
            ),
            const SizedBox(height: 16),

            Text('Имя пользователя',
                style: SeeUTypography.kicker
                    .copyWith(color: SeeUColors.textTertiary)),
            const SizedBox(height: 6),
            SeeUInput(
              controller: _usernameCtrl,
              autocorrect: false,
              hintText: 'Имя пользователя',
              validator: (v) {
                final val = v?.trim() ?? '';
                if (val.isEmpty) return 'Обязательное поле';
                if (val.length < 3) return 'Минимум 3 символа';
                if (!RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(val)) {
                  return 'Только буквы, цифры, _ и .';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            Text('О себе',
                style: SeeUTypography.kicker
                    .copyWith(color: SeeUColors.textTertiary)),
            const SizedBox(height: 6),
            SeeUInput(
              controller: _bioCtrl,
              maxLines: 3,
              maxLength: 150,
              hintText: 'Расскажите о себе...',
            ),
            const SizedBox(height: 16),

            Text('Сайт',
                style: SeeUTypography.kicker
                    .copyWith(color: SeeUColors.textTertiary)),
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
          ),
        ],
      ),
    );
  }
}
