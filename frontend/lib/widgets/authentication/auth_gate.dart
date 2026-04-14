import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/screens/customer_screen.dart';
import 'package:frontend/screens/backoffice_screen.dart';
import 'package:frontend/providers/auth_provider.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    // Auto-login
    Future.delayed(Duration.zero, () {
      if (!mounted) return;
      final auth = Provider.of<AuthProvider>(context, listen: false);
      auth.autoLogin();
    });
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
          if (auth.hasBackofficeAccess) return const BackofficeScreen();
          return const HomeScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
