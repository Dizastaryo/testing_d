import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/config/app_config.dart';
import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/blocks_provider.dart';
import '../../core/providers/invites_provider.dart';
import '../../core/providers/profile_badge_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../widgets/share_sheet.dart';
import '_export_download_web.dart' if (dart.library.io) '_export_download_io.dart' as exporter;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final currentThemeMode = ref.watch(themeProvider);
    final isDark = currentThemeMode == ThemeMode.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // Header: glass bar with serif "Настройки"
          SeeUGlassBar(
            titleText: 'Настройки',
            leading: GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                width: 36,
                height: 36,
                color: Colors.transparent,
                child: Icon(
                  PhosphorIcons.caretLeft(),
                  size: 22,
                  color: c.ink,
                ),
              ),
            ),
          ),
          // Body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
              children: [
                _buildSection(
                  title: 'АККАУНТ',
                  items: [
                    _SettingsRowData(
                      icon: PhosphorIcons.pencilSimple(),
                      label: 'Редактировать профиль',
                      value: ref.watch(authProvider).user?.username ?? '',
                      onTap: () => context.push('/profile/edit'),
                    ),
                    _SettingsRowData(
                      icon: PhosphorIcons.shield(),
                      label: 'Заблокированные',
                      value: ref.watch(blocksProvider).maybeWhen(
                            data: (items) => items.isEmpty ? '' : '${items.length}',
                            orElse: () => '',
                          ),
                      onTap: () => context.push('/settings/blocked'),
                    ),
                    // Пункт виден для приватного профиля ИЛИ пока есть
                        // непринятые заявки (снятие приватности при висящих
                        // заявках больше не прячет их из UI). Со счётчиком.
                    if (ref.watch(authProvider).user?.isPrivate == true ||
                        (ref
                                .watch(followRequestsCountProvider)
                                .valueOrNull ??
                            0) >
                            0)
                      _SettingsRowData(
                        icon: PhosphorIcons.usersThree(),
                        label: 'Запросы на подписку',
                        value: () {
                          final n = ref
                                  .watch(followRequestsCountProvider)
                                  .valueOrNull ??
                              0;
                          return n > 0 ? '$n' : '';
                        }(),
                        onTap: () =>
                            context.push('/settings/follow-requests'),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSectionWithToggle(
                  title: 'ПРИВАТНОСТЬ',
                  icon: PhosphorIcons.lock(),
                  label: 'Закрытый профиль',
                  isDark:
                      ref.watch(authProvider).user?.isPrivate ?? false,
                  onToggle: () => _togglePrivate(),
                ),
                const SizedBox(height: 12),
                // PROFILE-6: privacy для last_seen. Когда on — другие зрители
                // не видят «онлайн / был N мин назад» (self видит).
                _buildSectionWithToggle(
                  title: '',
                  icon: PhosphorIcons.eyeSlash(),
                  label: 'Скрыть «был в сети»',
                  isDark:
                      ref.watch(authProvider).user?.hideLastSeen ?? false,
                  onToggle: () => _toggleHideLastSeen(),
                ),
                const SizedBox(height: 24),
                _buildSection(
                  title: 'ЧИП',
                  items: [
                    _SettingsRowData(
                      icon: PhosphorIcons.bluetoothConnected(),
                      label: ref.watch(authProvider).user?.devicePublicId?.isNotEmpty == true
                          ? 'Браслет ${ref.watch(authProvider).user!.devicePublicId}'
                          : 'Браслет не привязан',
                      value: ref.watch(authProvider).user?.devicePublicId?.isNotEmpty == true
                          ? 'управление'
                          : 'привязать',
                      onTap: () => context.push('/settings/chip'),
                    ),
                    _SettingsRowData(
                      icon: PhosphorIcons.ghost(),
                      label: 'Видимость в сканере',
                      value: ref.watch(authProvider).user?.scanEnabled == true
                          ? 'включена'
                          : 'отключена',
                      onTap: () => context.push('/settings/scan-profile'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSectionWithToggle(
                  title: 'ВНЕШНИЙ ВИД',
                  icon: PhosphorIcons.moon(),
                  label: 'Тёмная тема',
                  isDark: isDark,
                  onToggle: () {
                    if (isDark) {
                      ref.read(themeProvider.notifier).setLight();
                    } else {
                      ref.read(themeProvider.notifier).setDark();
                    }
                  },
                ),
                const SizedBox(height: 24),
                _buildSection(
                  title: 'ПРАВОВАЯ ИНФОРМАЦИЯ',
                  items: [
                    _SettingsRowData(
                      icon: PhosphorIcons.shieldCheck(),
                      label: 'Политика конфиденциальности',
                      value: '',
                      onTap: () => _openLegal('${AppConfig.apiOrigin}/privacy'),
                    ),
                    _SettingsRowData(
                      icon: PhosphorIcons.fileText(),
                      label: 'Условия использования',
                      value: '',
                      onTap: () => _openLegal('${AppConfig.apiOrigin}/terms'),
                    ),
                    _SettingsRowData(
                      icon: PhosphorIcons.downloadSimple(),
                      label: 'Скачать мои данные',
                      value: 'JSON',
                      onTap: () => _exportData(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSection(
                  title: 'СЕССИЯ',
                  items: [
                    _SettingsRowData(
                      icon: PhosphorIcons.userPlus(),
                      label: 'Пригласить друга',
                      value: '',
                      onTap: () => _inviteFriend(),
                    ),
                    _SettingsRowData(
                      icon: PhosphorIcons.info(),
                      label: 'Помощь',
                      value: '',
                      onTap: () => _showAbout(context),
                    ),
                    _SettingsRowData(
                      icon: PhosphorIcons.signOut(),
                      label: 'Выйти',
                      value: '',
                      onTap: () async {
                        await ref.read(authProvider.notifier).logout();
                        if (!context.mounted) return;
                        context.go('/login');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildDangerSection(
                  title: 'ОПАСНАЯ ЗОНА',
                  label: 'Удалить аккаунт',
                  icon: PhosphorIcons.trash(),
                  onTap: () => _confirmDeleteAccount(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Editorial section kicker. Empty title renders nothing (fixes the phantom
  /// kicker over the «Скрыть был в сети» toggle).
  Widget _sectionKicker(String title) {
    if (title.trim().isEmpty) return const SizedBox.shrink();
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      child: Text(
        title.toUpperCase(),
        style: SeeUTypography.kicker.copyWith(color: c.ink3),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<_SettingsRowData> items,
  }) {
    final c = context.seeuColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionKicker(title),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(SeeURadii.medium),
            border: Border.all(color: c.line, width: 0.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _SettingsRow(data: items[i]),
                if (i < items.length - 1)
                  Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: c.line,
                    indent: 16,
                    endIndent: 16,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionWithToggle({
    required String title,
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onToggle,
  }) {
    final c = context.seeuColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionKicker(title),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(SeeURadii.medium),
            border: Border.all(color: c.line, width: 0.5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: c.ink2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: SeeUTypography.body,
                  ),
                ),
                GestureDetector(
                  onTap: onToggle,
                  child: _DarkToggle(isDark: isDark),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _togglePrivate() async {
    final auth = ref.read(authProvider.notifier);
    final user = ref.read(authProvider).user;
    if (user == null) return;
    final next = !user.isPrivate;
    // Оптимистично двигаем тумблер (иначе тап «залипает» на время сети),
    // откатываем при ошибке.
    auth.updateUser(user.copyWith(isPrivate: next));
    try {
      final api = ref.read(apiClientProvider);
      await api.put(ApiEndpoints.me, data: {'is_private': next});
      if (!mounted) return;
      showSeeUSnackBar(
        context,
        next
            ? 'Профиль закрыт. Подписки требуют подтверждения.'
            : 'Профиль открыт.',
        tone: SeeUTone.success,
      );
    } on DioException catch (e) {
      auth.updateUser(user); // откат
      if (!mounted) return;
      showSeeUSnackBar(context, 'Не удалось обновить: ${apiErrorMessage(e)}',
          tone: SeeUTone.danger);
    }
  }

  /// PROFILE-6: переключает hide_last_seen. Бэк скрывает is_online +
  /// last_seen_at от других зрителей, владелец продолжает видеть свой
  /// реальный статус.
  Future<void> _toggleHideLastSeen() async {
    final auth = ref.read(authProvider.notifier);
    final user = ref.read(authProvider).user;
    if (user == null) return;
    final next = !user.hideLastSeen;
    auth.updateUser(user.copyWith(hideLastSeen: next));
    try {
      final api = ref.read(apiClientProvider);
      await api.put(ApiEndpoints.me, data: {'hide_last_seen': next});
      if (!mounted) return;
      showSeeUSnackBar(
        context,
        next
            ? 'Статус «был в сети» скрыт от других.'
            : 'Статус «был в сети» виден другим.',
        tone: SeeUTone.success,
      );
    } on DioException catch (e) {
      auth.updateUser(user); // откат
      if (!mounted) return;
      showSeeUSnackBar(context, 'Не удалось обновить: ${apiErrorMessage(e)}',
          tone: SeeUTone.danger);
    }
  }

  Future<void> _inviteFriend() async {
    showSeeUSnackBar(context, 'Создаём код…');
    final code = await ref.read(invitesProvider.notifier).createCode();
    if (!mounted) return;
    if (code == null) {
      showSeeUSnackBar(context, 'Не удалось создать инвайт',
          tone: SeeUTone.danger);
      return;
    }
    final url = 'https://seeu.app/?invite=$code';
    // ignore: use_build_context_synchronously
    await showShareSheet(
      context: context,
      url: url,
      title: 'Пригласить друга в SeeU',
      subtitle: 'Код: $code',
    );
  }

  Future<void> _exportData() async {
    showSeeUSnackBar(context, 'Готовим экспорт…');
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.get(ApiEndpoints.exportMe);
      final bytes = utf8.encode(jsonEncode(r.data));
      await exporter.saveExport(bytes: bytes, filename: 'seeu-export.json');
      if (!mounted) return;
      showSeeUSnackBar(context, kIsWeb ? 'Файл скачан' : 'Файл сохранён',
          tone: SeeUTone.success);
    } catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Не удалось экспортировать: $e',
          tone: SeeUTone.danger);
    }
  }

  Future<void> _openLegal(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Не удалось открыть страницу',
          tone: SeeUTone.danger);
    }
  }

  Widget _buildDangerSection({
    required String title,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final c = context.seeuColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionKicker(title),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(SeeURadii.medium),
            border: Border.all(color: SeeUColors.error.withValues(alpha: 0.3), width: 0.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Tappable.faded(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: SeeUColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(PhosphorIcons.trash(), size: 18, color: SeeUColors.error),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: SeeUTypography.body.copyWith(color: SeeUColors.error),
                    ),
                  ),
                  Icon(icon, size: 14, color: SeeUColors.error),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showSeeUConfirm(
      context,
      title: 'Удалить аккаунт?',
      message:
          'Это действие безвозвратно удалит ваш аккаунт, все посты, истории, '
          'комментарии, лайки, подписки и сообщения. Восстановить будет нельзя.',
      confirmLabel: 'Удалить',
      destructive: true,
      icon: PhosphorIcons.trash(),
    );
    if (!confirmed || !context.mounted) return;

    // Второй барьер для необратимого действия: ввод слова-подтверждения.
    final typed = await _promptDeleteConfirmation(context);
    if (typed != true || !context.mounted) return;

    try {
      await ref.read(authProvider.notifier).deleteAccount();
      if (!context.mounted) return;
      showSeeUSnackBar(context, 'Аккаунт удалён', tone: SeeUTone.success);
      context.go('/login');
    } on DioException catch (e) {
      if (!context.mounted) return;
      showSeeUSnackBar(context, 'Не удалось удалить аккаунт: ${apiErrorMessage(e)}',
          tone: SeeUTone.danger);
    } catch (_) {
      if (!context.mounted) return;
      showSeeUSnackBar(context, 'Не удалось удалить аккаунт',
          tone: SeeUTone.danger);
    }
  }

  /// Type-to-confirm: пользователь вводит «УДАЛИТЬ», чтобы точно не удалить
  /// аккаунт случайным двойным тапом по одному диалогу.
  Future<bool?> _promptDeleteConfirmation(BuildContext context) {
    final ctrl = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (dctx) {
        final c = dctx.seeuColors;
        return StatefulBuilder(builder: (dctx, setLocal) {
          final ok = ctrl.text.trim().toUpperCase() == 'УДАЛИТЬ';
          return AlertDialog(
            backgroundColor: c.surface,
            title: Text('Подтвердите удаление',
                style: SeeUTypography.subtitle.copyWith(color: c.ink)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Введите слово УДАЛИТЬ, чтобы подтвердить.',
                    style: SeeUTypography.caption.copyWith(color: c.ink2)),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  onChanged: (_) => setLocal(() {}),
                  decoration: const InputDecoration(hintText: 'УДАЛИТЬ'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dctx).pop(false),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: ok ? () => Navigator.of(dctx).pop(true) : null,
                child: Text('Удалить',
                    style: TextStyle(
                        color: ok ? SeeUColors.error : c.ink4)),
              ),
            ],
          );
        });
      },
    ).whenComplete(ctrl.dispose);
  }

  void _showAbout(BuildContext context) {
    showSeeUBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('SeeU',
                  style: SeeUTypography.displayL
                      .copyWith(fontFamily: AppFonts.I.brand, letterSpacing: 0)),
              const SizedBox(height: 8),
              Text(
                'Социальная сеть с BLE-сканером',
                style: SeeUTypography.body.copyWith(color: context.seeuColors.ink2),
              ),
              const SizedBox(height: 4),
              Text(
                'Версия 1.0.0',
                style: SeeUTypography.caption,
              ),
              const SizedBox(height: 24),
              Text(
                'Находите людей рядом, делитесь моментами, общайтесь.',
                style: SeeUTypography.body.copyWith(color: context.seeuColors.ink2),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SeeUButton(
                label: 'Закрыть',
                variant: SeeUButtonVariant.secondary,
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsRowData {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SettingsRowData({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });
}

class _SettingsRow extends StatelessWidget {
  final _SettingsRowData data;

  const _SettingsRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.faded(
      onTap: data.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(data.icon, size: 16, color: c.ink2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                data.label,
                style: SeeUTypography.body,
              ),
            ),
            if (data.value.isNotEmpty) ...[
              Text(
                data.value,
                style: SeeUTypography.caption.copyWith(
                  color: c.ink3,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Icon(
              PhosphorIcons.caretRight(),
              size: 14,
              color: c.ink4,
            ),
          ],
        ),
      ),
    );
  }
}

// Custom 44x26 toggle switch matching the design (coral when on, ink-4 when off)
class _DarkToggle extends StatelessWidget {
  final bool isDark;

  const _DarkToggle({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44,
      height: 26,
      decoration: BoxDecoration(
        color: isDark ? SeeUColors.accent : SeeUColors.textQuaternary,
        borderRadius: BorderRadius.circular(SeeURadii.pill),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            top: 2,
            left: isDark ? 20 : 2,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
