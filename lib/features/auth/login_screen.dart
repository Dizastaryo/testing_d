import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/design/design.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpControllers = List.generate(4, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(4, (_) => FocusNode());
  bool _showOtp = false;
  String _phone = '';

  @override
  void dispose() {
    _phoneCtrl.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _rawPhone {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    return '+7$digits';
  }

  Future<void> _sendOtp() async {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length != 10) return;

    _phone = _rawPhone;
    final success = await ref.read(authProvider.notifier).sendOtp(_phone);
    if (success && mounted) {
      setState(() => _showOtp = true);
      _otpFocusNodes[0].requestFocus();
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otpControllers.map((c) => c.text).join();
    if (code.length != 4) return;

    final success = await ref.read(authProvider.notifier).verifyOtp(_phone, code);
    if (success && mounted) {
      context.go('/feed');
    }
  }

  void _onOtpChanged(int index, String value) {
    if (value.length == 1 && index < 3) {
      _otpFocusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }
    final code = _otpControllers.map((c) => c.text).join();
    if (code.length == 4) {
      _verifyOtp();
    }
  }

  void _goBack() {
    setState(() {
      _showOtp = false;
      for (final c in _otpControllers) {
        c.clear();
      }
    });
    ref.read(authProvider.notifier).resetOtpState();
    ref.read(authProvider.notifier).clearError();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: SeeUColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 72),

              // Logo
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOut,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: child,
                  ),
                ),
                child: Text(
                  'SeeU',
                  style: SeeUTypography.displayXL,
                ),
              ),
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  final delayed = ((value - 0.15) / 0.85).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: delayed,
                    child: Transform.translate(
                      offset: Offset(0, 16 * (1 - delayed)),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  'Связь с миром',
                  style: SeeUTypography.body.copyWith(
                    color: SeeUColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 48),

              // Error banner
              if (authState.error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: SeeUColors.accentSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    authState.error!,
                    style: SeeUTypography.caption.copyWith(color: SeeUColors.accent),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),
              ],

              if (!_showOtp) ..._buildPhoneStep(authState),
              if (_showOtp) ..._buildOtpStep(authState),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPhoneStep(AuthState authState) {
    return [
      // Phone label
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Номер телефона',
          style: SeeUTypography.subtitle.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Введите номер для входа или регистрации',
          style: SeeUTypography.caption.copyWith(color: SeeUColors.textSecondary),
        ),
      ),
      const SizedBox(height: 20),

      // Phone input
      Row(
        children: [
          // Country code
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: SeeUColors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SeeUColors.borderSubtle),
            ),
            child: Center(
              child: Text(
                '+7',
                style: SeeUTypography.subtitle.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Phone number
          Expanded(
            child: SeeUInput(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _sendOtp(),
              hintText: '700 330 96 16',
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
                _PhoneFormatter(),
              ],
              prefix: Icon(
                PhosphorIcons.phone(PhosphorIconsStyle.regular),
                size: 20,
                color: SeeUColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),

      // Send OTP button
      SeeUButton(
        label: 'Получить код',
        variant: SeeUButtonVariant.primary,
        isLoading: authState.isLoading,
        onTap: authState.isLoading ? null : _sendOtp,
      ),
    ];
  }

  List<Widget> _buildOtpStep(AuthState authState) {
    return [
      // Back button
      Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: _goBack,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular),
                  size: 20, color: SeeUColors.accent),
              const SizedBox(width: 4),
              Text('Изменить номер',
                  style: SeeUTypography.caption.copyWith(color: SeeUColors.accent)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),

      // OTP label
      Text(
        'Введите код',
        style: SeeUTypography.subtitle.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Text(
        'Код отправлен на $_phone',
        style: SeeUTypography.caption.copyWith(color: SeeUColors.textSecondary),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text(
        'Для тестирования введите 0000',
        style: SeeUTypography.micro.copyWith(color: SeeUColors.accent),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),

      // OTP inputs
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          return Container(
            width: 56,
            height: 64,
            margin: EdgeInsets.only(right: i < 3 ? 12 : 0),
            child: TextField(
              controller: _otpControllers[i],
              focusNode: _otpFocusNodes[i],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 1,
              style: SeeUTypography.displayXL.copyWith(fontSize: 24),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: SeeUColors.surfaceElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: SeeUColors.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: SeeUColors.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: SeeUColors.accent, width: 2),
                ),
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) => _onOtpChanged(i, v),
            ),
          );
        }),
      ),
      const SizedBox(height: 24),

      // Verify button
      SeeUButton(
        label: 'Подтвердить',
        variant: SeeUButtonVariant.primary,
        isLoading: authState.isLoading,
        onTap: authState.isLoading ? null : _verifyOtp,
      ),
      const SizedBox(height: 16),

      // Resend
      GestureDetector(
        onTap: authState.isLoading ? null : _sendOtp,
        child: Text(
          'Отправить код повторно',
          style: SeeUTypography.caption.copyWith(
            color: SeeUColors.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ];
  }
}

class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');

    String formatted = '';
    for (int i = 0; i < digits.length && i < 10; i++) {
      if (i == 3 || i == 6 || i == 8) formatted += ' ';
      formatted += digits[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
