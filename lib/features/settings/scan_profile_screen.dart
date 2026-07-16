import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';

/// Экран настройки видимости в BLE-сканере.
/// PUT /users/me/scan-profile { scan_enabled }
class ScanProfileScreen extends ConsumerStatefulWidget {
  const ScanProfileScreen({super.key});

  @override
  ConsumerState<ScanProfileScreen> createState() => _ScanProfileScreenState();
}

class _ScanProfileScreenState extends ConsumerState<ScanProfileScreen> {
  bool _scanEnabled = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scanEnabled = ref.read(authProvider).user?.scanEnabled ?? true;
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.put(ApiEndpoints.myScanProfile, data: {
        'scan_enabled': _scanEnabled,
      });
      await ref.read(authProvider.notifier).reloadMe();
      if (!mounted) return;
      showSeeUSnackBar(context, 'Настройки сохранены', tone: SeeUTone.success);
      context.pop();
    } on DioException catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Ошибка: ${apiErrorMessage(e)}',
          tone: SeeUTone.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SeeUGlassBar(
            titleText: 'Видимость в сканере',
            kicker: 'СКАНЕР',
            leading: Tappable.scaled(
              onTap: () => context.pop(),
              scaleFactor: 0.9,
              child: SizedBox(
                width: 40,
                height: 40,
                child:
                    Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
              ),
            ),
          ),
          Expanded(
            child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(SeeURadii.medium),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(PhosphorIcons.shieldCheck(),
                      size: 18, color: SeeUColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Когда видимость включена, люди рядом видят вашу '
                      'анонимную карточку (фото и никнейм карточки), не '
                      'связанную с профилем — имя и аккаунт не раскрываются.',
                      style: SeeUTypography.caption
                          .copyWith(color: c.ink2, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Toggle
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(SeeURadii.medium),
                border: Border.all(color: c.line, width: 0.5),
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
                            style: SeeUTypography.body
                                .copyWith(fontWeight: FontWeight.w600, color: c.ink)),
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
                  Switch.adaptive(
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
              label: _busy ? 'Сохранение...' : 'Сохранить',
              isLoading: _busy,
              onTap: _busy ? null : _save,
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
