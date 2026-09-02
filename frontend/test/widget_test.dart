import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/product.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/bill_provider.dart';
import 'package:frontend/services/api_operations.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/api_error.dart';
import 'package:frontend/utils/pos_error_message.dart';
import 'package:frontend/utils/store_summary.dart';
import 'package:frontend/widgets/backoffice/addresses_page.dart';
import 'package:frontend/widgets/backoffice/purchase_orders_page.dart';
import 'package:frontend/widgets/pos/requisition_dialog.dart';
import 'package:frontend/widgets/pos/search_parts_dialog.dart';
import 'package:provider/provider.dart';

void main() {
  _posErrorMessageTests();
  _transferErrorTests();
  _apiErrorTests();
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
      'สต๊อกในคลังประจำ POS ไม่พอ',
    );
    expect(
      posErrorMessage(Exception('400 {"error":"no_vehicle_stock"}')),
      'สินค้านี้ไม่มีสต๊อกในคลังประจำ POS',
    );
  });

  test('a short stock error names the quantity actually on the vehicle', () {
    // "แก้จำนวนไม่สำเร็จ" on its own reads as the app ignoring the edit; the
    // number is what tells the cashier what to do next.
    final message = posErrorMessage(
      Exception(
        '400 {"error":"not_enough_inventory","requestedQty":50,'
        '"availableQty":10,"addressCode":"VEH123"}',
      ),
    );
    expect(message, contains('50'));
    expect(message, contains('10'));
    expect(message, isNot(contains('not_enough_inventory')));
    expect(message, isNot(contains('VEH123')));
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

  testWidgets('the stock page lists van rows and will not let them be edited', (
    tester,
  ) async {
    // The page filtered every query to the warehouse while its store dropdown
    // offered the vans, so "ทุกคลัง" quietly meant "main only" — an admin read
    // 0 for goods a van was busy selling. Van rows show; only the warehouse is
    // editable, because moving van stock is a ใบเบิก, not a typed number.
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(
          home: Scaffold(
            body: AddressesManagementSection(
              autoLoad: false,
              initialAddresses: [
                {
                  'partCode': 'P0557',
                  'partName': 'ปลั๊กสามตาวีน่า',
                  'storeId': 'main',
                  'storeName': 'คลังหลัก',
                  'qty': 0,
                  'price': 60.0,
                  'rop': 0,
                },
                {
                  'partCode': 'P0557',
                  'partName': 'ปลั๊กสามตาวีน่า',
                  'storeId': 'vehicle_POS001',
                  'storeName': 'คลังสาขา pos1',
                  'qty': 12,
                  'price': 60.0,
                  'rop': 0,
                },
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('คลังหลัก'), findsOneWidget);
    expect(find.text('คลังสาขา pos1'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);

    final buttons = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .where((b) => b.icon is Icon && (b.icon as Icon).icon == Icons.edit_outlined)
        .toList();
    expect(buttons.length, 2);
    expect(buttons[0].onPressed, isNotNull, reason: 'warehouse row is editable');
    expect(buttons[1].onPressed, isNull, reason: 'van row is read-only here');
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

  testWidgets('purchase order delete warns and only removes after confirm', (
    tester,
  ) async {
    var deleteCalls = 0;
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: MaterialApp(
          theme: AppTheme.light().copyWith(
            splashFactory: NoSplash.splashFactory,
          ),
          home: Scaffold(
            body: PurchaseOrdersPage(
              autoLoad: false,
              initialOrders: const [
                {
                  'id': 'PO20260804000001',
                  'orderDate': '2026-08-04',
                  'notes': '',
                  'totalCost': 4,
                  'totalSaleValue': 8,
                },
              ],
              deleteOrder: (id) async => deleteCalls++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('delete-purchase-order-PO20260804000001')),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('จำนวนสินค้าในคลังจะไม่เปลี่ยน'),
      findsOneWidget,
    );
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(deleteCalls, 0);
    expect(find.text('PO20260804000001'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('delete-purchase-order-PO20260804000001')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ลบเอกสาร'));
    await tester.pumpAndSettle();
    expect(deleteCalls, 1);
    expect(find.text('PO20260804000001'), findsNothing);
  });

  testWidgets('shared purchase order action opens create form directly', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: MaterialApp(
          theme: AppTheme.light().copyWith(
            splashFactory: NoSplash.splashFactory,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showCreatePurchaseOrderDialog(context),
                child: const Text('เปิดฟอร์ม'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('เปิดฟอร์ม'));
    await tester.pumpAndSettle();
    expect(find.text('สร้างใบสั่งซื้อสินค้าเข้า'), findsOneWidget);
    expect(
      find.byKey(const Key('purchase-order-product-search')),
      findsOneWidget,
    );
    expect(
      find.text('บันทึกแล้วสินค้าและจำนวนจะเข้าคลังหลักทันที'),
      findsNothing,
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
                loadPage: (query, limit, offset, includeArchived) async {
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
      expect(find.textContaining('• ปิดใช้งาน'), findsOneWidget);

      await tester.tap(find.textContaining('P0801 - สินค้ารับเข้า'));
      await tester.pumpAndSettle();
      expect(selected?['code'], 'P0801');
      expect(selected?['cost'], 80);
      expect(controller.text, isEmpty);
    },
  );

  testWidgets(
    'the inbound picker leaves archived products out until asked for them',
    (tester) async {
      // The shop had the same three tyres entered under three naming habits.
      // Once the duplicates were archived they still filled this list, so
      // searching ยางนอก offered nine rows for three products.
      final controller = TextEditingController();
      final archivedFlags = <bool>[];
      addTearDown(controller.dispose);

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
                onSelected: (_) {},
                loadPage: (query, limit, offset, includeArchived) async {
                  archivedFlags.add(includeArchived);
                  return (parts: const <Map<String, dynamic>>[], total: 0);
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const Key('purchase-order-product-dropdown')),
      );
      await tester.pumpAndSettle();
      expect(archivedFlags, [false]);

      await tester.tap(
        find.byKey(const Key('purchase-order-include-archived')),
      );
      await tester.pumpAndSettle();
      expect(archivedFlags, [false, true]);
    },
  );

  testWidgets('a product the van has run out of is listed but not addable', (
    tester,
  ) async {
    // The shop reported "สินค้ามีในระบบ แต่ข้อมูลขายไม่มี": the vehicle stock page
    // listed the product and the till did not, because the till dropped every
    // line with no pieces left. Now the till shows the same list and says which
    // ones are finished.
    var added = 0;

    Widget card(Product product) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: PosProductCard(product: product, onAdd: () => added++),
      ),
    );

    await tester.pumpWidget(
      card(
        const Product(
          id: 'P0001',
          name: 'ตะปู 3*10',
          price: 650,
          code: 'P0001',
          availableQty: 0,
        ),
      ),
    );
    expect(find.text('ตะปู 3*10'), findsOneWidget);
    expect(find.text('หมด'), findsWidgets);
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    expect(added, 0, reason: 'a sold-out line must not reach the bill');

    await tester.pumpWidget(
      card(
        const Product(
          id: 'P0002',
          name: 'ตะปู 3*8',
          price: 650,
          code: 'P0002',
          availableQty: 2,
        ),
      ),
    );
    expect(find.text('เหลือ 2'), findsOneWidget);
    expect(find.text('+ เพิ่ม'), findsOneWidget);
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    expect(added, 1);
  });

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

void _posErrorMessageTests() {
  test('a bill cancelled elsewhere is explained, not dumped as raw JSON', () {
    final message = posErrorMessage(
      Exception(
        'Failed to pay bill: 400 {"error":"invalid_bill_status",'
        '"message":"Bill status must be \'new\' to process payment, '
        'bill status must be \'new\', current status: \'cancelled\'"}',
      ),
    );
    expect(message, contains('ถูกยกเลิก'));
    expect(message, isNot(contains('invalid_bill_status')));
    expect(message, isNot(contains('400')));
  });

  test('a bill already paid warns against taking the money twice', () {
    final message = posErrorMessage(
      Exception(
        'Failed to pay bill: 400 {"error":"invalid_bill_status",'
        '"message":"current status: \'completed\'"}',
      ),
    );
    expect(message, contains('ชำระเงินไปแล้ว'));
    expect(message, contains('ประวัติการขาย'));
  });

  test('unrelated errors are still passed through', () {
    expect(
      posErrorMessage(Exception('something else went wrong')),
      'something else went wrong',
    );
  });
}

void _transferErrorTests() {
  test('a stock shortage names the product, not just a part code', () {
    final message = posErrorMessage(
      ApiException(
        action: 'PUT /transfers/TR1/approve-restock failed',
        statusCode: 409,
        body:
            '{"error":"insufficient_stock","message":"คลังหลักมีของไม่พอ '
            'เบ็ดฉลาดดำ ขอ 8 เหลือ 6 (ขาด 2)","shortages":[]}',
      ),
    );
    expect(message, contains('เบ็ดฉลาดดำ'));
    expect(message, contains('ขาด 2'));
    expect(message, isNot(contains('409')));
    expect(message, isNot(contains('insufficient_stock')));
  });

  test('an error with no server message still reads as prose', () {
    expect(
      posErrorMessage(Exception('network unreachable')),
      'network unreachable',
    );
  });
}

void _apiErrorTests() {
  // The bug this file guards: a red bar that read
  // "400 {"error":"invalid_request","message":"Key: 'LineTotal' Error:Field
  // validation for 'LineTotal' failed on the 'required' tag"}".
  test('a rejected request never reaches the screen as raw JSON', () {
    final message = ApiException(
      action: 'Failed to update item price',
      statusCode: 400,
      body:
          '{"error":"invalid_request","message":"Key: \'LineTotal\' '
          'Error:Field validation for \'LineTotal\' failed on the '
          '\'required\' tag"}',
    ).toString();
    expect(message, isNot(contains('{')));
    expect(message, isNot(contains('LineTotal')));
    expect(message, isNot(contains('400')));
    expect(message, 'ข้อมูลที่ส่งไปไม่ครบหรือไม่ถูกต้อง');
  });

  test('a Thai explanation from the backend is passed through untouched', () {
    expect(
      ApiException(
        action: 'x',
        statusCode: 409,
        body: '{"error":"insufficient_stock","message":"คลังหลักมีของไม่พอ"}',
      ).toString(),
      'คลังหลักมีของไม่พอ',
    );
  });

  test('codes nobody spelled out are still answered in Thai', () {
    String render(String code, int status) => ApiException(
      action: 'x',
      statusCode: status,
      body: '{"error":"$code"}',
    ).toString();

    expect(render('promotion_not_found', 404), 'ไม่พบโปรโมชั่น');
    expect(render('missing_promotion_code', 400), contains('รหัสโปรโมชั่น'));
    expect(render('failed_to_create_member', 500), contains('ลองใหม่'));
    expect(render('stock_count_access_denied', 403), contains('ไม่มีสิทธิ์'));
  });

  test('a body with no reason at all falls back to the status', () {
    expect(
      ApiException(action: 'x', statusCode: 502, body: '<html>bad gateway')
          .toString(),
      contains('502'),
    );
  });

  test('the reason code stays readable for code that branches on it', () {
    final error = ApiException(
      action: 'x',
      statusCode: 400,
      body: '{"error":"invalid_bill_status"}',
    );
    expect(apiErrorCode(error), 'invalid_bill_status');
    expect(isApiErrorCode(error, 'invalid_bill_status'), isTrue);
    expect(isApiErrorCode(Exception('nope'), 'invalid_bill_status'), isFalse);
  });

  test('the raw response is still available for logs', () {
    final error = ApiException(
      action: 'Failed to pay bill',
      statusCode: 400,
      body: '{"error":"empty_bill"}',
    );
    expect(error.debugString, contains('Failed to pay bill'));
    expect(error.debugString, contains('empty_bill'));
  });
}
