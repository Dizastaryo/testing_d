import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/ble_device_model.dart';

/// PROFILE-1: глобальный store BLE-устройств в радиусе. Подписывается на
/// FlutterBluePlus.onScanResults и сохраняет уникальные устройства по MAC.
///
/// Используется в:
///  - `scanner_screen.dart` (radar UI — может читать тот же провайдер)
///  - `profile_screen.dart` (показывает «N рядом» badge)
///
/// State — `Map<String macAddress, BleDeviceModel>`. Любой consumer ватчит
/// `.length` для count или весь map для деталей. Stale-чистка по
/// `removeIfGone` от FlutterBluePlus (5с).
class NearbyDevicesNotifier extends StateNotifier<Map<String, BleDeviceModel>> {
  // BUG-7: exposed `_sub` (через extension below) чтобы ref.onDispose имел
  // к нему доступ извне. StateNotifier.dispose тоже cancel'ит, дублируем.
  StreamSubscription<List<ScanResult>>? _sub;

  NearbyDevicesNotifier() : super(const {}) {
    _sub = FlutterBluePlus.onScanResults.listen(_onResults);
  }

  void _onResults(List<ScanResult> results) {
    final next = Map<String, BleDeviceModel>.from(state);
    bool changed = false;
    for (final r in results) {
      if (r.advertisementData.advName != 'ESP32C3_TAG') continue;
      final d = BleDeviceModel.fromScanResult(r);
      // Reuse compare: если MAC + rssi не изменились, не дёргаем listener'ов.
      final prev = next[d.macAddress];
      if (prev == null || prev.rssi != d.rssi) {
        next[d.macAddress] = d;
        changed = true;
      }
    }
    if (changed) state = next;
  }

  /// Очистить state — например когда отключили сканирование пользователем.
  void clear() {
    if (state.isNotEmpty) state = const {};
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final nearbyDevicesProvider = StateNotifierProvider<NearbyDevicesNotifier,
    Map<String, BleDeviceModel>>((ref) {
  final notifier = NearbyDevicesNotifier();
  // BUG-7 defense-in-depth: помимо StateNotifier.dispose (где _sub.cancel)
  // явный ref.onDispose гарантирует cancel при любом сценарии invalidation
  // провайдера (logout / hot-reload / test cleanup). Двойной cancel
  // идемпотент — Future-based StreamSubscription это безопасно.
  ref.onDispose(() => notifier._sub?.cancel());
  return notifier;
});

/// Convenience-провайдер для UI: число найденных устройств. Перерендеривает
/// consumer только когда count меняется, не на каждом rssi-tick'е.
final nearbyDevicesCountProvider = Provider<int>((ref) {
  return ref.watch(nearbyDevicesProvider).length;
});
