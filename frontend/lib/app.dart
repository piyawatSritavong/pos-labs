import 'package:flutter/material.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/authentication/auth_gate.dart';
import 'package:frontend/screens/customer_screen.dart';
import 'package:provider/provider.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) => MaterialApp(
        title: 'POS Labs',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeProvider.mode,
        initialRoute: '/',
        routes: {
          '/': (context) => const AuthGate(),
          '/customer': (context) => const CustomerScreen(),
        },
      ),
    );
  }
}
