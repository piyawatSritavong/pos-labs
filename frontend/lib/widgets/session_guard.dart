import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/services/api_service.dart';

/// เฝ้าดู session ของ account ที่ login อยู่:
///
/// - ถ้ามีคน login ซ้อนด้วย account เดียวกันจากที่อื่น → แสดง dialog ให้เลือก
///   "ให้ฉันอยู่ต่อ" (เตะ session อื่นออก) หรือ "ให้ฉันออก" (logout ตัวเอง)
/// - ถ้า session นี้ถูกอีกฝั่งเตะออก (ฝั่งโน้นกด "ให้ฉันอยู่ต่อ") → แจ้งแล้วพา
///   กลับหน้า login
///
/// ครอบไว้รอบหน้า POS และ Backoffice หน้าละหนึ่งตัว (หน้า POS ที่ฝังใน
/// Backoffice ไม่ต้องครอบซ้ำ)
class SessionGuard extends StatefulWidget {
  const SessionGuard({super.key, required this.child});

  final Widget child;

  @override
  State<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends State<SessionGuard> {
  static const _pollInterval = Duration(seconds: 8);

  Timer? _timer;
  bool _busy = false; // dialog เปิดอยู่ / คำขอกำลังทำงาน — ข้ามรอบ poll

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_pollInterval, (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (!mounted || _busy) return;
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || auth.isCustomerDisplay) return;

    Map<String, dynamic>? result;
    try {
      result = await ApiService.getSessions(token);
    } catch (_) {
      return; // network ล่มชั่วคราว — รอบหน้าค่อยลองใหม่
    }
    if (!mounted) return;

    if (result == null) {
      // session นี้ถูกเตะออกแล้ว (อีกฝั่งกด "ให้ฉันอยู่ต่อ") หรือหมดอายุ
      _busy = true;
      await _forceLogout(
        'บัญชีนี้ถูกใช้งานจากเครื่องอื่น คุณถูกออกจากระบบ',
      );
      return;
    }

    if (result['othersActive'] == true) {
      _busy = true;
      await _showConflictDialog(auth, token);
      _busy = false;
    }
  }

  Future<void> _showConflictDialog(AuthProvider auth, String token) async {
    final who = auth.username ?? auth.name ?? '';
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(child: Text('มีการเข้าสู่ระบบซ้อน')),
          ],
        ),
        content: Text(
          'บัญชี "$who" กำลังถูกใช้งานจากเครื่องอื่นในขณะนี้\n'
          'ต้องการใช้งานที่เครื่องนี้ต่อหรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('leave'),
            child: const Text('ให้ฉันออก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('stay'),
            child: const Text('ให้ฉันอยู่ต่อ'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (action == 'stay') {
      try {
        await ApiService.revokeOtherSessions(token);
      } catch (_) {
        // เตะไม่สำเร็จ (เช่น token เพิ่งถูกเตะเอง) — รอบ poll ถัดไปจัดการต่อ
      }
    } else if (action == 'leave') {
      await _forceLogout(null);
    }
  }

  Future<void> _forceLogout(String? message) async {
    final auth = context.read<AuthProvider>();
    await auth.logout();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
