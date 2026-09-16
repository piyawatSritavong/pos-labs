import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/models/product.dart';
import 'package:frontend/widgets/pos/search_parts_dialog.dart';

void main() {
  group('POS sale stock selection', () {
    test('uses only positive stock from the current POS vehicle', () {
      final product = mapPosProductForSale({
        'code': 'P1589',
        'nameTh': 'เคมีปัว ลบเร็ว',
        'price': 115,
        'addresses': [
          {'code': 'MAIN-1', 'storeId': 'main', 'qty': 99, 'isDefault': true},
          {
            'code': 'POS-1-A',
            'store': {'id': 'vehicle_POS001'},
            'qty': 3,
          },
          {'code': 'POS-1-B', 'store_id': 'vehicle_POS001', 'qty': '2'},
        ],
      }, posId: 'POS001');

      expect(product.addressCodeForAdd, 'POS-1-A');
      expect(product.availableQty, 5);
    });

    test('never falls back to warehouse stock', () {
      final product = mapPosProductForSale({
        'code': 'P1589',
        'nameTh': 'เคมีปัว ลบเร็ว',
        'price': 115,
        'addresses': [
          {'code': 'MAIN-1', 'storeId': 'main', 'qty': 99, 'isDefault': true},
        ],
      }, posId: 'POS001');

      expect(product.addressCodeForAdd, isNull);
      expect(product.availableQty, 0);
    });

    testWidgets('disables Add when the POS vehicle is out of stock', (
      tester,
    ) async {
      var addCount = 0;
      const product = Product(
        id: 'P1589',
        name: 'เคมีปัว ลบเร็ว',
        price: 115,
        code: 'P1589',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 480,
              height: 160,
              child: PosProductCard(product: product, onAdd: () => addCount++),
            ),
          ),
        ),
      );

      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'หมด'),
      );
      expect(button.onPressed, isNull);
      expect(find.text('หมดจากรถ'), findsOneWidget);

      await tester.tap(find.text('หมด'));
      expect(addCount, 0);
    });
  });
}
