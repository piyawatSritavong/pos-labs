import 'package:flutter/material.dart';
import 'package:frontend/app.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/cart_provider.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
      ],
      child: const MyApp(),
    ),
  );
}
