import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_config.dart';
import '../../core/config/server_config.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/invites_provider.dart';
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
  bool _acceptsTerms = false;
  String _phone = '';
  // Invite code captured from the URL (?invite=...). Sent to backend on
  // verify-otp so the inviter gets credit when this user registers.
  String? _inviteCode;
  final _privacyRecognizer = TapGestureRecognizer();
  final _termsRecognizer = TapGestureRecognizer();

  @override
  void initState() {
    super.initState();
    final fromUri =
        Uri.base.queryParameters['invite'] ?? Uri.base.queryParameters['i'];
    if (fromUri != null && fromUri.isNotEmpty) {
      _inviteCode = fromUri.trim().toLowerCase();
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    _privacyRecognizer.dispose();
    _termsRecognizer.dispose();
    super.dispose();
  }

  // TODO: добавить выбор страны (country picker) — пока захардкожен +7 (KZ/RU).
  // При реализации: _countryCode как State-поле, dropdown перед полем ввода.
  static const _countryCode = '+7';

  String get _rawPhone {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    return '$_countryCode$digits';
  }

  Future<void> _sendOtp() async {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length != 10) return;
    if (!_acceptsTerms) return;

    _phone = _rawPhone;
    final success = await ref.read(authProvider.notifier).sendOtp(_phone);
    if (success && mounted) {
      setState(() => _showOtp = true);
      _otpFocusNodes[0].requestFocus();
    }
  }

  bool _isVerifying = false;

  Future<void> _verifyOtp() async {
    final code = _otpControllers.map((c) => c.text).join();
    if (code.length != 4 || _isVerifying) return;
    _isVerifying = true;

    final success = await ref.read(authProvider.notifier).verifyOtp(
          _phone,
          code,
          acceptsTerms: _acceptsTerms,
          inviteCode: _inviteCode,
        );
    _isVerifying = false;
    if (success && mounted) {
      context.go('/feed');
    }
  }

  Future<void> _showIpDialog(BuildContext context) async {
    final ctrl = TextEditingController(text: ServerConfig.lanIp);
    await showSeeUBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final c = ctx.seeuColors;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            8,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'СЕРВЕР',
                style: SeeUTypography.kicker.copyWith(color: c.ink3),
              ),
              const SizedBox(height: 2),
              Text(
                'Адрес сервера',
                style: SeeUTypography.displayS.copyWith(color: c.ink),
              ),
              const SizedBox(height: 4),
              Text(
                'LAN IP-адрес компьютера с бэкендом',
                style: SeeUTypography.caption.copyWith(color: c.ink2),
              ),
              const SizedBox(height: 16),
              SeeUInput(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                hintText: '192.168.1.2',
                prefix: Icon(PhosphorIconsRegular.wifiHigh, size: 18, color: c.ink3),
              ),
              const SizedBox(height: 20),
              SeeUButton(
                label: 'Сохранить',
                variant: SeeUButtonVariant.primary,
                onTap: () async {
                  final ip = ctrl.text.trim();
                  if (ip.isEmpty) return;
                  await ServerConfig.setLanIp(ip);
                  if (ctx.mounted) {
                    // Rebuild all Dio providers with new IP
                    ref.read(serverIpProvider.notifier).state = ip;
                    Navigator.of(ctx).pop();
                  }
                },
              ),
            ],
          ),
        );
      },
    );
    ctrl.dispose();
  }

  Future<void> _openLegal(String path) async {
    final uri = Uri.parse('${AppConfig.apiOrigin}$path');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
    final c = context.seeuColors;
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 72),

              // Logo (long-press → настройки IP сервера)
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
                child: GestureDetector(
                  onLongPress: () => _showIpDialog(context),
                  child: Text(
                    'SeeU',
                    style: SeeUTypography.displayXL
                        .copyWith(fontFamily: AppFonts.I.brand, letterSpacing: 0),
                  ),
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
                  'СВЯЗЬ С МИРОМ',
                  style: SeeUTypography.kicker.copyWith(color: c.ink3),
                ),
              ),
              const SizedBox(height: 48),

              // Error banner
              if (authState.error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(SeeURadii.medium),
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
    final c = context.seeuColors;
    return [
      if (_inviteCode != null && _inviteCode!.isNotEmpty)
        _InviteBanner(code: _inviteCode!),
      if (_inviteCode != null && _inviteCode!.isNotEmpty)
        const SizedBox(height: 20),
      // Kicker над блоком логина
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'ВХОД',
          style: SeeUTypography.kicker.copyWith(color: SeeUColors.accent),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Введите номер для входа или регистрации',
          style: SeeUTypography.caption.copyWith(color: c.ink2),
        ),
      ),
      const SizedBox(height: 24),

      // Phone label — eyebrow
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'НОМЕР ТЕЛЕФОНА',
          style: SeeUTypography.kicker.copyWith(color: c.ink3),
        ),
      ),
      const SizedBox(height: 8),

      // Phone input
      Row(
        children: [
          // Country code — тот же fill/радиус, что у SeeUInput рядом (единый вид).
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                _countryCode,
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
      const SizedBox(height: 16),

      // Consent checkbox + links to legal docs
      _buildConsent(),

      const SizedBox(height: 16),

      // Send OTP button — disabled until consent is given
      SeeUButton(
        label: 'Получить код',
        variant: SeeUButtonVariant.primary,
        isLoading: authState.isLoading,
        onTap: (authState.isLoading || !_acceptsTerms) ? null : _sendOtp,
      ),
    ];
  }

  Widget _buildConsent() {
    final c = context.seeuColors;
    final linkStyle = TextStyle(
      color: SeeUColors.accent,
      decoration: TextDecoration.underline,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: _acceptsTerms,
            onChanged: (v) => setState(() => _acceptsTerms = v ?? false),
            activeColor: SeeUColors.accent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: RichText(
              text: TextSpan(
                style: SeeUTypography.caption.copyWith(color: c.ink2),
                children: [
                  const TextSpan(text: 'Принимаю '),
                  TextSpan(
                    text: 'Политику конфиденциальности',
                    style: linkStyle,
                    recognizer: _privacyRecognizer..onTap = () => _openLegal('/privacy'),
                  ),
                  const TextSpan(text: ' и '),
                  TextSpan(
                    text: 'Условия использования',
                    style: linkStyle,
                    recognizer: _termsRecognizer..onTap = () => _openLegal('/terms'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildOtpStep(AuthState authState) {
    final c = context.seeuColors;
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
        style: SeeUTypography.caption.copyWith(color: c.ink2),
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
                fillColor: c.surface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SeeURadii.medium),
                  borderSide: BorderSide(color: c.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SeeURadii.medium),
                  borderSide: BorderSide(color: c.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SeeURadii.medium),
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

/// Friendly banner shown on the auth screen when the user landed via an
/// invite link (`?invite=CODE`). Resolves the code against the public
/// `/invites/:code` endpoint and shows the inviter's name + avatar.
class _InviteBanner extends ConsumerWidget {
  final String code;
  const _InviteBanner({required this.code});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(inviteLookupProvider(code));
    return async.when(
      loading: () => const SizedBox(height: 56),
      error: (_, __) => const SizedBox.shrink(),
      data: (inv) {
        if (inv == null) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.accentSoft,
            borderRadius: BorderRadius.circular(SeeURadii.medium),
            border: Border.all(color: SeeUColors.accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: c.surface2,
                backgroundImage: inv.inviterAvatarUrl.isNotEmpty
                    ? NetworkImage(inv.inviterAvatarUrl)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ПРИГЛАШЕНИЕ',
                        style: SeeUTypography.kicker
                            .copyWith(color: SeeUColors.accent)),
                    const SizedBox(height: 3),
                    Text('@${inv.inviterUsername}',
                        style: SeeUTypography.body
                            .copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
