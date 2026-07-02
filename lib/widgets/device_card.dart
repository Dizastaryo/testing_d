import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../core/design/design.dart';
import '../models/ble_device_model.dart';
import '../services/user_resolver.dart';
import 'chip_control_sheet.dart';

class DeviceCard extends StatefulWidget {
  final BleDeviceModel device;
  final ResolvedDevice resolved;

  const DeviceCard({
    super.key,
    required this.device,
    required this.resolved,
  });

  @override
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard> {
  bool _expanded = false;

  BleDeviceModel get device => widget.device;
  ResolvedDevice get resolved => widget.resolved;

  // --- Badge colors ---
  static const _friendColor = Color(0xFF5DCAA5);
  static const _knownColor = Color(0xFF85B7EB);
  static const _privateColor = Color(0xFFCECBF6);
  static const _unknownColor = Color(0xFF555555);

  Color get _signalColor {
    if (device.rssi > -60) return SeeUColors.signalClose;
    if (device.rssi > -80) return SeeUColors.signalMedium;
    return SeeUColors.signalFar;
  }

  double get _signalFraction {
    if (device.rssi > -60) return 1.0;
    if (device.rssi > -80) return 0.66;
    return 0.33;
  }

  Color get _badgeBg {
    switch (resolved.relationship) {
      case Relationship.friend:
        return _friendColor;
      case Relationship.knownPublic:
        return _knownColor;
      case Relationship.strangerPrivate:
        return _privateColor;
      case Relationship.me:
        return SeeUColors.textTertiary;
      case Relationship.myChipOff:
        return SeeUColors.textTertiary;
      case Relationship.unknown:
        return _unknownColor;
    }
  }

  String get _badgeLabel {
    switch (resolved.relationship) {
      case Relationship.friend:
        return 'Друг';
      case Relationship.knownPublic:
        return 'Знакомый';
      case Relationship.strangerPrivate:
        return 'Приватный';
      case Relationship.me:
        return 'Это ты';
      case Relationship.myChipOff:
        return 'Чип молчит';
      case Relationship.unknown:
        return 'Неизвестно';
    }
  }

  String get _displayName {
    switch (resolved.relationship) {
      case Relationship.friend:
      case Relationship.knownPublic:
      case Relationship.me:
        return resolved.user?.name ?? 'Неизвестно';
      case Relationship.myChipOff:
        return 'Твой чип';
      case Relationship.strangerPrivate:
        return 'Кто-то рядом';
      case Relationship.unknown:
        return 'Неизвестно';
    }
  }

  String? get _modeSubtitle {
    if (!resolved.hasValidPacket || resolved.mode == null) return null;
    if (resolved.mode == 0x00) return 'Общий';
    if (resolved.mode == 0x01) return 'Приватный';
    if (resolved.mode == 0xFF) return 'Выключен';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final signalColor = _signalColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SeeUCard(
        onTap: () => setState(() => _expanded = !_expanded),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildAvatar(signalColor),
                const SizedBox(width: 14),
                Expanded(child: _buildInfo(signalColor)),
                const SizedBox(width: 12),
                _buildSignalColumn(signalColor),
              ],
            ),
            // "Никто тебя не видит" for myChipOff
            if (resolved.relationship == Relationship.myChipOff) ...[
              const SizedBox(height: 8),
              Text(
                'Никто тебя не видит',
                style: SeeUTypography.caption.copyWith(
                  color: SeeUColors.textTertiary,
                ),
              ),
            ],
            // "Управлять" button for own chip
            if (resolved.isMyChip && device.bleDevice != null) ...[
              const SizedBox(height: 12),
              _buildManageButton(),
            ],
            if (_expanded) ...[
              const SizedBox(height: 16),
              _buildDebugBlock(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(Color signalColor) {
    final hasUser = resolved.user != null;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (hasUser ? _badgeBg : signalColor).withValues(alpha: 0.2),
            (hasUser ? _badgeBg : signalColor).withValues(alpha: 0.4),
          ],
        ),
      ),
      child: Center(
        child: hasUser
            ? Text(
                resolved.user!.avatarEmoji,
                style: const TextStyle(fontSize: 22),
              )
            : Icon(
                PhosphorIcons.question(PhosphorIconsStyle.bold),
                color: SeeUColors.textTertiary,
                size: 22,
              ),
      ),
    );
  }

  Widget _buildInfo(Color signalColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name + badge
        Row(
          children: [
            Flexible(
              child: Text(
                _displayName,
                style: SeeUTypography.subtitle.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _buildBadge(),
          ],
        ),
        // Mode subtitle
        if (_modeSubtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            _modeSubtitle!,
            style: SeeUTypography.caption.copyWith(
              color: SeeUColors.textTertiary,
            ),
          ),
        ],
        const SizedBox(height: 8),
        // Signal bar
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 3,
            child: LinearProgressIndicator(
              value: _signalFraction,
              backgroundColor: SeeUColors.borderSubtle,
              valueColor: AlwaysStoppedAnimation<Color>(signalColor),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          device.signalLabel.toUpperCase(),
          style: SeeUTypography.micro.copyWith(color: signalColor),
        ),
      ],
    );
  }

  Widget _buildBadge() {
    final bg = _badgeBg;
    final isLight = bg.computeLuminance() > 0.5;
    final fg = isLight ? const Color(0xFF333333) : Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SeeURadii.pill),
      ),
      child: Text(
        _badgeLabel,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildSignalColumn(Color signalColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${device.rssi}',
              style: SeeUTypography.displayL
                  .copyWith(fontWeight: FontWeight.w600, color: signalColor),
            ),
            const SizedBox(width: 4),
            Text(
              'dBm',
              style: SeeUTypography.micro.copyWith(color: signalColor),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SeeUChip(
          label: '~${device.distanceStr}',
          bgColor: SeeUColors.accentSoft,
          fgColor: SeeUColors.accent,
        ),
      ],
    );
  }

  Widget _buildManageButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: () => _openChipControl(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: SeeUColors.accent,
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            boxShadow: SeeUShadows.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIcons.slidersHorizontal(PhosphorIconsStyle.fill),
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Управлять',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openChipControl() {
    if (device.bleDevice == null) return;
    showSeeUBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChipControlSheet(device: device.bleDevice!),
    );
  }

  Widget _buildDebugBlock() {
    final packet = device.seeuPacket;
    final rows = <_DebugRow>[];

    if (packet != null) {
      rows.add(const _DebugRow('Company ID', '0x297A'));
      final modeStr = packet.isPublic
          ? '0x00 (public)'
          : packet.isPrivate
              ? '0x01 (private)'
              : '0xFF (off)';
      rows.add(_DebugRow('Mode', modeStr));
      rows.add(_DebugRow('ID (hex)', packet.idHex));
      rows.add(_DebugRow('CRC', packet.crcValid ? 'ok' : 'mismatch'));
    } else {
      rows.add(const _DebugRow('SeeU packet', 'not detected'));
    }
    rows.add(_DebugRow('MAC', device.macAddress));
    rows.add(_DebugRow('RSSI', '${device.rssi} dBm'));
    rows.add(_DebugRow('Last seen', _formatTime(device.lastSeen)));

    if (resolved.user != null) {
      rows.add(_DebugRow('Bio', resolved.user!.bio));
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SeeUColors.background,
        borderRadius: BorderRadius.circular(SeeURadii.small),
        border: Border.all(color: SeeUColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DEBUG',
            style: SeeUTypography.micro.copyWith(
              color: SeeUColors.textTertiary,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      row.label,
                      style: SeeUTypography.mono.copyWith(
                        color: SeeUColors.textTertiary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      style: SeeUTypography.mono.copyWith(
                        color: SeeUColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _DebugRow {
  final String label;
  final String value;
  const _DebugRow(this.label, this.value);
}
