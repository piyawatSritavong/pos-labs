import 'package:flutter/material.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/authentication/auth_gate.dart';
import 'package:frontend/screens/customer_screen.dart';
import 'package:provider/provider.dart';
import 'package:frontend/services/app_dialog_service.dart';

class _MobileFontReducer extends TextScaler {
  const _MobileFontReducer(this.base);

  static const double _reduction = 8;
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
        navigatorKey: appNavigatorKey,
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

          final theme = Theme.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: _MobileFontReducer(mediaQuery.textScaler),
            ),
            child: Theme(
              data: _compactMobileTheme(theme),
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }

  ThemeData _compactMobileTheme(ThemeData theme) {
    const compactPadding = EdgeInsets.all(6);
    const compactHorizontalPadding = EdgeInsets.symmetric(horizontal: 6);
    const compactButtonSize = Size(0, 34);

    return theme.copyWith(
      visualDensity: VisualDensity.compact,
      cardTheme: theme.cardTheme.copyWith(margin: compactPadding),
      dialogTheme: theme.dialogTheme.copyWith(
        insetPadding: compactPadding,
        actionsPadding: compactPadding,
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        isDense: true,
        contentPadding: compactPadding,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: (theme.elevatedButtonTheme.style ?? const ButtonStyle())
            .copyWith(
              minimumSize: const WidgetStatePropertyAll(compactButtonSize),
              padding: const WidgetStatePropertyAll(compactHorizontalPadding),
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: (theme.outlinedButtonTheme.style ?? const ButtonStyle())
            .copyWith(
              minimumSize: const WidgetStatePropertyAll(compactButtonSize),
              padding: const WidgetStatePropertyAll(compactHorizontalPadding),
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
          minimumSize: const WidgetStatePropertyAll(compactButtonSize),
          padding: const WidgetStatePropertyAll(compactHorizontalPadding),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: (theme.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      listTileTheme: theme.listTileTheme.copyWith(
        contentPadding: compactHorizontalPadding,
        minVerticalPadding: 0,
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
