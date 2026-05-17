// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:frontend/app.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/bill_provider.dart';
import 'package:frontend/providers/branches_provider.dart';
import 'package:frontend/providers/company_provider.dart';
import 'package:frontend/providers/users_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
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
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MyApp(),
    ),
  );

  HomeScreen.openCustomerWindowFn = () {
    // ignore: discarded_futures
    _openCustomerWindow();
  };
}

/// เปิดหน้าจอลูกค้าในจอ 2 (ถ้ามี) โดยใช้ Window Management API ของ Edge/Chrome
/// ครั้งแรก browser จะ prompt "Allow this site to manage windows on all your displays"
/// ถ้าไม่ได้รับอนุญาต / รองรับ → fallback เป็น popup ตำแหน่งเดิม (ผู้ใช้ลากเองได้)
Future<void> _openCustomerWindow() async {
  final origin = html.window.location.origin;
  final path = html.window.location.pathname;
  final customerUrl = '$origin$path#/customer';

  final secondary = await _findSecondaryScreen();

  final String features;
  if (secondary != null) {
    final l = secondary['left']!.toInt();
    final t = secondary['top']!.toInt();
    final w = secondary['width']!.toInt();
    final h = secondary['height']!.toInt();
    features =
        'noopener,noreferrer,toolbar=no,menubar=no,'
        'left=$l,top=$t,width=$w,height=$h';
  } else {
    features =
        'noopener,noreferrer,toolbar=no,menubar=no,'
        'width=1024,height=768,left=100,top=100';
  }

  html.window.open(customerUrl, '_blank', features);
}

/// คืนค่าพิกัด available ของจอที่ไม่ใช่ primary (จอ 2) ผ่าน Window Management API
/// คืน null ถ้า API ไม่รองรับ, ผู้ใช้ deny permission, หรือมีจอเดียว
Future<Map<String, num>?> _findSecondaryScreen() async {
  try {
    final dynamic details = await (html.window as dynamic).getScreenDetails();
    final dynamic screensRaw = details.screens;
    final List<dynamic> screens = List.from(screensRaw as Iterable<dynamic>);
    for (final s in screens) {
      final dynamic screen = s;
      final isPrimary = screen.isPrimary as bool? ?? false;
      if (!isPrimary) {
        return {
          'left': screen.availLeft as num,
          'top': screen.availTop as num,
          'width': screen.availWidth as num,
          'height': screen.availHeight as num,
        };
      }
    }
  } catch (_) {
    // permission denied / API unsupported — fall through to null
  }
  return null;
}
