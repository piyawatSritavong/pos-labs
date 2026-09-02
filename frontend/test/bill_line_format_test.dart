import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/bill_line_format.dart';

void main() {
  test('reads a line that carries its own unit price', () {
    final line = {'qty': 10, 'unitPrice': 80.0, 'lineTotal': 800.0};
    expect(billLineQty(line), 10);
    expect(billLineUnitPrice(line), 80);
    expect(billLineTotal(line), 800);
    expect(billLineQtyPriceLabel(line), '10 × ฿80.00');
  });

  test('derives the unit price when only a total came back', () {
    // The older list endpoints answer this way, and the screens showing them
    // are exactly the ones that were missing the price each.
    final line = {'qty': 76, 'amount': 6840.0};
    expect(billLineUnitPrice(line), 90);
    expect(billLineQtyPriceLabel(line), '76 × ฿90.00');
  });

  test('derives the total when only a unit price came back', () {
    final line = {'qty': 5, 'price': 170.0};
    expect(billLineTotal(line), 850);
    expect(billLineQtyPriceLabel(line), '5 × ฿170.00');
  });

  test('a missing or zero quantity counts as one, never zero', () {
    // Dividing a total by zero would print an infinity on a customer's screen.
    expect(billLineQty(const {}), 1);
    expect(billLineQty(const {'qty': 0}), 1);
    expect(billLineUnitPrice(const {'qty': 0, 'amount': 25.0}), 25);
  });

  test('weighed goods keep their decimals, counted goods do not', () {
    expect(
      billLineQtyPriceLabel({'qty': 1.498, 'price': 129.0}),
      '1.498 × ฿129.00',
    );
    expect(billLineQtyPriceLabel({'qty': 4, 'price': 20.0}), '4 × ฿20.00');
  });

  test('string numbers from JSON are read, not dropped', () {
    final line = {'qty': '3', 'price': '15.50'};
    expect(billLineQty(line), 3);
    expect(billLineUnitPrice(line), 15.5);
    expect(billLineTotal(line), 46.5);
  });

  test('a line given away is labelled แถม instead of ฿0.00', () {
    // A cashier prices a freebie at 0; ฿0.00 on a history screen reads as a
    // pricing mistake and sends someone looking for a bug that is not there.
    expect(
      billLineTotalLabel({'qty': 2, 'price': 0.0, 'lineTotal': 0}),
      'แถม',
    );
    expect(
      billLineTotalLabel({'qty': 2, 'price': 35.0, 'lineTotal': 70}),
      '฿70.00',
    );
  });
}
