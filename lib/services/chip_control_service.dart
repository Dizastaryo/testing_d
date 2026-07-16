import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const _svcUuid      = '5ee0cafe-5ee0-5ee0-5ee0-5ee0cafe0001';
const _modeCharUuid = '5ee0cafe-5ee0-5ee0-5ee0-5ee0cafe0002';
const _infoCharUuid = '5ee0cafe-5ee0-5ee0-5ee0-5ee0cafe0003';
const _playCharUuid = '5ee0cafe-5ee0-5ee0-5ee0-5ee0cafe0004'; // Фаза 6: триггер тона

const _toneSpark = 0x01; // tone id «пришёл Spark»

class ChipInfo {
  final int protoIndex;
  final String publicIdHex;
  final String privateIdHex;
  final int currentMode;

  const ChipInfo({
    required this.protoIndex,
    required this.publicIdHex,
    required this.privateIdHex,
    required this.currentMode,
  });
}

class ChipControlException implements Exception {
  final String message;
  const ChipControlException(this.message);

  @override
  String toString() => 'ChipControlException: $message';
}

class ChipControlService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _modeChar;
  BluetoothCharacteristic? _infoChar;
  BluetoothCharacteristic? _playChar; // Фаза 6: опциональна (старые прошивки без неё)
  StreamSubscription? _notifySub;
  final _modeController = StreamController<int>.broadcast();
  bool _connected = false;

  bool get isConnected => _connected;
  Stream<int> get modeStream => _modeController.stream;

  Future<ChipInfo> connectAndRead(BluetoothDevice device) async {
    _device = device;

    try {
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );
    } catch (e) {
      throw ChipControlException('Не удалось подключиться: $e');
    }

    // Виджет закрылся во время connect (dispose уже отработал): не оставляем
    // живой GATT-линк висеть — сразу рвём (у ESP32 лимит подключений).
    if (_disposed) {
      try {
        await device.disconnect();
      } catch (_) {}
      throw ChipControlException('Отменено');
    }

    _connected = true;

    List<BluetoothService> services;
    try {
      services = await device.discoverServices();
    } catch (e) {
      await _cleanup();
      throw ChipControlException('Не удалось найти сервисы: $e');
    }

    final svc = services.cast<BluetoothService?>().firstWhere(
      (s) => s!.uuid.toString().toLowerCase() == _svcUuid,
      orElse: () => null,
    );
    if (svc == null) {
      await _cleanup();
      throw const ChipControlException('SeeU GATT сервис не найден');
    }

    for (final c in svc.characteristics) {
      final uuid = c.uuid.toString().toLowerCase();
      if (uuid == _modeCharUuid) _modeChar = c;
      if (uuid == _infoCharUuid) _infoChar = c;
      if (uuid == _playCharUuid) _playChar = c;
    }

    if (_modeChar == null || _infoChar == null) {
      await _cleanup();
      throw const ChipControlException('Характеристики не найден��');
    }

    // Read info (18 bytes)
    List<int> infoBytes;
    try {
      infoBytes = await _infoChar!.read();
    } catch (e) {
      await _cleanup();
      throw ChipControlException('Не удалось прочитать Info: $e');
    }

    if (infoBytes.length < 18) {
      await _cleanup();
      throw ChipControlException(
        'Info слишком короткий: ${infoBytes.length} байт',
      );
    }

    final protoIndex = infoBytes[0];
    final publicHex = infoBytes
        .sublist(1, 9)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
    final privateHex = infoBytes
        .sublist(9, 17)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
    final currentMode = infoBytes[17];

    // Subscribe to mode notifications
    try {
      await _modeChar!.setNotifyValue(true);
      _notifySub = _modeChar!.onValueReceived.listen((value) {
        if (value.isNotEmpty) {
          _modeController.add(value[0]);
        }
      });
    } catch (_) {
      // Notify not critical — read still works
    }

    return ChipInfo(
      protoIndex: protoIndex,
      publicIdHex: publicHex,
      privateIdHex: privateHex,
      currentMode: currentMode,
    );
  }

  Future<void> setMode(int mode) async {
    if (_modeChar == null || !_connected) {
      throw const ChipControlException('Не подключено');
    }
    try {
      await _modeChar!.write([mode], withoutResponse: false);
    } catch (e) {
      throw ChipControlException('Не удалось записать режим: $e');
    }
  }

  /// Фаза 6: триггерит на браслете короткий тон Spark (если прошивка
  /// поддерживает PlayChar). Тихо игнорируется на старых прошивках.
  Future<void> playSparkTone() async {
    final ch = _playChar;
    if (ch == null || !_connected) return;
    try {
      await ch.write([_toneSpark], withoutResponse: true);
    } catch (_) {
      // Звук некритичен — не роняем поток из-за него.
    }
  }

  bool _disposed = false;

  Future<void> disconnect() async {
    await _cleanup();
  }

  Future<void> _cleanup() async {
    // await отмены подписки ДО закрытия контроллера (ниже в dispose) —
    // иначе пришедшая между планированием cancel и close нотификация режима
    // стреляла _modeController.add на уже закрытом контроллере (StateError).
    await _notifySub?.cancel();
    _notifySub = null;
    _modeChar  = null;
    _infoChar  = null;
    _playChar  = null;
    _connected = false;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    // Последовательно: сначала полный cleanup (с await cancel + disconnect),
    // потом закрытие контроллера. Раньше _cleanup не await'ился, и close шёл
    // немедленно — гонка с pending-нотификацией + утечка GATT-линка, если
    // connect() завершался уже после dispose.
    await _cleanup();
    await _modeController.close();
  }
}
