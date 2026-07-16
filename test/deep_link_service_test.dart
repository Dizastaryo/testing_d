import 'package:flutter_test/flutter_test.dart';
import 'package:seeu/core/services/deep_link_service.dart';

/// Ссылки, которыми приложение делится наружу, имеют вид `seeu://files/{id}` —
/// первый сегмент попадает в HOST, а не в path. Именно на этом ломается
/// наивный разбор через `uri.path`, поэтому проверяем обе формы.
void main() {
  String? route(String link) => DeepLinkService.routeFor(Uri.parse(link));

  group('routeFor — историческая форма seeu://host/path', () {
    test('книга', () {
      expect(route('seeu://files/abc-123'), '/files/abc-123');
    });

    test('подборка', () {
      expect(route('seeu://collection/c1'), '/collection/c1');
    });

    test('сбор', () {
      expect(route('seeu://sbory/s1'), '/sbory/s1');
    });

    test('профиль', () {
      expect(route('seeu://profile/alisher'), '/profile/alisher');
    });

    test('пост', () {
      expect(route('seeu://post/p1'), '/post/p1');
    });

    test('сканер без хвоста', () {
      expect(route('seeu://scanner'), '/scanner');
    });
  });

  group('routeFor — нормализованная форма seeu:///path', () {
    test('книга', () {
      expect(route('seeu:///files/abc-123'), '/files/abc-123');
    });

    test('подборка', () {
      expect(route('seeu:///collection/c1'), '/collection/c1');
    });
  });

  group('routeFor — привязка браслета', () {
    test('серийник уезжает в query, а не в путь', () {
      expect(
        route('seeu://bind/SEEU_8b2ee44'),
        '/settings/chip?serial=SEEU_8b2ee44',
      );
    });

    test('без серийника — просто экран привязки', () {
      expect(route('seeu://bind'), '/settings/chip');
    });
  });

  group('routeFor — что не должно открываться', () {
    test('чужая схема игнорируется', () {
      expect(route('https://example.com/files/abc'), isNull);
    });

    test('неизвестный раздел игнорируется', () {
      expect(route('seeu://unknown/x'), isNull);
    });

    test('пустая ссылка игнорируется', () {
      expect(route('seeu://'), isNull);
    });

    test('подборка без id не ведёт в никуда', () {
      expect(route('seeu://collection'), isNull);
    });
  });
}
