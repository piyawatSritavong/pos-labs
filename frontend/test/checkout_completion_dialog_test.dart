import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/pos/checkout_completion_dialog.dart';

void main() {
  testWidgets('confirms a completed sale and shows the bill number', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CheckoutCompletionDialog(
            hasPurchaseItems: true,
            hasReturnItems: false,
            allReceiptsPrinted: true,
            billId: '20260928000003',
          ),
        ),
      ),
    );

    expect(find.text('ดำเนินการเสร็จสิ้น'), findsOneWidget);
    expect(
      find.text('ปิดการขายบิลเลขที่ 20260928000003 เรียบร้อยแล้ว'),
      findsOneWidget,
    );
    expect(find.textContaining('ใบเสร็จไม่ได้พิมพ์'), findsNothing);
  });

  testWidgets('explains that the sale succeeded when printing was skipped', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CheckoutCompletionDialog(
            hasPurchaseItems: true,
            hasReturnItems: false,
            allReceiptsPrinted: false,
            billId: '20260928000003',
          ),
        ),
      ),
    );

    expect(find.text('ดำเนินการเสร็จสิ้น'), findsOneWidget);
    expect(find.textContaining('ระบบบันทึกรายการสำเร็จแล้ว'), findsOneWidget);
    expect(find.textContaining('ใบเสร็จไม่ได้พิมพ์'), findsOneWidget);
    expect(find.textContaining('พิมพ์ซ้ำจากประวัติบิล'), findsOneWidget);
  });
}
