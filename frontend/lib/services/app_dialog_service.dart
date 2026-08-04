import 'package:flutter/material.dart';

import 'api_exception.dart';
import 'api_http.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class AppDialogService {
  AppDialogService._();

  static bool _authDialogOpen = false;

  static String safeMessage(
    Object error, {
    String fallback = 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง',
  }) {
    if (error is ApiException) return error.message;
    final raw = error.toString();
    if (raw.contains('barcode_already_exists')) {
      return 'Barcode นี้ถูกใช้งานกับสินค้าอื่นแล้ว';
    }
    if (raw.contains('invalid_credentials')) {
      return 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง';
    }
    if (raw.contains('login_already_pending')) {
      return 'มีคำขอเข้าสู่ระบบของบัญชีนี้รอการยืนยันอยู่แล้ว';
    }
    return fallback;
  }

  static Future<bool> showError(
    BuildContext context, {
    required Object error,
    String title = 'เกิดข้อผิดพลาด',
    String fallback = 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง',
    bool allowRetry = false,
  }) async {
    if (ApiHttpEvents.hasRecentAuthFailure) return false;
    final retry = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(safeMessage(error, fallback: fallback)),
        actions: [
          if (allowRetry)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ปิด'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(allowRetry),
            child: Text(allowRetry ? 'ลองใหม่' : 'ตกลง'),
          ),
        ],
      ),
    );
    return retry == true;
  }

  static Future<void> showSessionExpired(
    BuildContext context,
    Future<void> Function() clearSession,
  ) async {
    if (_authDialogOpen) return;
    _authDialogOpen = true;
    BuildContext? dialogContext;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (currentDialogContext) {
        dialogContext = currentDialogContext;
        return const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Expanded(child: Text('การล็อกอินหมดอายุ')),
              ],
            ),
          ),
        );
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final currentDialogContext = dialogContext;
    if (currentDialogContext != null && currentDialogContext.mounted) {
      Navigator.of(currentDialogContext).pop();
    }
    await clearSession();
    _authDialogOpen = false;
  }
}
