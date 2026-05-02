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

    return Scaffold(
      backgroundColor: SeeUColors.background,
      body: const Center(
        child: CircularProgressIndicator(color: SeeUColors.accent),
      ),
    );
  }
}
