import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../widgets/chip_control_sheet.dart';

/// Thin wrapper that makes ChipControlSheet presentable as a standalone screen
/// inside a modal bottom sheet. Grabber/glass chrome comes from
/// `showSeeUBottomSheet` at the call site — this just hosts the content.
class ChipControlSheetWrapper extends StatelessWidget {
  final BluetoothDevice device;

  const ChipControlSheetWrapper({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    return ChipControlSheet(device: device);
  }
}
