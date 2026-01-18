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
}