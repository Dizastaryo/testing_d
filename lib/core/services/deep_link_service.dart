import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Диплинки `seeu://…` — те самые ссылки, которыми приложение делится наружу.
///
/// Историческая форма ссылок — `seeu://files/{id}`, где «files» попадает в
/// **host**, а не в path. Поэтому маршрут нельзя брать из `uri.path` — его
/// надо собирать как `host + path`, иначе `seeu://files/abc` превратится в
/// `/abc` и уйдёт в 404. Заодно понимаем и форму `seeu:///files/abc`
/// (пустой host) — на случай, если ссылку где-то нормализовали.
///
/// Ссылка, пришедшая до логина, не теряется: она откладывается и открывается
/// сразу после входа.
class DeepLinkService {
  final GoRouter router;

  /// true, когда пользователь авторизован. Диплинк на защищённый экран без
  /// авторизации был бы вышвырнут redirect'ом на /login.
  final bool Function() isAuthenticated;

  DeepLinkService({required this.router, required this.isAuthenticated});

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  Timer? _initialGuard;

  /// Ссылка, пришедшая, пока пользователь не авторизован.
  String? _pending;

  /// Ссылка холодного старта. На части платформ поток при подписке повторно
  /// отдаёт её же — тогда экран открылся бы дважды. Гасим ровно один повтор.
  Uri? _consumedInitial;

  /// Экраны, с которых нельзя открывать диплинк: splash в конце делает `go()`
  /// и затирает стек, а login/onboarding/complete-profile — это шлюзы, куда
  /// redirect вернёт человека обратно.
  static const _gates = [
    '/splash',
    '/login',
    '/register',
    '/onboarding',
    '/complete-profile',
  ];

  bool get _atGate {
    final loc = router.state.matchedLocation;
    return _gates.any((g) => loc.startsWith(g));
  }

  Future<void> start() async {
    // Пока приложение не прошло splash/логин, ссылку открывать некуда —
    // ждём, когда человек окажется на настоящем экране.
    router.routerDelegate.addListener(_onRouteChanged);

    // Холодный старт: приложение открыли самой ссылкой.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _consumedInitial = initial;
        _handle(initial);
      }
    } catch (e) {
      debugPrint('[deeplink] initial link failed: $e');
    }

    // Приложение уже запущено — ссылка приходит потоком.
    _sub = _appLinks.uriLinkStream.listen(
      (uri) {
        if (_consumedInitial == uri) {
          // Это эхо стартовой ссылки, а не новое открытие.
          _consumedInitial = null;
          return;
        }
        _handle(uri);
      },
      onError: (Object e) => debugPrint('[deeplink] stream error: $e'),
    );

    // Эхо приходит сразу при подписке. Если его не было — забываем стартовую
    // ссылку, чтобы её повторное открытие через минуту сработало как обычно.
    _initialGuard = Timer(
      const Duration(seconds: 2),
      () => _consumedInitial = null,
    );
  }

  void dispose() {
    _initialGuard?.cancel();
    _sub?.cancel();
    _sub = null;
    router.routerDelegate.removeListener(_onRouteChanged);
  }

  void _onRouteChanged() {
    if (_pending == null) return;
    flushPending();
  }

  /// Открывает отложенную ссылку, если приложение к этому готово.
  ///
  /// Пуш уходит следующим кадром: сюда попадаем из слушателя роутера, то есть
  /// посреди навигации — навигировать оттуда синхронно нельзя.
  void flushPending() {
    final route = _pending;
    if (route == null) return;
    if (!isAuthenticated() || _atGate) return;
    _pending = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => router.push(route));
  }

  void _handle(Uri uri) {
    if (uri.scheme != 'seeu') return;
    final route = routeFor(uri);
    if (route == null) {
      debugPrint('[deeplink] unknown link: $uri');
      return;
    }

    // Ссылка не теряется: она подождёт логина и конца splash-экрана.
    _pending = route;
    flushPending();
  }

  /// `seeu://collection/abc` → `/collection/abc`.
  /// Разбор вынесен отдельно, чтобы его можно было проверить тестом.
  @visibleForTesting
  static String? routeFor(Uri uri) {
    if (uri.scheme != 'seeu') return null;

    // Собираем «host + path»: у `seeu://files/abc` первый сегмент лежит в host,
    // у `seeu:///files/abc` — уже в path.
    final segments = <String>[
      if (uri.host.isNotEmpty) uri.host,
      ...uri.pathSegments.where((s) => s.isNotEmpty),
    ];
    if (segments.isEmpty) return null;

    final head = segments.first;
    final rest = segments.skip(1).toList();

    switch (head) {
      // Книга/файл библиотеки.
      case 'files':
        return rest.isEmpty ? '/files' : '/files/${rest.first}';

      // Подборка книг — открывается и чужая, если владелец её расшарил.
      case 'collection':
        return rest.isEmpty ? null : '/collection/${rest.first}';

      case 'sbory':
        return rest.isEmpty ? '/sbory' : '/sbory/${rest.first}';

      case 'post':
        return rest.isEmpty ? null : '/post/${rest.first}';

      case 'profile':
        return rest.isEmpty ? '/profile' : '/profile/${rest.first}';

      // QR браслета из админки: серийник подставится в поле привязки.
      case 'bind':
        if (rest.isEmpty) return '/settings/chip';
        return '/settings/chip?serial=${Uri.encodeComponent(rest.first)}';

      case 'scanner':
        return '/scanner';

      default:
        return null;
    }
  }
}
