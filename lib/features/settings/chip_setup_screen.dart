import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';

/// Привязка браслета SeeU к аккаунту.
/// Юзер вводит серийный номер с коробки браслета (напр. «SEEU_000001»).
/// POST /users/me/device { serial_number }
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
    final serial = _ctrl.text.trim().toUpperCase();
    if (serial.isEmpty || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      await api.post(ApiEndpoints.myDevice, data: {'serial_number': serial});
      await ref.read(authProvider.notifier).reloadMe();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Браслет «$serial» привязан')),
      );
      context.pop();
    } on DioException catch (e) {
      if (!mounted) return;
      final code = e.response?.statusCode;
      messenger.showSnackBar(
        SnackBar(
          content: Text(code == 409
              ? 'Этот браслет уже привязан к другому аккаунту'
              : code == 404
                  ? 'Браслет не найден — проверьте серийный номер'
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
        title: const Text('Отвязать браслет?'),
        content: const Text(
          'Сканер перестанет показывать вас другим. '
          'Сможете привязать его снова в любой момент.',
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
      messenger.showSnackBar(const SnackBar(content: Text('Браслет отвязан')));
    } on DioException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка: ${apiErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showQRHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Как найти серийный номер'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              '1. Возьмите коробку браслета SeeU.\n'
              '2. Найдите QR-наклейку на боковой стороне.\n'
              '3. Серийный номер указан под QR — например: SEEU_000001.\n'
              '4. Введите его в поле ниже.',
              style: TextStyle(height: 1.5),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final user = ref.watch(authProvider).user;
    final currentSerial = user?.devicePublicId ?? '';
    final hasChip = currentSerial.isNotEmpty;

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
        title: Text('Браслет SeeU',
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
            // Текущий браслет
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
                        Text(hasChip ? 'Привязан' : 'Не привязан',
                            style: TextStyle(color: c.ink2, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(
                          hasChip
                              ? currentSerial
                              : 'Введите серийный номер с браслета',
                          style: TextStyle(
                            fontFamily:
                                hasChip ? 'JetBrains Mono' : null,
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

            Row(
              children: [
                Text(hasChip ? 'Сменить браслет' : 'Привязать браслет',
                    style: SeeUTypography.subtitle
                        .copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(
                  onTap: _showQRHelp,
                  child: Row(
                    children: [
                      Icon(PhosphorIcons.question(), size: 14, color: c.ink3),
                      const SizedBox(width: 4),
                      Text('Где найти?',
                          style: TextStyle(fontSize: 12, color: c.ink3)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Введите серийный номер с QR-наклейки на коробке браслета.',
              style: TextStyle(color: c.ink2, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _ctrl,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'SEEU_000001',
                labelText: 'Серийный номер',
                prefixIcon: Icon(PhosphorIcons.qrCode(), color: c.ink3),
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
                      'После привязки сканер других пользователей увидит вас рядом. '
                      'К одному аккаунту — один браслет; при смене старый освобождается.',
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
