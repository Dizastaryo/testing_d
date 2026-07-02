import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/design/design.dart';

/// Registration is handled automatically via phone+OTP in LoginScreen.
/// This screen just redirects to login.
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // With phone auth, registration happens automatically on first OTP verify.
    // Redirect to login screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.go('/login');
    });

    // Pure redirect stub — a bare theme-aware cream canvas while the router
    // swaps to /login on the next frame.
    return Scaffold(
      backgroundColor: context.seeuColors.bg,
      body: const SizedBox.shrink(),
    );
  }
}
