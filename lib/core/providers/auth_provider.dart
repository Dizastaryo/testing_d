import 'package:dio/dio.dart';
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

  AuthNotifier(this._api) : super(const AuthState(isLoading: true)) {
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final token = await _api.getAccessToken();
    if (token != null && token.isNotEmpty) {
      try {
        final response = await _api.get(ApiEndpoints.me);
        final data = response.data;
        final userData = data is Map && data.containsKey('data') ? data['data'] : data;
        final user = User.fromJson(userData as Map<String, dynamic>);
        state = AuthState(isAuthenticated: true, user: user);
        return;
      } catch (_) {
        await _api.clearTokens();
      }
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

  Future<bool> verifyOtp(String phone, String code) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await _api.post(
        ApiEndpoints.verifyOtp,
        data: {'phone': phone, 'code': code},
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

  void updateUser(User user) {
    state = state.copyWith(user: user);
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
  return AuthNotifier(api);
});
