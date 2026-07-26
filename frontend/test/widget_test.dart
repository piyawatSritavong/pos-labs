import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/bill_provider.dart';
import 'package:frontend/utils/pos_error_message.dart';
import 'package:frontend/utils/store_summary.dart';
import 'package:frontend/widgets/backoffice/addresses_page.dart';
import 'package:provider/provider.dart';

void main() {
  test('formats and aggregates warehouse quantities without shelf names', () {
    final formatted = formatPartStoreSummary([
      {
        'store': {'id': 'vehicle_POS001', 'labelTh': 'คลังสาขา pos1'},
        'shelf': 'รถ',
        'qty': 2,
      },
      {
        'store': {'id': 'main', 'labelTh': 'คลังหลัก'},
        'shelf': 'A-01',
        'qty': 5,
      },
      {
        'store': {'id': 'vehicle_POS001', 'labelTh': 'คลังสาขา pos1'},
        'shelf': 'รถสำรอง',
        'qty': 3,
      },
    ]);

    expect(formatted, 'คลังหลัก (5), คลังสาขา pos1 (5)');
    expect(formatted, isNot(contains('A-01')));
    expect(formatted, isNot(contains('รถ')));
  });

  test('new bill provider starts with an empty cart', () {
    final bill = BillProvider();
    expect(bill.billId, isNull);
    expect(bill.items, isEmpty);
  });

  test('inventory API errors are shown in Thai', () {
    expect(
      posErrorMessage(Exception('400 {"error":"not_enough_inventory"}')),
      'สินค้านี้ไม่มีสต๊อกในคลังประจำ POS',
    );
  });

  testWidgets('inventory filters and empty state are shown in Thai', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(
          home: Scaffold(body: AddressesManagementSection(autoLoad: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('คลังสินค้า'), findsOneWidget);
    expect(find.text('ทุกคลัง'), findsOneWidget);
    expect(find.text('ไม่พบข้อมูลคลังสินค้า'), findsOneWidget);
    expect(find.text('เพิ่มคลังใหม่'), findsNothing);
  });
}
