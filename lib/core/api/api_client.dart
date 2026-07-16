import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/server_config.dart';
import 'api_endpoints.dart';

const _accessTokenKey = 'access_token';
const _refreshTokenKey = 'refresh_token';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
});

/// `true` — есть сеть, `false` — нет соединения.
/// Обновляется автоматически из Dio-интерцептора.
final networkOnlineProvider = StateProvider<bool>((_) => true);

final apiClientProvider = Provider<ApiClient>((ref) {
  ref.watch(serverIpProvider); // rebuild when IP changes → new baseUrl
  final storage = ref.watch(secureStorageProvider);
  return ApiClient(
    storage: storage,
    onOffline: () {
      if (ref.read(networkOnlineProvider)) {
        ref.read(networkOnlineProvider.notifier).state = false;
      }
    },
    onOnline: () {
      if (!ref.read(networkOnlineProvider)) {
        ref.read(networkOnlineProvider.notifier).state = true;
      }
    },
  );
});

class ApiClient {
  late final Dio _dio;
  final FlutterSecureStorage storage;
  final void Function()? onOffline;
  final void Function()? onOnline;
  Completer<bool>? _refreshCompleter;

  // In-memory token cache. Primary source of truth for the current session;
  // the keychain is a best-effort persistence layer. If `flutter_secure_storage`
  // ever fails, this cache keeps the access token alive for the session so authed
  // requests don't 401. The keychain additionally persists tokens across launches.
  String? _accessTokenCache;
  String? _refreshTokenCache;

  /// Generation counter bumped on every [clearTokens] (i.e. logout / auth
  /// rejection). A refresh captures it at the start and refuses to write the
  /// freshly-minted tokens if it changed mid-flight — otherwise a logout that
  /// races an in-flight refresh would get its session resurrected.
  int _authEpoch = 0;

  ApiClient({required this.storage, this.onOffline, this.onOnline}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiEndpoints.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _onRequest,
        onResponse: _onResponse,
        onError: _onError,
      ),
    );

    // Retry interceptor for transient failures (5xx, timeout, connection reset).
    _dio.interceptors.add(_RetryInterceptor(_dio));

    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: true,
          requestHeader: false,
          responseHeader: false,
          error: true,
          // Wrap debugPrint so a malformed response body (e.g. U+FFFD bytes
          // sneaking in via stored content) can't crash the whole app.
          logPrint: (obj) {
            try {
              debugPrint('[API] $obj');
            } catch (_) {
              debugPrint('[API] (unprintable response — ${obj.toString().length} chars)');
            }
          },
        ),
      );
    }
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  void _onResponse(Response response, ResponseInterceptorHandler handler) {
    onOnline?.call();
    handler.next(response);
  }

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Сетевые ошибки (нет подключения / таймаут) → офлайн-статус.
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      onOffline?.call();
    }
    final alreadyRetried = err.requestOptions.extra['_authRetried'] == true;
    if (err.response?.statusCode == 401 && !alreadyRetried) {
      // refreshTokens() de-dupes concurrent callers: if a refresh is already
      // in flight it returns the shared future, so parallel 401s during token
      // expiry all await the same refresh and then retry — instead of being
      // dropped with a 401 (which happened when this was gated on
      // `_refreshCompleter == null`).
      final refreshed = await refreshTokens();
      if (refreshed) {
        final retryOptions = err.requestOptions;
        retryOptions.extra['_authRetried'] = true;
        final newToken = await getAccessToken();
        if (newToken != null) {
          retryOptions.headers['Authorization'] = 'Bearer $newToken';
        }
        // A FormData/stream body is consumed by the first send — `_dio.fetch`
        // would replay an empty/already-read stream and the upload would fail
        // with a confusing error. We can't transparently retry it, so refresh
        // the token (done above) and surface a clear retryable error letting
        // the caller re-issue the upload with a fresh FormData. JSON/map bodies
        // are safe to replay, so only opt those into the transparent retry.
        final body = retryOptions.data;
        final isStreamBody = body is FormData || body is Stream;
        if (isStreamBody) {
          handler.next(DioException(
            requestOptions: retryOptions,
            type: DioExceptionType.cancel,
            error:
                'token_refreshed_retry_upload: session was refreshed, please resend this upload',
          ));
          return;
        }
        try {
          final retryResponse = await _dio.fetch(retryOptions);
          handler.resolve(retryResponse);
          return;
        } catch (_) {
          // Fall through to original error.
        }
      }
    }
    handler.next(err);
  }

  /// Forces a refresh-token round-trip and persists the new pair. Public so
  /// non-REST clients (WebSocket reconnect logic) can prompt a refresh when
  /// they detect their own auth-related failure. Returns true on success.
  /// Concurrent callers are debounced via `_isRefreshing`.
  Future<bool> refreshTokens() async {
    if (_refreshCompleter != null) {
      // Another caller is mid-refresh — await the same future.
      return _refreshCompleter!.future;
    }
    // Capture the auth generation at the start; if a logout bumps it while the
    // refresh round-trips, we must NOT repopulate the cache/keychain.
    final epoch = _authEpoch;
    _refreshCompleter = Completer<bool>();
    try {
      final refreshToken = await _getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        _refreshCompleter!.complete(false);
        return false;
      }
      final refreshDio = Dio(
        BaseOptions(
          baseUrl: ApiEndpoints.baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final response = await refreshDio.post(
        ApiEndpoints.refreshToken,
        data: {'refresh_token': refreshToken},
      );
      // Server envelopes everything as `{data: {...}, error: null}` — unwrap.
      // Falling back to top-level keys preserves compatibility if a future
      // endpoint returns the bare token object.
      final body = response.data;
      final inner = (body is Map && body['data'] is Map) ? body['data'] : body;
      final newAccessToken = inner is Map ? inner['access_token'] as String? : null;
      final newRefreshToken = inner is Map ? inner['refresh_token'] as String? : null;
      if (newAccessToken == null) {
        _refreshCompleter!.complete(false);
        return false;
      }
      // A logout happened while the refresh was in flight — do not resurrect
      // the just-killed session by writing fresh tokens.
      if (_authEpoch != epoch) {
        _refreshCompleter!.complete(false);
        return false;
      }
      _accessTokenCache = newAccessToken;
      if (newRefreshToken != null) _refreshTokenCache = newRefreshToken;
      try {
        await storage.write(key: _accessTokenKey, value: newAccessToken);
        if (newRefreshToken != null) {
          await storage.write(key: _refreshTokenKey, value: newRefreshToken);
        }
      } catch (_) {/* keychain unavailable — cache still holds the new pair */}
      // Re-check after the awaited keychain writes: a logout could have
      // interleaved. If so, undo so cache/keychain don't hold a live session.
      if (_authEpoch != epoch) {
        await clearTokens();
        _refreshCompleter!.complete(false);
        return false;
      }
      _refreshCompleter!.complete(true);
      return true;
    } on DioException catch (e) {
      // Only a DEFINITIVE rejection of the refresh token wipes credentials.
      // A network blip / timeout / 5xx must keep the session intact (offline).
      final code = e.response?.statusCode;
      final body = e.response?.data;
      final errStr = body is Map
          ? '${body['error'] ?? ''} ${body['error_description'] ?? ''}'
          : '';
      final invalidGrant = errStr.contains('invalid_grant');
      if ((code == 401 || code == 403 || invalidGrant) && _authEpoch == epoch) {
        // Refresh-token itself rejected — wipe so the app drops to login.
        await clearTokens();
      }
      _refreshCompleter!.complete(false);
      return false;
    } catch (_) {
      // Non-HTTP failure — don't wipe a potentially valid session.
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.get<T>(path, queryParameters: queryParameters, options: options);
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) {
    return _dio.post<T>(path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
        cancelToken: cancelToken);
  }

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.put<T>(path, data: data, queryParameters: queryParameters, options: options);
  }

  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.patch<T>(path, data: data, queryParameters: queryParameters, options: options);
  }

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.delete<T>(path, data: data, queryParameters: queryParameters, options: options);
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessTokenCache = accessToken;
    _refreshTokenCache = refreshToken;
    try {
      await storage.write(key: _accessTokenKey, value: accessToken);
      await storage.write(key: _refreshTokenKey, value: refreshToken);
    } catch (_) {
      // Keychain write can fail in rare cases; the in-memory cache keeps the
      // session authenticated regardless.
    }
  }

  Future<void> clearTokens() async {
    // Bump the generation so any in-flight refresh won't repopulate tokens.
    _authEpoch++;
    _accessTokenCache = null;
    _refreshTokenCache = null;
    try {
      await storage.delete(key: _accessTokenKey);
      await storage.delete(key: _refreshTokenKey);
    } catch (_) {/* keychain unavailable — ignore */}
  }

  /// Returns the access token from the in-memory cache, falling back to the
  /// keychain. Tolerates a keychain failure (returns null) so a rare
  /// `flutter_secure_storage` error can't crash startup or hang the splash.
  Future<String?> getAccessToken() async {
    if (_accessTokenCache != null) return _accessTokenCache;
    try {
      _accessTokenCache = await storage.read(key: _accessTokenKey);
    } catch (_) {
      _accessTokenCache = null;
    }
    return _accessTokenCache;
  }

  /// Returns the refresh token from cache, falling back to the keychain.
  Future<String?> _getRefreshToken() async {
    if (_refreshTokenCache != null) return _refreshTokenCache;
    try {
      _refreshTokenCache = await storage.read(key: _refreshTokenKey);
    } catch (_) {
      _refreshTokenCache = null;
    }
    return _refreshTokenCache;
  }
}

/// Retries transient errors (5xx, timeout, connection reset) up to [maxRetries]
/// times with exponential backoff.
class _RetryInterceptor extends Interceptor {
  final Dio _dio;
  static const maxRetries = 2;
  static const _retryableStatuses = {500, 502, 503, 504};

  _RetryInterceptor(this._dio);

  bool _shouldRetry(DioException err) {
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }
    final status = err.response?.statusCode;
    return status != null && _retryableStatuses.contains(status);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final attempt = (err.requestOptions.extra['_retryAttempt'] as int?) ?? 0;
    if (!_shouldRetry(err) || attempt >= maxRetries) {
      return handler.next(err);
    }
    // Exponential backoff: 500ms, 1500ms
    await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
    final options = err.requestOptions;
    options.extra['_retryAttempt'] = attempt + 1;
    try {
      final response = await _dio.fetch(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

String apiErrorMessage(DioException e) {
  if (e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.unknown) {
    return 'Нет соединения с интернетом. Проверьте сеть.';
  }
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout) {
    return 'Время ожидания истекло. Попробуйте ещё раз.';
  }
  final statusCode = e.response?.statusCode;
  // Тело ошибки не всегда JSON-объект: сервер (или прокси) может вернуть строку
  // или HTML. Индексация non-Map (`'text'['error']`) кидает рантайм-ошибку прямо
  // внутри обработчика ошибок. Приводим к Map один раз и дальше безопасно.
  final data = e.response?.data;
  final Map? body = data is Map ? data : null;
  if (statusCode == 401) return 'Сессия истекла. Войдите снова.';
  if (statusCode == 403) return 'У вас нет прав для этого действия.';
  if (statusCode == 404) return 'Не найдено.';
  if (statusCode == 422) {
    final errors = body?['errors'];
    if (errors is Map) {
      return errors.values.first?.toString() ?? 'Ошибка валидации.';
    }
    return body?['error']?.toString() ??
        body?['message']?.toString() ??
        'Ошибка валидации.';
  }
  if (statusCode != null && statusCode >= 500) {
    return body?['error']?.toString() ??
        'Ошибка на сервере. Попробуйте ещё раз.';
  }
  return body?['error']?.toString() ??
      body?['message']?.toString() ??
      'Что-то пошло не так.';
}
