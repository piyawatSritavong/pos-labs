import 'package:flutter/material.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/authentication/auth_gate.dart';
import 'package:frontend/screens/customer_screen.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'POS Labs',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // เส้นทางเริ่มต้น: ใช้ AuthGate สำหรับฝั่งพนักงาน
      initialRoute: '/',
      routes: {
        // หน้าหลัก: ให้ AuthGate จัดการว่าจะไป Login/HomeScreen ตามปกติ
        '/': (context) => const AuthGate(),
        // เส้นทางสำหรับหน้าจอลูกค้าโดยเฉพาะ
        '/customer': (context) => const CustomerScreen(),
      },
    );
  }
}
