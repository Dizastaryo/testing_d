import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/user.dart';

class AuthState {
  final bool isAuthenticated;
  final User? user;
  final bool isLoading;
  final String? error;
  final bool otpSent;
  final bool isNewUser;

  const AuthState({
    this.isAuthenticated = false,
    this.user,
    this.isLoading = false,
    this.error,
    this.otpSent = false,
    this.isNewUser = false,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    User? user,
    bool? isLoading,
    String? error,
    bool? otpSent,
    bool? isNewUser,
    bool clearError = false,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      otpSent: otpSent ?? this.otpSent,
      isNewUser: isNewUser ?? this.isNewUser,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _api;
  final Ref _ref;
  ProviderSubscription<bool>? _onlineSub;

  AuthNotifier(this._api, this._ref) : super(const AuthState(isLoading: true)) {
    _loadInitial();
    // Recovery: if we ever degrade to an authenticated-but-userless session
    // (offline launch / 5xx on /me), refetch the profile the moment the
    // network comes back instead of leaving the user as null forever.
    _onlineSub = _ref.listen<bool>(networkOnlineProvider, (prev, next) {
      if (next == true && state.isAuthenticated && state.user == null) {
        reloadMe();
      }
    });
  }

  @override
  void dispose() {
    _onlineSub?.close();
    super.dispose();
  }

  /// Bounded background retry that fills [AuthState.user] once /me succeeds.
  /// Used after an offline-degrade so the session doesn't stay userless
  /// (which makes own profile resolve to "/unknown" and chat sender id 'me').
  Future<void> _recoverUser() async {
    for (var attempt = 0; attempt < 6; attempt++) {
      if (state.user != null || !state.isAuthenticated) return;
      final delay = Duration(seconds: (2 * (attempt + 1)).clamp(2, 15));
      await Future<void>.delayed(delay);
      if (state.user != null || !state.isAuthenticated) return;
      final ok = await reloadMe();
      if (ok) return;
    }
  }

  Future<void> _loadInitial() async {
    try {
      final token = await _api.getAccessToken();
      if (token != null && token.isNotEmpty) {
        try {
          final response = await _api.get(ApiEndpoints.me);
          final data = response.data;
          final userData = data is Map && data.containsKey('data') ? data['data'] : data;
          final user = User.fromJson(userData as Map<String, dynamic>);
          state = AuthState(isAuthenticated: true, user: user);
          return;
        } on DioException catch (e) {
          final code = e.response?.statusCode;
          if (code == 401 || code == 403) {
            // Definitive auth rejection — the stored token is truly dead.
            await _api.clearTokens();
          } else {
            // Network blip / offline launch / 5xx: the token is still valid.
            // Keep the session and degrade to offline instead of logging a
            // valid user out; recovery refetches once back online.
            state = const AuthState(isAuthenticated: true);
            unawaited(_recoverUser());
            return;
          }
        } catch (_) {
          // Non-HTTP failure (e.g. malformed body) — not an auth rejection.
          // Preserve the session rather than wiping a valid login.
          state = const AuthState(isAuthenticated: true);
          unawaited(_recoverUser());
          return;
        }
      }
    } catch (_) {
      // Never let startup hang on the splash: any failure (e.g. keychain
      // unavailable) degrades to "logged out".
    }
    state = const AuthState();
  }

  Future<bool> sendOtp(String phone) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _api.post(ApiEndpoints.sendOtp, data: {'phone': phone});
      state = state.copyWith(isLoading: false, otpSent: true);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: apiErrorMessage(e),
      );
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> verifyOtp(String phone, String code,
      {bool acceptsTerms = false, String? inviteCode}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await _api.post(
        ApiEndpoints.verifyOtp,
        data: {
          'phone': phone,
          'code': code,
          'accepts_terms': acceptsTerms,
          if (inviteCode != null && inviteCode.isNotEmpty)
            'invite_code': inviteCode,
        },
      );

      final data = response.data;
      final tokenData = data is Map && data.containsKey('data') ? data['data'] : data;

      final accessToken = tokenData['access_token'] as String;
      final refreshToken = tokenData['refresh_token'] as String;
      final isNewUser = tokenData['is_new_user'] as bool? ?? false;
      final userData = tokenData['user'] as Map<String, dynamic>;
      final user = User.fromJson(userData);

      await _api.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      state = AuthState(
        isAuthenticated: true,
        user: user,
        isNewUser: isNewUser,
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: apiErrorMessage(e),
      );
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _api.post(ApiEndpoints.logout);
    } catch (_) {}
    await _api.clearTokens();
    state = const AuthState();
  }

  /// Permanently deletes the account on the server, then clears local session.
  /// Throws DioException on server error so the UI can show a message.
  Future<void> deleteAccount() async {
    await _api.delete(ApiEndpoints.deleteMe);
    await _api.clearTokens();
    state = const AuthState();
  }

  void updateUser(User user) {
    state = state.copyWith(user: user);
  }

  /// Re-fetches `/users/me` and replaces the cached user. Use after profile
  /// edits, chip binding, etc. so the UI gets fresh state.
  Future<bool> reloadMe() async {
    try {
      final r = await _api.get(ApiEndpoints.me);
      final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
      state = state.copyWith(user: User.fromJson(data as Map<String, dynamic>));
      return true;
    } catch (e) {
      debugPrint('[auth] reloadMe failed: $e');
      return false;
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void resetOtpState() {
    state = state.copyWith(otpSent: false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final api = ref.watch(apiClientProvider);
  return AuthNotifier(api, ref);
});
