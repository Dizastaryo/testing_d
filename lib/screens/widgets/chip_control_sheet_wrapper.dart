import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../widgets/chip_control_sheet.dart';

/// Thin wrapper that makes ChipControlSheet presentable as a standalone screen
/// inside a modal bottom sheet (adds bottom padding + drag handle).
class ChipControlSheetWrapper extends StatelessWidget {
  final BluetoothDevice device;

  const ChipControlSheetWrapper({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        ChipControlSheet(device: device),
      ],
    );
  }
}
