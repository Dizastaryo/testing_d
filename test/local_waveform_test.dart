import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:seeu/core/audio/local_waveform.dart';

/// PCM signed 16-bit little-endian — то, что отдаёт ffmpeg. Ошибка в разборе
/// байтов даёт правдоподобную, но неверную волну, поэтому проверяем её отдельно
/// от самого ffmpeg.
Uint8List pcm(List<int> samples) {
  final b = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    b.setInt16(i * 2, samples[i], Endian.little);
  }
  return b.buffer.asUint8List();
}

void main() {
  test('слишком короткий файл — волны нет, а не мусор', () {
    expect(LocalWaveform.peaksFromPcm(pcm(List.filled(50, 1000))), isNull);
  });

  test('тишина — волны нет, а не плоская линия на весь экран', () {
    expect(LocalWaveform.peaksFromPcm(pcm(List.filled(4000, 0))), isNull);
  });

  test('ровный сигнал даёт ровно 100 пиков', () {
    final peaks = LocalWaveform.peaksFromPcm(pcm(List.filled(4000, 8000)));
    expect(peaks, isNotNull);
    expect(peaks!.length, 100);
    // Нормируем по собственному максимуму: ровный сигнал — ровная волна.
    expect(peaks.every((p) => (p - 1.0).abs() < 0.01), isTrue);
  });

  test('отрицательные отсчёты берутся по модулю', () {
    // Синус уходит в минус; если брать знак, половина волны исчезнет.
    final samples = [
      for (var i = 0; i < 4000; i++)
        (math.sin(i / 20) * 20000).round(),
    ];
    final peaks = LocalWaveform.peaksFromPcm(pcm(samples))!;
    expect(peaks.every((p) => p > 0.5), isTrue,
        reason: 'у синуса нет тихих участков — значит модуль работает');
  });

  test('громкая середина заметно выше тихих краёв', () {
    final samples = [
      ...List.filled(1500, 500),
      ...List.filled(1000, 30000),
      ...List.filled(1500, 500),
    ];
    final peaks = LocalWaveform.peaksFromPcm(pcm(samples))!;
    final middle = peaks[50];
    final edge = peaks[2];
    expect(middle, greaterThan(0.9));
    expect(edge, lessThan(0.2));
  });

  test('все пики укладываются в 0..1', () {
    final samples = [
      for (var i = 0; i < 5000; i++) (i % 7 == 0) ? 32767 : -32768,
    ];
    final peaks = LocalWaveform.peaksFromPcm(pcm(samples))!;
    expect(peaks.every((p) => p >= 0 && p <= 1), isTrue);
  });
}
