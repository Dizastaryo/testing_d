import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';
import '../../models/ble_device_model.dart';
import '../widgets/chip_control_sheet_wrapper.dart';

/// Шторка «Мой браслет» в экране сканера.
/// Управляет видимостью двумя способами:
///   1. Server-side toggle: scan_enabled (всегда доступно)
///   2. GATT write: режим браслета (Общий / Приватный / Выключить) —
///      только если свой браслет виден в BLE-сканировании рядом.
class MyBraceletSheet extends ConsumerStatefulWidget {
  /// Текущая карта найденных BLE-устройств от ScannerScreen.
  final Map<String, BleDeviceModel> devicesMap;

  const MyBraceletSheet({super.key, required this.devicesMap});

  @override
  ConsumerState<MyBraceletSheet> createState() => _MyBraceletSheetState();
}

class _MyBraceletSheetState extends ConsumerState<MyBraceletSheet> {
  bool _serverBusy = false;

  /// Ищет собственный браслет в списке найденных устройств по publicIdHex.
  BleDeviceModel? get _ownDevice {
    final myId =
        ref.read(authProvider).user?.devicePublicId?.toLowerCase() ?? '';
    if (myId.isEmpty) return null;
    for (final d in widget.devicesMap.values) {
      if (d.seeuPacket?.idHex.toLowerCase() == myId) return d;
    }
    return null;
  }

  Future<void> _toggleServerVisibility() async {
    if (_serverBusy) return;
    final user = ref.read(authProvider).user;
    if (user == null) return;

    setState(() => _serverBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      final newEnabled = !user.scanEnabled;
      await api.put(ApiEndpoints.myScanProfile, data: {
        'scan_enabled': newEnabled,
      });
      await ref.read(authProvider.notifier).reloadMe();
    } on DioException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка: ${apiErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _serverBusy = false);
    }
  }

  void _openGattSheet(BleDeviceModel device) {
    Navigator.pop(context);
    showSeeUBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChipControlSheetWrapper(device: device.bleDevice!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final user = ref.watch(authProvider).user;
    final scanEnabled = user?.scanEnabled ?? true;
    final hasDevice = (user?.devicePublicId ?? '').isNotEmpty;
    final ownDevice = hasDevice ? _ownDevice : null;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scanEnabled
                      ? SeeUColors.accent.withValues(alpha: 0.1)
                      : c.surface2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  PhosphorIcons.bluetoothConnected(),
                  size: 20,
                  color: scanEnabled ? SeeUColors.accent : c.ink3,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Мой браслет',
                      style: SeeUTypography.displayXS
                          .copyWith(fontWeight: FontWeight.w600, color: c.ink)),
                  Text(
                    hasDevice
                        ? (scanEnabled ? 'Видим в сканере' : 'Скрыт в сканере')
                        : 'Браслет не привязан',
                    style: SeeUTypography.caption.copyWith(
                      color: scanEnabled && hasDevice
                          ? SeeUColors.success
                          : c.ink3,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Layer 3: Server-side visibility ──────────────────────────────
          _sectionLabel('Сервер · всегда работает', c),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Видимость в сканере',
                          style: SeeUTypography.body
                              .copyWith(fontWeight: FontWeight.w600, color: c.ink)),
                      const SizedBox(height: 2),
                      Text(
                        scanEnabled
                            ? 'Другие видят тебя рядом'
                            : 'Ты скрыт(а) от всех',
                        style: SeeUTypography.caption.copyWith(color: c.ink3),
                      ),
                    ],
                  ),
                ),
                _serverBusy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: SeeUColors.accent))
                    : Switch(
                        value: scanEnabled,
                        onChanged: hasDevice
                            ? (_) => _toggleServerVisibility()
                            : null,
                        activeThumbColor: SeeUColors.accent,
                        activeTrackColor:
                            SeeUColors.accent.withValues(alpha: 0.4),
                      ),
              ],
            ),
          ),

          if (!hasDevice) ...[
            const SizedBox(height: 12),
            _InfoBanner(
              text: 'Привяжите браслет в настройках для управления видимостью.',
              c: c,
            ),
          ],

          const SizedBox(height: 20),

          // ── Layer 2: GATT / BLE mode ─────────────────────────────────────
          _sectionLabel('Браслет · BLE-управление', c),
          const SizedBox(height: 8),

          if (!hasDevice)
            _InfoBanner(
                text: 'Нет привязанного браслета.', c: c)
          else if (ownDevice == null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.line),
              ),
              child: Row(
                children: [
                  Icon(PhosphorIcons.waveform(), size: 18, color: c.ink3),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Браслет не найден рядом.\nПоднесите браслет ближе.',
                      style: SeeUTypography.caption.copyWith(
                          color: c.ink3, height: 1.4),
                    ),
                  ),
                ],
              ),
            )
          else
            GestureDetector(
              onTap: ownDevice.bleDevice != null
                  ? () => _openGattSheet(ownDevice)
                  : null,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: SeeUColors.accent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: SeeUColors.accent.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: SeeUColors.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(PhosphorIcons.bluetooth(),
                          size: 18, color: SeeUColors.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Браслет рядом · управление режимом',
                              style: SeeUTypography.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: SeeUColors.accent)),
                          const SizedBox(height: 2),
                          Text(
                            'Общий / Приватный / Выключить',
                            style: SeeUTypography.caption
                                .copyWith(color: SeeUColors.accent.withValues(alpha: 0.7)),
                          ),
                        ],
                      ),
                    ),
                    Icon(PhosphorIcons.caretRight(),
                        size: 16, color: SeeUColors.accent),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 20),

          // ── Scan-profile link ─────────────────────────────────────────────
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              context.push('/settings/scan-profile');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(SeeURadii.small),
              ),
              child: Row(
                children: [
                  Icon(PhosphorIcons.ghost(), size: 18, color: c.ink3),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Редактировать scan-профиль',
                        style: SeeUTypography.body.copyWith(color: c.ink2)),
                  ),
                  Icon(PhosphorIcons.caretRight(),
                      size: 14, color: c.ink3),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, SeeUThemeColors c) => Text(
        text.toUpperCase(),
        style: SeeUTypography.monoLabel.copyWith(
            color: c.ink4, fontSize: 10, letterSpacing: 0.8),
      );
}

class _InfoBanner extends StatelessWidget {
  final String text;
  final SeeUThemeColors c;
  const _InfoBanner({required this.text, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(SeeURadii.small),
        border: Border.all(color: c.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIcons.info(), size: 15, color: c.ink3),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: SeeUTypography.caption.copyWith(
                    color: c.ink3, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
