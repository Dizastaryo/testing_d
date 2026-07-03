import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'admin_auth_provider.dart';

class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  String get _phone {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    return '+$digits';
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(adminAuthProvider);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'SeeU Admin',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  auth.otpSent
                      ? 'Введите код подтверждения'
                      : 'Войдите телефоном с правами администратора',
                  style: TextStyle(color: Colors.grey.shade700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (!auth.otpSent) _phoneField(auth) else _otpField(auth),
                if (auth.error != null) ...[
                  const SizedBox(height: 12),
                  _errorBanner(auth.error!),
                ],
                if (auth.otpSent) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () =>
                        ref.read(adminAuthProvider.notifier).resetOtp(),
                    child: const Text('Изменить номер'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneField(AdminAuthState auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          autofocus: true,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(15),
          ],
          decoration: const InputDecoration(
            labelText: 'Номер телефона (цифры, начиная с 7)',
            hintText: '77003309616',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: auth.isLoading
              ? null
              : () => ref.read(adminAuthProvider.notifier).sendOtp(_phone),
          child: auth.isLoading
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Получить код'),
        ),
      ],
    );
  }

  Widget _otpField(AdminAuthState auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          maxLength: 4,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, letterSpacing: 12, fontFeatures: [FontFeature.tabularFigures()]),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          decoration: const InputDecoration(counterText: ''),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: auth.isLoading
              ? null
              : () => ref
                  .read(adminAuthProvider.notifier)
                  .verifyOtp(_phone, _codeCtrl.text),
          child: auth.isLoading
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Войти'),
        ),
      ],
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEFEC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE74C3C).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsRegular.warningCircle, color: Color(0xFFE74C3C), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(color: Color(0xFFB02F1F))),
          ),
        ],
      ),
    );
  }
}
