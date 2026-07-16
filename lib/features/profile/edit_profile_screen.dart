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
  // §05: человекочитаемый текст ссылки — показывается в профиле вместо URL.
  late final TextEditingController _websiteLabelCtrl;
  XFile? _pickedFile;
  Uint8List? _pickedBytes;
  bool _avatarRemoved = false;
  // Баннер профиля (channel_banner_url) — раньше рендерился на профиле, но
  // задать его из приложения было нельзя (нет UI). Теперь редактируется.
  XFile? _pickedBannerFile;
  Uint8List? _pickedBannerBytes;
  bool _bannerRemoved = false;
  String? _uploadedBannerUrl;
  bool _isSaving = false;
  // Кэш URL уже загруженного на прошлой попытке аватара. Если PUT /users/me
  // упал после успешной загрузки файла, повторный тап "Сохранить" не должен
  // заново заливать тот же файл — иначе на каждый ретрай плодятся сиротские
  // медиа-загрузки на бэке. Сбрасывается только при выборе нового файла или
  // удалении аватара.
  String? _uploadedAvatarUrl;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _fullNameCtrl = TextEditingController(text: user?.fullName ?? '');
    _usernameCtrl = TextEditingController(text: user?.username ?? '');
    _bioCtrl = TextEditingController(text: user?.bio ?? '');
    _websiteCtrl = TextEditingController(text: user?.website ?? '');
    _websiteLabelCtrl = TextEditingController(text: user?.websiteLabel ?? '');
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _websiteCtrl.dispose();
    _websiteLabelCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFromSource(ImageSource source) async {
    // maxHeight + imageQuality: раньше был только maxWidth — очень высокая
    // картинка давала огромный несжатый буфер, который заливался как есть.
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedFile = picked;
        _pickedBytes = bytes;
        _avatarRemoved = false;
        // Новый файл — предыдущая загрузка (если была) больше не актуальна.
        _uploadedAvatarUrl = null;
      });
    }
  }

  Future<void> _pickBanner() async {
    // Баннер широкий (16:6) — больший maxWidth, но тоже сжимаем.
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedBannerFile = picked;
        _pickedBannerBytes = bytes;
        _bannerRemoved = false;
        _uploadedBannerUrl = null;
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
                    _uploadedAvatarUrl = null;
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

      // Upload avatar if a new file was picked. Если файл уже был успешно
      // загружен на прошлой (неудачной) попытке сохранения, переиспользуем
      // готовый URL вместо повторной заливки того же файла.
      String? avatarUrl;
      if (_uploadedAvatarUrl != null) {
        avatarUrl = _uploadedAvatarUrl;
      } else if (_pickedFile != null && _pickedBytes != null) {
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
        _uploadedAvatarUrl = avatarUrl;
      } else if (_avatarRemoved) {
        avatarUrl = '';
      }

      // Баннер — та же логика: заливаем новый / очищаем / не трогаем.
      String? bannerUrl;
      if (_uploadedBannerUrl != null) {
        bannerUrl = _uploadedBannerUrl;
      } else if (_pickedBannerFile != null && _pickedBannerBytes != null) {
        final form = FormData.fromMap({
          'file': MultipartFile.fromBytes(_pickedBannerBytes!,
              filename: _pickedBannerFile!.name),
        });
        final uploadResp = await api.post(ApiEndpoints.mediaUpload, data: form);
        final uploadData = uploadResp.data;
        bannerUrl = (uploadData is Map && uploadData['data'] is Map)
            ? uploadData['data']['url'] as String?
            : uploadData is Map
                ? uploadData['url'] as String?
                : null;
        _uploadedBannerUrl = bannerUrl;
      } else if (_bannerRemoved) {
        bannerUrl = '';
      }

      final body = <String, dynamic>{
        'full_name': _fullNameCtrl.text.trim(),
        'username': _usernameCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'website': _websiteCtrl.text.trim(),
        // §05: текст ссылки — рендерится в профиле вместо сырого URL.
        'website_label': _websiteLabelCtrl.text.trim(),
      };
      if (avatarUrl != null) {
        body['avatar_url'] = avatarUrl;
      }
      // channel_banner_url — pointer на бэке: шлём только при изменении.
      if (bannerUrl != null) {
        body['channel_banner_url'] = bannerUrl;
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
            const SizedBox(height: 16),

            // Banner (16:6) — редактируемый channel_banner_url.
            GestureDetector(
              onTap: _pickBanner,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(SeeURadii.card),
                    child: AspectRatio(
                      aspectRatio: 16 / 6,
                      child: _pickedBannerBytes != null
                          ? Image.memory(_pickedBannerBytes!, fit: BoxFit.cover)
                          : (!_bannerRemoved &&
                                  (user?.channelBannerUrl.isNotEmpty ?? false))
                              ? Image.network(user!.channelBannerUrl,
                                  fit: BoxFit.cover)
                              : Container(
                                  color: SeeUColors.surfaceElevated,
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(PhosphorIcons.image(),
                                            color: SeeUColors.textTertiary,
                                            size: 28),
                                        const SizedBox(height: 4),
                                        Text('Добавить баннер',
                                            style: SeeUTypography.caption
                                                .copyWith(
                                                    color: SeeUColors
                                                        .textTertiary)),
                                      ],
                                    ),
                                  ),
                                ),
                    ),
                  ),
                  // Кнопка удаления баннера, если он есть.
                  if (_pickedBannerBytes != null ||
                      (!_bannerRemoved &&
                          (user?.channelBannerUrl.isNotEmpty ?? false)))
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _bannerRemoved = true;
                          _pickedBannerFile = null;
                          _pickedBannerBytes = null;
                          _uploadedBannerUrl = null;
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(PhosphorIcons.x(),
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                ],
              ),
            ),
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
                          : (_avatarRemoved ||
                                  user?.avatarUrl == null ||
                                  user!.avatarUrl!.isEmpty
                              ? null
                              : NetworkImage(user.avatarUrl!)) as ImageProvider?,
                      child: (_pickedBytes == null &&
                              (_avatarRemoved ||
                                  user?.avatarUrl == null ||
                                  user!.avatarUrl!.isEmpty))
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

            // Form fields — kicker-лейблы в ВЕРХНЕМ РЕГИСТРЕ (§05).
            Text('ПОЛНОЕ ИМЯ',
                style: SeeUTypography.kicker
                    .copyWith(color: SeeUColors.textTertiary)),
            const SizedBox(height: 6),
            SeeUInput(
              controller: _fullNameCtrl,
              textCapitalization: TextCapitalization.words,
              hintText: 'Полное имя',
              maxLength: 50,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Обязательное поле' : null,
            ),
            const SizedBox(height: 16),

            Text('ИМЯ ПОЛЬЗОВАТЕЛЯ',
                style: SeeUTypography.kicker
                    .copyWith(color: SeeUColors.textTertiary)),
            const SizedBox(height: 6),
            SeeUInput(
              controller: _usernameCtrl,
              autocorrect: false,
              hintText: 'Имя пользователя',
              maxLength: 30,
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

            Text('О СЕБЕ',
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

            Text('ССЫЛКА (URL)',
                style: SeeUTypography.kicker
                    .copyWith(color: SeeUColors.textTertiary)),
            const SizedBox(height: 6),
            SeeUInput(
              controller: _websiteCtrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              hintText: 'Ссылка на сайт',
              maxLength: 200,
            ),
            const SizedBox(height: 16),

            // §05: человекочитаемый текст ссылки — в профиле показывается
            // вместо сырого URL, тап по нему открывает саму ссылку.
            Text('ТЕКСТ ССЫЛКИ',
                style: SeeUTypography.kicker
                    .copyWith(color: SeeUColors.textTertiary)),
            const SizedBox(height: 6),
            SeeUInput(
              controller: _websiteLabelCtrl,
              hintText: 'Как подписать ссылку',
              maxLength: 80,
            ),
            const SizedBox(height: 4),
            Text(
              'тап по тексту откроет ссылку',
              style: SeeUTypography.micro.copyWith(
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                color: SeeUColors.textQuaternary,
              ),
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
