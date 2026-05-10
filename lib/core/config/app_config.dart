/// Build-time configuration. Values come from `--dart-define` flags;
/// defaults point at the dev-laptop's **LAN IPv4** (`192.168.10.13`).
///
/// **Why LAN, not localhost:** shipping target — iOS + Android (см. CLAUDE.md).
/// Юзер собирает APK/IPA и ставит на телефон, телефон и ноут в одной Wi-Fi
/// сети → телефон достучится до бэка по LAN-IP. localhost резолвится на
/// сам телефон и API недоступен.
///
/// Если LAN-IP ноута меняется (пересоздание сети / новый роутер) — поменять
/// здесь или пробросить через `--dart-define`.
///
/// Usage:
///   flutter build apk                                # default LAN IP
///   flutter build ipa --no-codesign                  # default LAN IP
///
///   flutter run \                                    # для другого IP / прода
///       --dart-define=API_BASE_URL=https://api.seeu.kz/api/v1 \
///       --dart-define=VIDEO_BASE_URL=https://video.seeu.kz/api/v1 \
///       --dart-define=LIBRARY_BASE_URL=https://library.seeu.kz/api/v1
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.10.13:8001/api/v1',
  );

  static const String videoBaseUrl = String.fromEnvironment(
    'VIDEO_BASE_URL',
    defaultValue: 'http://192.168.10.13:8002/api/v1',
  );

  static const String libraryBaseUrl = String.fromEnvironment(
    'LIBRARY_BASE_URL',
    defaultValue: 'http://192.168.10.13:8003/api/v1',
  );

  /// Public origin of the admin-bundle (used by main-app для deep-link'ов в
  /// модерированный контент через admin). admin-bundle сам остаётся
  /// Chrome production target — это **исключение** из rule «mobile only».
  static const String mainAppUrl = String.fromEnvironment(
    'MAIN_APP_URL',
    defaultValue: 'http://192.168.10.13:5000',
  );

  /// Strips `/api/v1` from the base URL so callers can build absolute media URLs
  /// from server-relative paths like `/uploads/2026/05/04/foo.png`.
  static String get apiOrigin => _stripApiPrefix(apiBaseUrl);
  static String get videoOrigin => _stripApiPrefix(videoBaseUrl);
  static String get libraryOrigin => _stripApiPrefix(libraryBaseUrl);

  static String _stripApiPrefix(String url) {
    const suffix = '/api/v1';
    if (url.endsWith(suffix)) {
      return url.substring(0, url.length - suffix.length);
    }
    return url;
  }
}
