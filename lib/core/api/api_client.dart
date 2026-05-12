import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_endpoints.dart';

const _accessTokenKey = 'access_token';
const _refreshTokenKey = 'refresh_token';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return ApiClient(storage: storage);
});

class ApiClient {
  late final Dio _dio;
  final FlutterSecureStorage storage;
  bool _isRefreshing = false;

  ApiClient({required this.storage}) {
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
    final token = await storage.read(key: _accessTokenKey);
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  void _onResponse(Response response, ResponseInterceptorHandler handler) {
    handler.next(response);
  }

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      final refreshed = await refreshTokens();
      if (refreshed) {
        final retryOptions = err.requestOptions;
        final newToken = await storage.read(key: _accessTokenKey);
        if (newToken != null) {
          retryOptions.headers['Authorization'] = 'Bearer $newToken';
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
    if (_isRefreshing) {
      // Another caller is mid-refresh — wait for them to finish, then report
      // whether storage has a fresh access token.
      while (_isRefreshing) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      final tok = await storage.read(key: _accessTokenKey);
      return tok != null && tok.isNotEmpty;
    }
    _isRefreshing = true;
    try {
      final refreshToken = await storage.read(key: _refreshTokenKey);
      if (refreshToken == null || refreshToken.isEmpty) {
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
      if (newAccessToken == null) return false;
      await storage.write(key: _accessTokenKey, value: newAccessToken);
      if (newRefreshToken != null) {
        await storage.write(key: _refreshTokenKey, value: newRefreshToken);
      }
      return true;
    } catch (_) {
      // Refresh-token itself rejected — wipe credentials so the app drops to
      // login-screen on next gated screen instead of looping.
      await storage.delete(key: _accessTokenKey);
      await storage.delete(key: _refreshTokenKey);
      return false;
    } finally {
      _isRefreshing = false;
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
  }) {
    return _dio.post<T>(path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress);
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
    await storage.write(key: _accessTokenKey, value: accessToken);
    await storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<void> clearTokens() async {
    await storage.delete(key: _accessTokenKey);
    await storage.delete(key: _refreshTokenKey);
  }

  Future<String?> getAccessToken() => storage.read(key: _accessTokenKey);
}

String apiErrorMessage(DioException e) {
  if (e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.unknown) {
    return 'No internet connection. Please check your network.';
  }
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout) {
    return 'Connection timed out. Please try again.';
  }
  final statusCode = e.response?.statusCode;
  if (statusCode == 401) return 'Session expired. Please log in again.';
  if (statusCode == 403) return 'You do not have permission to do that.';
  if (statusCode == 404) return 'Not found.';
  if (statusCode == 422) {
    final errors = e.response?.data?['errors'];
    if (errors is Map) {
      return errors.values.first?.toString() ?? 'Validation error.';
    }
    return e.response?.data?['message']?.toString() ?? 'Validation error.';
  }
  if (statusCode != null && statusCode >= 500) {
    return 'Something went wrong on the server. Please try again.';
  }
  return e.response?.data?['message']?.toString() ?? 'Something went wrong.';
}
