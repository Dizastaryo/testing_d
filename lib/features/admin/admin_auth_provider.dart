import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

class AdminAuthState {
  final bool checking;
  final bool authenticated;
  final bool otpSent;
  final bool isLoading;
  final String? error;

  const AdminAuthState({
    this.checking = true,
    this.authenticated = false,
    this.otpSent = false,
    this.isLoading = false,
    this.error,
  });

  AdminAuthState copyWith({
    bool? checking,
    bool? authenticated,
    bool? otpSent,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      AdminAuthState(
        checking: checking ?? this.checking,
        authenticated: authenticated ?? this.authenticated,
        otpSent: otpSent ?? this.otpSent,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

class AdminAuthNotifier extends StateNotifier<AdminAuthState> {
  final ApiClient _api;

  AdminAuthNotifier(this._api) : super(const AdminAuthState()) {
    _bootstrap();
  }

  /// On startup: if there's a saved token, try a privileged endpoint to
  /// confirm it still grants admin access. Otherwise stay logged out.
  Future<void> _bootstrap() async {
    final tok = await _api.getAccessToken();
    if (tok == null || tok.isEmpty) {
      state = const AdminAuthState(checking: false);
      return;
    }
    final granted = await _checkAdminAccess();
    state = AdminAuthState(checking: false, authenticated: granted);
    if (!granted) {
      await _api.clearTokens();
    }
  }

  Future<bool> _checkAdminAccess() async {
    try {
      await _api.get('/admin/metrics');
      return true;
    } on DioException {
      return false;
    }
  }

  Future<bool> sendOtp(String phone) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _api.post('/auth/send-otp', data: {'phone': phone});
      state = state.copyWith(otpSent: true, isLoading: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: apiErrorMessage(e));
      return false;
    }
  }

  Future<bool> verifyOtp(String phone, String code) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final resp = await _api.post('/auth/verify-otp', data: {
        'phone': phone,
        'code': code,
        // Admins are accepting their employer's terms by using the panel.
        'accepts_terms': true,
      });
      final data = resp.data is Map && resp.data.containsKey('data')
          ? resp.data['data']
          : resp.data;
      await _api.saveTokens(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
      );

      if (!await _checkAdminAccess()) {
        await _api.clearTokens();
        state = state.copyWith(
          isLoading: false,
          error: 'У этого аккаунта нет доступа к админке',
        );
        return false;
      }

      state = const AdminAuthState(checking: false, authenticated: true);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: apiErrorMessage(e));
      return false;
    }
  }

  Future<void> logout() async {
    await _api.clearTokens();
    state = const AdminAuthState(checking: false);
  }

  void resetOtp() {
    state = state.copyWith(otpSent: false, clearError: true);
  }
}

final adminAuthProvider =
    StateNotifierProvider<AdminAuthNotifier, AdminAuthState>((ref) {
  final api = ref.watch(apiClientProvider);
  return AdminAuthNotifier(api);
});
