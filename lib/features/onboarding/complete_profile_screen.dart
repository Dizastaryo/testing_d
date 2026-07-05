import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/models/user.dart';

/// Обязательный экран после первого входа по OTP — новый юзер не может
/// попасть в приложение, пока не заполнит имя и никнейм (аватар — опционально,
/// можно добавить позже через обычное редактирование профиля).
///
/// Гейтится в main.dart по `user.fullName.trim().isEmpty` — durable-сигнал,
/// в отличие от одноразового `isNewUser` из ответа verify-otp, который
/// теряется при перезапуске приложения.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  late final TextEditingController _fullNameCtrl;
  late final TextEditingController _usernameCtrl;
  XFile? _pickedFile;
  Uint8List? _pickedBytes;
  bool _isSaving = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _fullNameCtrl = TextEditingController(text: user?.fullName ?? '');
    // Предзаполняем авто-сгенерированным никнеймом (user_<цифры>) — юзер
    // может оставить как есть или сразу поменять на нормальный.
    _usernameCtrl = TextEditingController(text: user?.username ?? '');
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
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
              Text('Добавить фото профиля', style: SeeUTypography.subtitle),
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
      final api = ref.read(apiClientProvider);

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
      }

      final body = <String, dynamic>{
        'full_name': _fullNameCtrl.text.trim(),
        'username': _usernameCtrl.text.trim(),
      };
      if (avatarUrl != null) {
        body['avatar_url'] = avatarUrl;
      }

      final resp = await api.put(ApiEndpoints.me, data: body);
      final data = resp.data;
      final userData = data is Map && data.containsKey('data') ? data['data'] : data;
      final updated = User.fromJson(userData as Map<String, dynamic>);
      if (mounted) {
        // Обновляем authProvider — router redirect в main.dart сам уведёт
        // на /feed, как только fullName перестанет быть пустым.
        ref.read(authProvider.notifier).updateUser(updated);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
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

    return PopScope(
      // Обязательный шаг — системная кнопка "назад" не должна выкидывать
      // из onboarding'а на предыдущий экран.
      canPop: false,
      child: Scaffold(
        backgroundColor: SeeUColors.background,
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                const SizedBox(height: 32),
                Text('Заполните профиль',
                    style: SeeUTypography.displayS
                        .copyWith(color: SeeUColors.textPrimary)),
                const SizedBox(height: 8),
                Text(
                  'Имя и никнейм увидят другие пользователи SeeU',
                  style: SeeUTypography.body.copyWith(color: SeeUColors.textSecondary),
                ),
                const SizedBox(height: 32),

                // Avatar — опционально
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
                              : null,
                          child: _pickedBytes == null
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
                              color: _pickedFile != null
                                  ? SeeUColors.success
                                  : SeeUColors.accent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: SeeUColors.background,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              _pickedFile != null
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
                      _pickedFile != null ? 'Изменить фото' : 'Добавить фото (необязательно)',
                      style: SeeUTypography.body.copyWith(
                        color: SeeUColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                Text('Полное имя',
                    style: SeeUTypography.kicker
                        .copyWith(color: SeeUColors.textTertiary)),
                const SizedBox(height: 6),
                SeeUInput(
                  controller: _fullNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  hintText: 'Как вас зовут?',
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
                const SizedBox(height: 40),

                SeeUButton(
                  label: 'Продолжить',
                  variant: SeeUButtonVariant.primary,
                  isLoading: _isSaving,
                  onTap: _isSaving ? null : _save,
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
