import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/theme_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
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
                    color: SeeUColors.borderSubtle,
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
                        color: SeeUColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Настройки',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 24,
                      fontWeight: FontWeight.w400,
                      color: SeeUColors.textPrimary,
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
                  title: 'ПРИВАТНОСТЬ',
                  items: [
                    _SettingsRowData(
                      icon: PhosphorIcons.pencilSimple(),
                      label: 'Псевдоним',
                      value: ref.watch(authProvider).user?.username ?? '',
                      onTap: () => _showComingSoon(context),
                    ),
                    _SettingsRowData(
                      icon: PhosphorIcons.image(),
                      label: 'Фото-маска',
                      value: 'установлено',
                      onTap: () => _showComingSoon(context),
                    ),
                    _SettingsRowData(
                      icon: PhosphorIcons.eye(),
                      label: 'Видимость в радаре',
                      value: 'только публичные места',
                      onTap: () => _showComingSoon(context),
                    ),
                    _SettingsRowData(
                      icon: PhosphorIcons.shield(),
                      label: 'Заблокированные',
                      value: '0',
                      onTap: () => _showComingSoon(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSection(
                  title: 'ЧИП',
                  items: [
                    _SettingsRowData(
                      icon: PhosphorIcons.bluetoothConnected(),
                      label: 'ESP32C3_TAG · DEVICE_0001',
                      value: 'подключен',
                      onTap: () => _showComingSoon(context),
                    ),
                    _SettingsRowData(
                      icon: PhosphorIcons.qrCode(),
                      label: 'Привязать новый чип',
                      value: 'отсканировать QR',
                      onTap: () => _showComingSoon(context),
                    ),
                    _SettingsRowData(
                      icon: PhosphorIcons.lock(),
                      label: 'Авто-выкл когда один',
                      value: 'вкл',
                      onTap: () => _showComingSoon(context),
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
                  title: 'АККАУНТ',
                  items: [
                    _SettingsRowData(
                      icon: PhosphorIcons.bell(),
                      label: 'Пуш-уведомления',
                      value: '',
                      onTap: () => _showComingSoon(context),
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
                        if (!mounted) return;
                        context.go('/login');
                      },
                    ),
                  ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Text(
            title,
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 10,
              fontWeight: FontWeight.w400,
              letterSpacing: 1.0,
              color: SeeUColors.textTertiary,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: SeeUColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SeeUColors.borderSubtle, width: 0.5),
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
                    color: SeeUColors.borderSubtle,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Consolas',
              fontSize: 10,
              fontWeight: FontWeight.w400,
              letterSpacing: 1.0,
              color: SeeUColors.textTertiary,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: SeeUColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SeeUColors.borderSubtle, width: 0.5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: SeeUColors.surface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: SeeUColors.textSecondary),
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

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Скоро будет доступно')),
    );
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
                style: SeeUTypography.body.copyWith(color: SeeUColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                'Версия 1.0.0',
                style: SeeUTypography.caption,
              ),
              const SizedBox(height: 24),
              Text(
                'Находите людей рядом, делитесь моментами, общайтесь.',
                style: SeeUTypography.body.copyWith(color: SeeUColors.textSecondary),
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
                color: SeeUColors.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(data.icon, size: 16, color: SeeUColors.textSecondary),
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
                  color: SeeUColors.textTertiary,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Icon(
              PhosphorIcons.caretRight(),
              size: 14,
              color: SeeUColors.textQuaternary,
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
