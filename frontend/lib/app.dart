import 'package:flutter/material.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/authentication/auth_gate.dart';
import 'package:frontend/screens/customer_screen.dart';
import 'package:provider/provider.dart';

class _MobileFontReducer extends TextScaler {
  const _MobileFontReducer(this.base);

  static const double _reduction = 10;
  static const double _minFontSize = 8;

  final TextScaler base;

  @override
  double scale(double fontSize) {
    final scaled = base.scale(fontSize) - _reduction;
    return scaled < _minFontSize ? _minFontSize : scaled;
  }

  @override
  double get textScaleFactor => 1.0;

  @override
  bool operator ==(Object other) {
    return other is _MobileFontReducer && other.base == base;
  }

  @override
  int get hashCode => base.hashCode;
}

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
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          final isMobile = mediaQuery.size.shortestSide < 600;
          if (!isMobile) {
            return child ?? const SizedBox.shrink();
          }

          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: _MobileFontReducer(mediaQuery.textScaler),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}
