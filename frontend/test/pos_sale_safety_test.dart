import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/models/product.dart';
import 'package:frontend/widgets/pos/pos_product_card.dart';

void main() {
  group('POS sale stock selection', () {
    test('uses backend-selected sellable address when provided', () {
      final product = mapPosProductForSale({
        'code': 'P1589',
        'nameTh': 'เคมีปัว ลบเร็ว',
        'price': 115,
        'addressCode': 'SELLABLE-2',
        'availableQty': 3,
        'addresses': [
          {'code': 'DEFAULT-EMPTY', 'qty': 0, 'isDefault': true},
          {'code': 'SELLABLE-2', 'qty': 3},
        ],
      });

      expect(product.addressCodeForAdd, 'SELLABLE-2');
      expect(product.availableQty, 3);
    });

    test(
      'fallback skips an empty default and selects positive branch stock',
      () {
        final product = mapPosProductForSale({
          'code': 'P1589',
          'nameTh': 'เคมีปัว ลบเร็ว',
          'price': 115,
          'addresses': [
            {'code': 'DEFAULT-EMPTY', 'qty': 0, 'isDefault': true},
            {'code': 'SELLABLE', 'qty': '9'},
          ],
        });

        expect(product.addressCodeForAdd, 'SELLABLE');
        expect(product.availableQty, 9);
      },
    );

    testWidgets('disables Add when every branch address is out of stock', (
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
      expect(find.text('หมดจากคลัง'), findsOneWidget);

      await tester.tap(find.text('หมด'));
      expect(addCount, 0);
    });
  });
}
