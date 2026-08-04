import 'dart:async';

import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/screens/customer_screen.dart';
import 'package:frontend/screens/backoffice_screen.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/widgets/authentication/session_guard.dart';
import 'package:frontend/services/api_http.dart';
import 'package:frontend/services/app_dialog_service.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<ApiAuthFailure>? _authFailureSubscription;

  @override
  void initState() {
    super.initState();
    _authFailureSubscription = ApiHttpEvents.authFailures.listen((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      AppDialogService.showSessionExpired(context, auth.expireSession);
    });
    // Auto-login
    Future.delayed(Duration.zero, () {
      if (!mounted) return;
      final auth = Provider.of<AuthProvider>(context, listen: false);
      auth.autoLogin();
    });
  }

  @override
  void dispose() {
    _authFailureSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (auth.isCustomerDisplay) {
          return const CustomerScreen();
        }

        if (auth.isAuthenticated) {
          final destination = auth.hasBackofficeAccess
              ? const BackofficeScreen()
              : const HomeScreen();
          return SessionGuard(child: destination);
        }

        return const LoginScreen();
      },
    );
  }
}
