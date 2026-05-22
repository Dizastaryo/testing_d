import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';

/// Screen для привязки/отвязки BLE-метки (ESP32C3) к аккаунту.
/// Юзер либо вводит публичный ID руками (с коробки/QR-наклейки), либо в
/// будущем сканирует QR. Привязка идёт через `POST /users/me/device`.
class ChipSetupScreen extends ConsumerStatefulWidget {
  const ChipSetupScreen({super.key});

  @override
  ConsumerState<ChipSetupScreen> createState() => _ChipSetupScreenState();
}

class _ChipSetupScreenState extends ConsumerState<ChipSetupScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _bind() async {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      await api.post(ApiEndpoints.myDevice, data: {'device_public_id': raw});
      // Refresh /me so settings reflects the new chip.
      await ref.read(authProvider.notifier).reloadMe();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Чип «$raw» привязан')),
      );
      context.pop();
    } on DioException catch (e) {
      if (!mounted) return;
      final code = e.response?.statusCode;
      messenger.showSnackBar(
        SnackBar(
          content: Text(code == 409
              ? 'Этот чип уже привязан к другому аккаунту'
              : 'Не удалось привязать: ${apiErrorMessage(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unbind() async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отвязать чип?'),
        content: const Text(
          'Сканер перестанет показывать ваш профиль другим. Можете привязать его снова в любой момент.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Отвязать')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      await api.delete(ApiEndpoints.myDevice);
      await ref.read(authProvider.notifier).reloadMe();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Чип отвязан')));
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
    final user = ref.watch(authProvider).user;
    final currentChip = user?.devicePublicId ?? '';
    final hasChip = currentChip.isNotEmpty;

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
        title: Text('Чип',
            style: TextStyle(
                fontFamily: 'Fraunces',
                fontWeight: FontWeight.w400,
                fontSize: 22,
                color: c.ink)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Текущий чип
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
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: hasChip
                          ? SeeUColors.accent.withValues(alpha: 0.12)
                          : c.surface2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      PhosphorIcons.bluetoothConnected(),
                      color: hasChip ? SeeUColors.accent : c.ink3,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(hasChip ? 'Текущий чип' : 'Чип не привязан',
                            style: TextStyle(color: c.ink2, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(
                          hasChip ? currentChip : 'Привяжите свой ESP32C3 ниже',
                          style: TextStyle(
                            fontFamily: hasChip ? 'JetBrains Mono' : null,
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasChip)
                    TextButton(
                      onPressed: _busy ? null : _unbind,
                      style: TextButton.styleFrom(
                        foregroundColor: SeeUColors.error,
                      ),
                      child: const Text('Отвязать'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Привязать новый
            Text(hasChip ? 'Сменить чип' : 'Привязать чип',
                style: SeeUTypography.subtitle
                    .copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Введите публичный ID, напечатанный на коробке или наклейке чипа. '
              'Например: «DEVICE_0001».',
              style: TextStyle(color: c.ink2, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'DEVICE_XXXX',
                prefixIcon: Icon(PhosphorIcons.qrCode(),
                    color: c.ink3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SeeUButton(
              label: hasChip ? 'Привязать новый' : 'Привязать',
              isLoading: _busy,
              onTap: _busy ? null : _bind,
            ),

            const SizedBox(height: 32),
            // Помощь
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(PhosphorIcons.info(), size: 18, color: c.ink3),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'После привязки сканер других пользователей сможет '
                      'найти вас рядом по этому чипу. К одному аккаунту можно '
                      'привязать только один чип; перепривязка освобождает старый.',
                      style: TextStyle(
                          color: c.ink2, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
