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
          // Header: back chevron + serif "Настройки", border-bottom
          SafeArea(
            bottom: false,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: c.line,
                    width: 0.5,
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(4, 10, 16, 10),
              child: Row(
                children: [
                  GestureDetector(
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
                  const SizedBox(width: 4),
                  Text(
                    'Настройки',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontSize: 24,
                      fontWeight: FontWeight.w400,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 100),
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
                    if (ref.watch(authProvider).user?.isPrivate == true)
                      _SettingsRowData(
                        icon: PhosphorIcons.usersThree(),
                        label: 'Запросы на подписку',
                        value: '',
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
                          ? 'Чип ${ref.watch(authProvider).user!.devicePublicId}'
                          : 'Чип не привязан',
                      value: ref.watch(authProvider).user?.devicePublicId?.isNotEmpty == true
                          ? 'управление'
                          : 'привязать',
                      onTap: () => context.push('/settings/chip'),
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

  Widget _buildSection({
    required String title,
    required List<_SettingsRowData> items,
  }) {
    final c = context.seeuColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Text(
            title,
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 10,
              fontWeight: FontWeight.w400,
              letterSpacing: 1.0,
              color: c.ink3,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Text(
            title,
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 10,
              fontWeight: FontWeight.w400,
              letterSpacing: 1.0,
              color: c.ink3,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
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
    final cur = ref.read(authProvider).user?.isPrivate ?? false;
    final next = !cur;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      await api.put(ApiEndpoints.me, data: {'is_private': next});
      await ref.read(authProvider.notifier).reloadMe();
      messenger.showSnackBar(SnackBar(
        content: Text(
            next ? 'Профиль закрыт. Подписки требуют подтверждения.' : 'Профиль открыт.'),
      ));
    } on DioException catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Не удалось обновить: ${apiErrorMessage(e)}')));
    }
  }

  /// PROFILE-6: переключает hide_last_seen. Бэк скрывает is_online +
  /// last_seen_at от других зрителей, владелец продолжает видеть свой
  /// реальный статус.
  Future<void> _toggleHideLastSeen() async {
    final cur = ref.read(authProvider).user?.hideLastSeen ?? false;
    final next = !cur;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      await api.put(ApiEndpoints.me, data: {'hide_last_seen': next});
      await ref.read(authProvider.notifier).reloadMe();
      messenger.showSnackBar(SnackBar(
        content: Text(next
            ? 'Статус «был в сети» скрыт от других.'
            : 'Статус «был в сети» виден другим.'),
      ));
    } on DioException catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Не удалось обновить: ${apiErrorMessage(e)}')));
    }
  }

  Future<void> _inviteFriend() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Создаём код…')));
    final code = await ref.read(invitesProvider.notifier).createCode();
    if (!context.mounted) return;
    if (code == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Не удалось создать инвайт')),
      );
      return;
    }
    if (!mounted) return;
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
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Готовим экспорт…')));
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.get(ApiEndpoints.exportMe);
      final bytes = utf8.encode(jsonEncode(r.data));
      await exporter.saveExport(bytes: bytes, filename: 'seeu-export.json');
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(kIsWeb ? 'Файл скачан' : 'Файл сохранён')),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Не удалось экспортировать: $e')));
    }
  }

  Future<void> _openLegal(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть страницу')),
      );
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
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Text(
            title,
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 10,
              fontWeight: FontWeight.w400,
              letterSpacing: 1.0,
              color: c.ink3,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE74C3C).withValues(alpha: 0.3), width: 0.5),
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
                      color: const Color(0xFFE74C3C).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.delete_forever, size: 18, color: Color(0xFFE74C3C)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: SeeUTypography.body.copyWith(color: const Color(0xFFE74C3C)),
                    ),
                  ),
                  Icon(icon, size: 14, color: const Color(0xFFE74C3C)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final c = context.seeuColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('Удалить аккаунт?'),
        content: const Text(
          'Это действие безвозвратно удалит ваш аккаунт, все посты, истории, '
          'комментарии, лайки, подписки и сообщения. Восстановить будет нельзя.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE74C3C)),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(authProvider.notifier).deleteAccount();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Аккаунт удалён')),
      );
      context.go('/login');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить аккаунт: $e')),
      );
    }
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
              Text('SeeU', style: SeeUTypography.displayL),
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
