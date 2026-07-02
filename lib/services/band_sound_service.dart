import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'chip_control_service.dart';

/// Фаза 6: при получении Spark проигрывает тон на СВОЁМ браслете.
/// Best-effort: сканирует эфир, находит браслет «SeeUBand», подключается, сверяет
/// public_id и пишет в PlayChar. Любая ошибка/отсутствие браслета — тихо.
class BandSoundService {
  static bool _busy = false;

  /// [ownPublicIdHex] — public_id_hex своего браслета (User.devicePublicId).
  static Future<void> playOwnBandSpark(String? ownPublicIdHex) async {
    final want = (ownPublicIdHex ?? '').toLowerCase();
    if (_busy || want.isEmpty) return;
    _busy = true;

    BluetoothDevice? found;
    StreamSubscription? sub;
    try {
      sub = FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          if (r.advertisementData.advName == 'SeeUBand') {
            found ??= r.device;
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
      final deadline = DateTime.now().add(const Duration(seconds: 6));
      while (found == null && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      await FlutterBluePlus.stopScan();
      await sub.cancel();
      sub = null;

      final device = found;
      if (device == null) return;

      final chip = ChipControlService();
      try {
        final info = await chip.connectAndRead(device);
        if (info.publicIdHex.toLowerCase() == want) {
          await chip.playSparkTone();
        }
      } finally {
        await chip.disconnect();
      }
    } catch (_) {
      // best-effort — звук некритичен
    } finally {
      await sub?.cancel();
      _busy = false;
    }
  }
}
