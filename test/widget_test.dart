import 'package:flutter_test/flutter_test.dart';
import 'package:seeu/models/ble_device_model.dart';

void main() {
  test('Distance calculation works', () {
    final device = BleDeviceModel(
      id: 'TEST',
      name: 'Test',
      macAddress: 'AA:BB:CC:DD:EE:FF',
      rssi: -59,
    );
    expect(device.distance, closeTo(1.0, 0.1));
  });

  test('Signal color based on RSSI', () {
    final close = BleDeviceModel(
      id: 'T', name: 'T', macAddress: 'AA', rssi: -50,
    );
    final mid = BleDeviceModel(
      id: 'T', name: 'T', macAddress: 'BB', rssi: -70,
    );
    final far = BleDeviceModel(
      id: 'T', name: 'T', macAddress: 'CC', rssi: -90,
    );
    expect(close.signalLabel, 'Близко');
    expect(mid.signalLabel, 'Средне');
    expect(far.signalLabel, 'Далеко');
  });
}
