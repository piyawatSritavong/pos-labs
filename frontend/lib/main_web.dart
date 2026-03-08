// ignore: deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:frontend/app.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/bill_provider.dart';
import 'package:frontend/providers/branches_provider.dart';
import 'package:frontend/providers/company_provider.dart';
import 'package:frontend/providers/users_provider.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => BillProvider()),
        ChangeNotifierProvider(create: (_) => UsersProvider()),
        ChangeNotifierProvider(create: (_) => CompanyProvider()),
        ChangeNotifierProvider(create: (_) => BranchesProvider()),
      ],
      child: const MyApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    final href = html.window.location.href;
    if (href.contains('#/customer') || href.endsWith('/customer')) {
      return;
    }

    final origin = html.window.location.origin;
    final path = html.window.location.pathname;
    final baseUrl = '$origin$path';

    final customerUrl = '$baseUrl#/customer';

    html.window.open(
      customerUrl,
      '_blank',
      'noopener,noreferrer,toolbar=no,menubar=no,width=1024,height=768,left=100,top=100',
    );
  });
}