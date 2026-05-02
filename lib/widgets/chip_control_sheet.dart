import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../core/design/design.dart';
import '../services/account_session.dart';
import '../services/chip_control_service.dart';

class ChipControlSheet extends StatefulWidget {
  final BluetoothDevice device;

  const ChipControlSheet({super.key, required this.device});

  @override
  State<ChipControlSheet> createState() => _ChipControlSheetState();
}

class _ChipControlSheetState extends State<ChipControlSheet> {
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

      // Верификация владельца
      final session = AccountSession.instance;
      if (info.publicIdHex != session.currentUser.publicIdHex) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  @override
  void dispose() {
    _modeSub?.cancel();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = AccountSession.instance.currentUser;

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
              Text(user.avatarEmoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Твой SeeU',
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 22,
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
            // Mode buttons
            _ModeButton(
              label: 'Общий',
              subtitle: 'Все видят твоё имя',
              icon: PhosphorIcons.broadcast(PhosphorIconsStyle.fill),
              color: const Color(0xFF5DCAA5),
              isActive: _currentMode == 0x00,
              onTap: () => _setMode(0x00),
            ),
            const SizedBox(height: 10),
            _ModeButton(
              label: 'Приватный',
              subtitle: 'Только друзья узнают те��я',
              icon: PhosphorIcons.lockSimple(PhosphorIconsStyle.fill),
              color: const Color(0xFFCECBF6),
              isActive: _currentMode == 0x01,
              onTap: () => _setMode(0x01),
            ),
            const SizedBox(height: 10),
            _ModeButton(
              label: 'Выключить',
              subtitle: 'Никто тебя не видит',
              icon: PhosphorIcons.power(PhosphorIconsStyle.fill),
              color: const Color(0xFF555555),
              isActive: _currentMode == 0xFF,
              onTap: () => _setMode(0xFF),
            ),
          ],
          const SizedBox(height: 8),
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
  final VoidCallback onTap;

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

    return GestureDetector(
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
    );
  }
}
