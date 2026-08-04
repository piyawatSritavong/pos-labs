import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/services/app_dialog_service.dart';

void main() {
  testWidgets('shows a safe standard error dialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AppDialogService.showError(
                  context,
                  error: Exception('SQLSTATE should stay hidden'),
                  fallback: 'โหลดข้อมูลไม่สำเร็จ',
                  allowRetry: true,
                );
              },
              child: const Text('เปิด'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('เปิด'));
    await tester.pumpAndSettle();

    expect(find.text('เกิดข้อผิดพลาด'), findsOneWidget);
    expect(find.text('โหลดข้อมูลไม่สำเร็จ'), findsOneWidget);
    expect(find.text('ลองใหม่'), findsOneWidget);
    expect(find.textContaining('SQLSTATE'), findsNothing);
  });
}
