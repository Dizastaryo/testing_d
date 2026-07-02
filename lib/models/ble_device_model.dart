import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class SeeUPacket {
  final int mode;
  final String idHex;
  final bool crcValid;

  const SeeUPacket({
    required this.mode,
    required this.idHex,
    required this.crcValid,
  });

  /// Парсит из AdvertisementData.manufacturerData.
  /// Ключ 0x297A → payload 10 байт [mode, id0..id7, crc].
  /// Для CRC реконструируем полный 12-байтовый пакет.
  static SeeUPacket? tryParse(Map<int, List<int>> manufacturerData) {
    final payload = manufacturerData[0x297A];
    if (payload == null || payload.length != 10) return null;

    final full = <int>[0x7A, 0x29, ...payload];
    int crc = 0;
    for (int i = 0; i < 11; i++) {
      crc ^= full[i];
    }
    final crcValid = crc == full[11];

    final mode = payload[0];
    final idHex = payload
        .sublist(1, 9)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();

    return SeeUPacket(mode: mode, idHex: idHex, crcValid: crcValid);
  }

  bool get isPublic => mode == 0x00;
  bool get isPrivate => mode == 0x01;
  bool get isOff => mode == 0xFF;
}

class BleDeviceModel {
  final String id;
  final String name;
  final String macAddress;
  final int rssi;
  final String? manufacturerData;
  final DateTime lastSeen;
  final SeeUPacket? seeuPacket;
  final BluetoothDevice? bleDevice;

  static const double _txPower = -59;
  static const double _n = 2.0;

  BleDeviceModel({
    required this.id,
    required this.name,
    required this.macAddress,
    required this.rssi,
    this.manufacturerData,
    this.seeuPacket,
    this.bleDevice,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  factory BleDeviceModel.fromScanResult(ScanResult result) {
    final device = result.device;
    final advData = result.advertisementData;
    String? mfData;

    if (advData.manufacturerData.isNotEmpty) {
      final entry = advData.manufacturerData.entries.first;
      final bytes = entry.value;
      mfData = String.fromCharCodes(bytes);
    }

    final displayId = mfData ?? device.remoteId.str;
    final displayName = advData.advName.isNotEmpty
        ? advData.advName
        : 'Unknown Device';

    final packet = SeeUPacket.tryParse(advData.manufacturerData);

    return BleDeviceModel(
      id: displayId,
      name: displayName,
      macAddress: device.remoteId.str,
      rssi: result.rssi,
      manufacturerData: mfData,
      seeuPacket: packet,
      bleDevice: device,
    );
  }

  double get distance {
    return pow(10, (_txPower - rssi) / (10 * _n)).toDouble();
  }

  String get distanceStr {
    final d = distance;
    if (d < 1) return '${(d * 100).toStringAsFixed(0)} cm';
    if (d < 10) return '${d.toStringAsFixed(1)} m';
    return '${d.toStringAsFixed(0)} m';
  }

  Color get signalColor {
    if (rssi > -60) return const Color(0xFF4CAF50);
    if (rssi > -80) return const Color(0xFFFFC107);
    return const Color(0xFFF44336);
  }

  String get signalLabel {
    if (rssi > -60) return 'Близко';
    if (rssi > -80) return 'Средне';
    return 'Далеко';
  }

  String get avatarLetter {
    if (manufacturerData != null && manufacturerData!.isNotEmpty) {
      return manufacturerData![0].toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  BleDeviceModel copyWithRssi(int newRssi) {
    return BleDeviceModel(
      id: id,
      name: name,
      macAddress: macAddress,
      rssi: newRssi,
      manufacturerData: manufacturerData,
      seeuPacket: seeuPacket,
      bleDevice: bleDevice,
    );
  }
}
