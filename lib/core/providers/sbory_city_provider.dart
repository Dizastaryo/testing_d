import 'dart:math' show sqrt, sin, cos, atan2, pi;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Список городов Казахстана ────────────────────────────────────

class KzCity {
  final String name;
  final double lat;
  final double lng;
  const KzCity(this.name, this.lat, this.lng);
}

const List<KzCity> kKazakhstanCities = [
  KzCity('Алматы', 43.2220, 76.8512),
  KzCity('Астана', 51.1801, 71.4460),
  KzCity('Шымкент', 42.3417, 69.5901),
  KzCity('Актобе', 50.2839, 57.1669),
  KzCity('Тараз', 42.9000, 71.3667),
  KzCity('Павлодар', 52.2833, 76.9667),
  KzCity('Усть-Каменогорск', 49.9490, 82.6285),
  KzCity('Семей', 50.4120, 80.2276),
  KzCity('Атырау', 47.1066, 51.9199),
  KzCity('Костанай', 53.2167, 63.6167),
  KzCity('Кызылорда', 44.8479, 65.5093),
  KzCity('Уральск', 51.2333, 51.3667),
  KzCity('Петропавловск', 54.8667, 69.1500),
  KzCity('Актау', 43.6526, 51.1974),
  KzCity('Темиртау', 50.0608, 72.9619),
  KzCity('Туркестан', 43.3031, 68.2642),
  KzCity('Экибастуз', 51.7264, 75.3209),
  KzCity('Талдыкорган', 44.9833, 78.3833),
  KzCity('Рудный', 52.9654, 63.1300),
  KzCity('Жезказган', 47.7880, 67.7160),
  KzCity('Балхаш', 46.8483, 74.9950),
  KzCity('Кокшетау', 53.2865, 69.3925),
  KzCity('Жанаозен', 43.3403, 52.8686),
  KzCity('Риддер', 50.3480, 83.5060),
  KzCity('Каскелен', 43.1987, 76.6257),
  KzCity('Конаев', 43.8644, 77.0650),
  KzCity('Степногорск', 52.3500, 71.8833),
  KzCity('Аксай', 51.1700, 53.0100),
  KzCity('Зыряновск', 49.7250, 84.2980),
  KzCity('Хромтау', 50.2520, 58.4430),
];

const _kPrefsKey = 'sbory_city';
const _kDefaultCity = 'Алматы';

// ─── Notifier ─────────────────────────────────────────────────────

class SboryCityNotifier extends StateNotifier<String> {
  SboryCityNotifier() : super(_kDefaultCity);

  /// Вызывается один раз при открытии SboryScreen.
  /// Логика:
  ///   1. Если в SharedPreferences уже есть сохранённый город — загружаем его,
  ///      геолокацию не запрашиваем.
  ///   2. Если нет — запрашиваем разрешение на геолокацию:
  ///      - Разрешено → определяем ближайший город → сохраняем
  ///      - Отказано → сохраняем «Алматы» по умолчанию
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kPrefsKey);
    if (saved != null && saved.isNotEmpty) {
      // Город уже выбран ранее — просто показываем его.
      state = saved;
      return;
    }

    // Первый заход — пробуем определить через геолокацию.
    final detected = await _detectCity();
    final city = detected ?? _kDefaultCity;
    state = city;
    await prefs.setString(_kPrefsKey, city);
  }

  /// Ручной выбор города пользователем.
  Future<void> selectCity(String city) async {
    state = city;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsKey, city);
  }

  // ─── Private ────────────────────────────────────────────────────

  Future<String?> _detectCity() async {
    try {
      // Проверяем, включён ли сервис геолокации.
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      // Проверяем / запрашиваем разрешение.
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }

      // Получаем координаты (низкая точность — нам достаточно для города).
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return _nearestCity(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Возвращает название ближайшего города из списка по координатам.
  String _nearestCity(double lat, double lng) {
    KzCity? best;
    double bestDist = double.infinity;
    for (final city in kKazakhstanCities) {
      final d = _dist(lat, lng, city.lat, city.lng);
      if (d < bestDist) {
        bestDist = d;
        best = city;
      }
    }
    return best?.name ?? _kDefaultCity;
  }

  /// Приблизительное расстояние (км) через формулу Хаверсина.
  double _dist(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _rad(double deg) => deg * pi / 180;
}

// ─── Provider ─────────────────────────────────────────────────────

final sboryCityProvider =
    StateNotifierProvider<SboryCityNotifier, String>((ref) {
  return SboryCityNotifier();
});
