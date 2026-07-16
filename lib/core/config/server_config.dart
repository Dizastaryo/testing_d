import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_config.dart';

/// Провайдер хранит текущий LAN IP. Когда меняется — все Dio-провайдеры
/// пересоздаются автоматически (через ref.watch).
final serverIpProvider = StateProvider<String>((ref) => ServerConfig.lanIp);

/// Конфигурация адреса бэкенда. IP можно менять в runtime через [setLanIp],
/// что позволяет тестировать на реальном телефоне без пересборки.
class ServerConfig {
  ServerConfig._();

  static const _key = 'lan_ip';

  static String _lanIp = _extractIp(AppConfig.apiBaseUrl);

  static String get lanIp => _lanIp;
  static String get apiBaseUrl => 'http://$_lanIp:8001/api/v1';
  static String get libraryBaseUrl => 'http://$_lanIp:8003/api/v1';

  /// Вызывается в main() до runApp. Загружает сохранённый IP из SharedPreferences.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && saved.isNotEmpty) {
      _lanIp = saved;
    }
  }

  /// Сохраняет IP и обновляет runtime-состояние.
  static Future<void> setLanIp(String ip) async {
    _lanIp = ip.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _lanIp);
  }

  static String _extractIp(String url) {
    final uri = Uri.tryParse(url);
    return uri?.host ?? '192.168.1.2';
  }
}
