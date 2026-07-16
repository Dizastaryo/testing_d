import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../core/design/design.dart';
import '../core/providers/auth_provider.dart';
import '../services/chip_control_service.dart';

class ChipControlSheet extends ConsumerStatefulWidget {
  final BluetoothDevice device;

  const ChipControlSheet({super.key, required this.device});

  @override
  ConsumerState<ChipControlSheet> createState() => _ChipControlSheetState();
}

class _ChipControlSheetState extends ConsumerState<ChipControlSheet> {
  final _service = ChipControlService();
  ChipInfo? _chipInfo;
  int? _currentMode;
  String? _error;
  bool _loading = true;
  StreamSubscription<int>? _modeSub;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      final info = await _service.connectAndRead(widget.device);

      // PROFILE-2 (c): owner verification через authProvider (раньше был
      // AccountSession.instance — legacy mock). User.devicePublicId — hex
      // строка из БД, сравниваем с тем что чип шлёт по BLE.
      final myDeviceId =
          ref.read(authProvider).user?.devicePublicId ?? '';
      if (info.publicIdHex.toLowerCase() != myDeviceId.toLowerCase()) {
        await _service.disconnect();
        if (mounted) {
          setState(() {
            _error = 'Это не твой чип';
            _loading = false;
          });
        }
        return;
      }

      _modeSub = _service.modeStream.listen((mode) {
        if (mounted) setState(() => _currentMode = mode);
      });

      if (mounted) {
        setState(() {
          _chipInfo = info;
          _currentMode = info.currentMode;
          _loading = false;
        });
      }
    } on ChipControlException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Ошибка: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _setMode(int mode) async {
    try {
      await _service.setMode(mode);
      if (mounted) setState(() => _currentMode = mode);
    } on ChipControlException catch (e) {
      if (mounted) {
        showSeeUSnackBar(context, e.message, tone: SeeUTone.danger);
      }
    }
  }

  @override
  void dispose() {
    _modeSub?.cancel();
    // Async-cleanup сервиса fire-and-forget (State.dispose синхронный) —
    // сам сервис теперь корректно рвёт GATT-линк даже если connect ещё висит.
    unawaited(_service.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final avatarLetter = (user?.username.isNotEmpty == true)
        ? user!.username[0].toUpperCase()
        : '?';

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: SeeUColors.accentSoft,
                backgroundImage:
                    (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty)
                        ? NetworkImage(user.avatarUrl!)
                        : null,
                child: (user?.avatarUrl == null || user!.avatarUrl!.isEmpty)
                    ? Text(
                        avatarLetter,
                        style: TextStyle(
                          color: SeeUColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Твой SeeU',
                      style: SeeUTypography.displayS.copyWith(
                        fontWeight: FontWeight.w600,
                        color: SeeUColors.textPrimary,
                      ),
                    ),
                    Text(
                      _loading
                          ? 'Подключение...'
                          : _error != null
                              ? _error!
                              : 'Подключено',
                      style: SeeUTypography.caption.copyWith(
                        color: _error != null
                            ? SeeUColors.error
                            : _loading
                                ? SeeUColors.textTertiary
                                : SeeUColors.success,
                      ),
                    ),
                  ],
                ),
              ),
              if (_chipInfo != null)
                Text(
                  'PROTO-${_chipInfo!.protoIndex.toString().padLeft(3, '0')}',
                  style: SeeUTypography.mono,
                ),
            ],
          ),
          const SizedBox(height: 24),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: CircularProgressIndicator(color: SeeUColors.accent),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Icon(
                PhosphorIcons.warning(PhosphorIconsStyle.fill),
                color: SeeUColors.error,
                size: 48,
              ),
            )
          else ...[
            // Если браслет выключен кнопкой — показываем статус
            if (_currentMode == 0xFF) ...[
              _OffBadge(),
              const SizedBox(height: 10),
            ],
            // Только два режима — OFF управляется физической кнопкой на браслете
            _ModeButton(
              label: 'Общий',
              subtitle: 'Все видят тебя в сканере',
              icon: PhosphorIcons.broadcast(PhosphorIconsStyle.fill),
              color: const Color(0xFF5DCAA5),
              isActive: _currentMode == 0x00,
              onTap: _currentMode == 0xFF ? null : () => _setMode(0x00),
            ),
            const SizedBox(height: 10),
            _ModeButton(
              label: 'Приватный',
              subtitle: 'Только выбранные тебя видят',
              icon: PhosphorIcons.lockSimple(PhosphorIconsStyle.fill),
              color: const Color(0xFFCECBF6),
              isActive: _currentMode == 0x01,
              onTap: _currentMode == 0xFF ? null : () => _setMode(0x01),
            ),
            // OFF намеренно убран из приложения — управляется кнопкой на браслете.
            // Безопасность: браслет можно выключить без телефона.
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// Плашка когда браслет выключен физической кнопкой
class _OffBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(SeeURadii.card),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Icon(PhosphorIcons.power(PhosphorIconsStyle.fill),
              size: 20, color: c.ink3),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Браслет выключен',
                    style: SeeUTypography.subtitle.copyWith(
                        fontWeight: FontWeight.w600, color: c.ink2)),
                const SizedBox(height: 2),
                Text('Нажми кнопку на браслете чтобы включить',
                    style: SeeUTypography.caption.copyWith(color: c.ink3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isActive;
  // null = кнопка задизейблена (браслет выключен физически)
  final VoidCallback? onTap;

  const _ModeButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = color.computeLuminance() > 0.5;
    final fg = isLight ? const Color(0xFF333333) : Colors.white;
    final disabled = onTap == null;

    return Opacity(
      opacity: disabled ? 0.4 : 1.0,
      child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isActive ? color : SeeUColors.surfaceElevated,
          borderRadius: BorderRadius.circular(SeeURadii.card),
          border: Border.all(
            color: isActive ? color : SeeUColors.borderSubtle,
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive ? SeeUShadows.md : SeeUShadows.sm,
        ),
        child: Row(
          children: [
            Icon(icon, color: isActive ? fg : color, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: SeeUTypography.subtitle.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isActive ? fg : SeeUColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: SeeUTypography.caption.copyWith(
                      color: isActive
                          ? fg.withValues(alpha: 0.7)
                          : SeeUColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (isActive)
              Icon(
                PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                color: fg,
                size: 22,
              ),
          ],
        ),
      ),
    )); // закрываем Opacity
  }
}
