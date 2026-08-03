import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/bill_provider.dart';
import 'package:frontend/services/api_operations.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/pos_error_message.dart';
import 'package:frontend/utils/store_summary.dart';
import 'package:frontend/widgets/backoffice/addresses_page.dart';
import 'package:frontend/widgets/backoffice/purchase_orders_page.dart';
import 'package:frontend/widgets/pos/requisition_dialog.dart';
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
    expect(find.textContaining('Min'), findsNothing);
    expect(find.textContaining('Max'), findsNothing);
  });

  testWidgets('purchase order page exposes the bulk inbound action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: Scaffold(body: PurchaseOrdersPage())),
      ),
    );
    await tester.pump();
    expect(find.text('สร้างใบสั่งซื้อสินค้าเข้า'), findsOneWidget);
    expect(
      find.text('บันทึกแล้วสินค้าและจำนวนจะเข้าคลังหลักทันที'),
      findsOneWidget,
    );
  });

  testWidgets(
    'purchase order product picker opens and selects without typing',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      Map<String, dynamic>? selected;
      final offsets = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(
            splashFactory: NoSplash.splashFactory,
          ),
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: PurchaseOrderProductPicker(
                controller: controller,
                onSelected: (product) => selected = product,
                loadPage: (query, limit, offset) async {
                  offsets.add(offset);
                  return (
                    parts: const [
                      {
                        'code': 'P0801',
                        'nameTh': 'สินค้ารับเข้า',
                        'barCode': '885000000801',
                        'cost': 80,
                        'price': 100,
                        'minPrice': 90,
                        'isActive': false,
                      },
                    ],
                    total: 1,
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('หมายเหตุ'), findsNothing);
      await tester.tap(
        find.byKey(const Key('purchase-order-product-dropdown')),
      );
      await tester.pumpAndSettle();
      expect(offsets, [0]);
      expect(find.textContaining('P0801 - สินค้ารับเข้า'), findsOneWidget);
      expect(find.textContaining('ปิดใช้งาน'), findsOneWidget);

      await tester.tap(find.textContaining('P0801 - สินค้ารับเข้า'));
      await tester.pumpAndSettle();
      expect(selected?['code'], 'P0801');
      expect(selected?['cost'], 80);
      expect(controller.text, isEmpty);
    },
  );

  testWidgets('restock picker opens without typing and selects immediately', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    Map<String, dynamic>? selected;
    var submitted = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light().copyWith(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 560,
              child: RestockCatalogPicker(
                controller: controller,
                onSubmitted: () => submitted++,
                onSelected: (part) => selected = part,
                loadPage: (query, limit, offset) async => RestockCatalogPage(
                  items: const [
                    {
                      'code': 'P0001',
                      'barCode': '885000000001',
                      'nameTh': 'สินค้าทดสอบ',
                      'availableQty': 8,
                      'price': 100,
                    },
                  ],
                  total: 1,
                  limit: limit,
                  offset: offset,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('ค้นหาจากรายการสินค้า'), findsNothing);
    await tester.tap(find.byKey(const Key('restock-catalog-dropdown')));
    await tester.pumpAndSettle();
    expect(find.textContaining('P0001 - สินค้าทดสอบ'), findsOneWidget);

    await tester.tap(find.textContaining('P0001 - สินค้าทดสอบ'));
    await tester.pumpAndSettle();
    expect(selected?['code'], 'P0001');
    expect(controller.text, isEmpty);

    await tester.enterText(
      find.byKey(const Key('restock-unified-search')),
      'P0001',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(submitted, 1);
  });

  testWidgets('restock picker loads the next 50 items near scroll end', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final offsets = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light().copyWith(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: SizedBox(
            width: 560,
            child: RestockCatalogPicker(
              controller: controller,
              onSubmitted: () {},
              onSelected: (_) {},
              loadPage: (query, limit, offset) async {
                offsets.add(offset);
                final end = (offset + limit).clamp(0, 51);
                return RestockCatalogPage(
                  items: [
                    for (var i = offset; i < end; i++)
                      {
                        'code': 'P${(i + 1).toString().padLeft(4, '0')}',
                        'nameTh': 'สินค้า ${i + 1}',
                        'availableQty': 1,
                        'price': 10,
                      },
                  ],
                  total: 51,
                  limit: limit,
                  offset: offset,
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('restock-catalog-dropdown')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    expect(offsets, containsAllInOrder([0, 50]));
    expect(find.textContaining('P0051 - สินค้า 51'), findsOneWidget);
  });

  test('theme uses 12px controls/cards and 16px dialogs', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final input =
          theme.inputDecorationTheme.enabledBorder as OutlineInputBorder;
      final card = theme.cardTheme.shape as RoundedRectangleBorder;
      final dialog = theme.dialogTheme.shape as RoundedRectangleBorder;
      final button =
          theme.elevatedButtonTheme.style!.shape!.resolve({})
              as RoundedRectangleBorder;

      expect(input.borderRadius.topLeft.x, AppSizes.radius);
      expect((card.borderRadius as BorderRadius).topLeft.x, AppSizes.radius);
      expect((button.borderRadius as BorderRadius).topLeft.x, AppSizes.radius);
      expect(
        (dialog.borderRadius as BorderRadius).topLeft.x,
        AppSizes.radiusLarge,
      );
    }
  });
}
