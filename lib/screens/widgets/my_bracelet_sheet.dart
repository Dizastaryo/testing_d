import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';
import '../../features/card/card_warning_screen.dart' show CardGlassBar;
import '../../models/ble_device_model.dart';
import 'chip_control_sheet_wrapper.dart';

/// Полноэкранная страница «Браслет» — управление видимостью и режимом.
///
/// Два уровня:
///   1. Сервер: `scan_enabled` — видят ли тебя рядом (работает всегда).
///   2. Браслет (GATT): режим Общий / Приватный — записывается в чип, поэтому
///      требует, чтобы твой браслет был найден в живом BLE-скане рядом.
/// Поэтому страница открывается ИЗ сканера и получает карту найденных устройств.
class BraceletScreen extends ConsumerStatefulWidget {
  final Map<String, BleDeviceModel> devicesMap;
  const BraceletScreen({super.key, required this.devicesMap});

  @override
  ConsumerState<BraceletScreen> createState() => _BraceletScreenState();
}

class _BraceletScreenState extends ConsumerState<BraceletScreen> {
  bool _busy = false;

  /// Свой браслет среди найденных рядом. Сверяем И public, И private id:
  /// в приватном режиме (0x01) чип вещает private_id, и по одному только
  /// public_id свой браслет не находился — режим было не сменить (лок-аут).
  BleDeviceModel? get _ownDevice {
    final u = ref.read(authProvider).user;
    final myPublic = u?.devicePublicId?.toLowerCase() ?? '';
    final myPrivate = u?.devicePrivateId?.toLowerCase() ?? '';
    if (myPublic.isEmpty && myPrivate.isEmpty) return null;
    for (final d in widget.devicesMap.values) {
      final id = d.seeuPacket?.idHex.toLowerCase() ?? '';
      if (id.isEmpty) continue;
      if ((myPublic.isNotEmpty && id == myPublic) ||
          (myPrivate.isNotEmpty && id == myPrivate)) {
        return d;
      }
    }
    return null;
  }

  Future<void> _toggleVisibility() async {
    if (_busy) return;
    final user = ref.read(authProvider).user;
    if (user == null) return;
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.put(ApiEndpoints.myScanProfile, data: {
        'scan_enabled': !user.scanEnabled,
      });
      await ref.read(authProvider.notifier).reloadMe();
    } on DioException catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, apiErrorMessage(e), tone: SeeUTone.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Режим пишется в чип по BLE — нужен свой браслет в радиусе.
  void _openMode() {
    final own = _ownDevice;
    if (own?.bleDevice == null) {
      showSeeUSnackBar(
        context,
        'Браслет не найден рядом. Включи Bluetooth и держи браслет при себе.',
        tone: SeeUTone.danger,
      );
      return;
    }
    HapticFeedback.selectionClick();
    showSeeUBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChipControlSheetWrapper(device: own!.bleDevice!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final user = ref.watch(authProvider).user;
    final scanEnabled = user?.scanEnabled ?? true;
    final hasDevice = (user?.devicePublicId ?? '').isNotEmpty;
    final foundNearby = hasDevice && _ownDevice != null;

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          CardGlassBar(
            kicker: 'УПРАВЛЕНИЕ',
            title: 'Браслет',
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              children: [
                _hero(c, scanEnabled, hasDevice),
                const SizedBox(height: 14),
                _statusRow(c, hasDevice, foundNearby),
                const SizedBox(height: 20),
                _modeSection(c, foundNearby),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero: «Тебя видят рядом» + тумблер ────────────────────────────────────

  Widget _hero(SeeUThemeColors c, bool scanEnabled, bool hasDevice) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF1EB), Color(0xFFFFE1D6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFFFFD4C6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BroadcastHaloIcon(active: scanEnabled && hasDevice),
              const Spacer(),
              _toggle(scanEnabled && hasDevice, hasDevice),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            scanEnabled && hasDevice ? 'Тебя видят рядом' : 'Ты скрыт в сканере',
            style: SeeUTypography.displayS.copyWith(
              fontSize: 27,
              height: 1.05,
              color: const Color(0xFF161310),
            ),
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: 270,
            child: Text(
              hasDevice
                  ? 'Люди в паре метров видят твою карточку. Выключи — и ты '
                      'станешь невидимым в сканере.'
                  : 'Привяжи браслет, чтобы появляться в сканере у людей рядом.',
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: Color(0xFF8A5546),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Тумблер 56×32 из дизайна.
  Widget _toggle(bool on, bool enabled) {
    return GestureDetector(
      onTap: enabled && !_busy ? _toggleVisibility : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 56,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: on ? SeeUColors.accent : const Color(0xFFD9CFC5),
          boxShadow: on
              ? [
                  BoxShadow(
                    color: SeeUColors.accent.withValues(alpha: 0.42),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: _busy
                ? const SizedBox(
                    width: 26,
                    height: 26,
                    child: Padding(
                      padding: EdgeInsets.all(5),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                  )
                : Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ── Статус браслета ───────────────────────────────────────────────────────

  Widget _statusRow(SeeUThemeColors c, bool hasDevice, bool foundNearby) {
    final ok = hasDevice;
    final color = ok ? SeeUColors.success : c.ink3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line, width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
            ),
            alignment: Alignment.center,
            child: Icon(
              ok ? PhosphorIconsBold.check : PhosphorIconsBold.x,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ok ? 'Браслет привязан' : 'Браслет не привязан',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: c.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  !ok
                      ? 'Привяжи браслет в настройках'
                      : foundNearby
                          ? 'Найден рядом · синхронизирован'
                          : 'Не найден рядом · включи Bluetooth',
                  style: TextStyle(fontSize: 12.5, color: c.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Режим (GATT) ──────────────────────────────────────────────────────────

  Widget _modeSection(SeeUThemeColors c, bool foundNearby) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Режим',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: c.ink)),
            Text('кто может тебя видеть',
                style: TextStyle(fontSize: 12, color: c.ink3)),
          ],
        ),
        const SizedBox(height: 9),
        // Раньше здесь был псевдо-сегмент «Общий/Приватный» с ЗАХАРДКОЖЕННЫМ
        // active (всегда «Общий»), не читавший реальный режим чипа — вводил в
        // заблуждение. Заменён на кнопку, открывающую ChipControlSheet, где
        // режим читается по BLE и виден фактическим.
        GestureDetector(
          onTap: _openMode,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1EBE1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(PhosphorIcons.slidersHorizontal(), size: 18, color: c.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Настроить режим',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.ink)),
                      Text('общий · приватный · выключен',
                          style: TextStyle(fontSize: 11.5, color: c.ink3)),
                    ],
                  ),
                ),
                Icon(PhosphorIcons.caretRight(), size: 16, color: c.ink3),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          foundNearby
              ? 'Режим записывается прямо в чип браслета.'
              : 'Чтобы сменить режим, браслет должен быть рядом (BLE).',
          style: TextStyle(fontSize: 11.5, color: c.ink3),
        ),
      ],
    );
  }

}

/// Иконка вещания с двумя расходящимися halo-кольцами (скруглённый квадрат).
class _BroadcastHaloIcon extends StatefulWidget {
  final bool active;
  const _BroadcastHaloIcon({required this.active});

  @override
  State<_BroadcastHaloIcon> createState() => _BroadcastHaloIconState();
}

class _BroadcastHaloIconState extends State<_BroadcastHaloIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.active)
            AnimatedBuilder(
              animation: _c,
              builder: (_, __) => Stack(
                alignment: Alignment.center,
                children: List.generate(2, (i) {
                  final phase = (_c.value + i * 0.5) % 1.0;
                  final scale = 0.82 + (1.55 - 0.82) * phase;
                  final opacity = (0.55 * (1 - phase)).clamp(0.0, 0.55);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              SeeUColors.accent.withValues(alpha: opacity),
                          width: 1.5,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: SeeUColors.accent.withValues(alpha: 0.2),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(
              PhosphorIconsFill.broadcast,
              size: 26,
              color: widget.active
                  ? SeeUColors.accent
                  : context.seeuColors.ink3,
            ),
          ),
        ],
      ),
    );
  }
}
