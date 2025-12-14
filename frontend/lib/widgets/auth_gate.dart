import 'package:frontend/screens/office_screen.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/screens/login_screen.dart';
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
    // Auto-login when app starts
    Future.delayed(Duration.zero, () {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      auth.autoLogin();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        // Show loading while checking auth
        if (auth.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (auth.isAuthenticated) {
          if (auth.isAdmin) {
            // ถ้าเป็น role.admin ให้เข้าโหมดหลังบ้าน
            return const OfficeScreen();
          }
          // ถ้าไม่ใช่ admin ให้เข้าโหมดหน้าบ้านปกติ
          return const HomeScreen(); // Replace with your main app screen
        }

        return const LoginScreen(); // Replace with your login screen
      },
    );
  }
}
