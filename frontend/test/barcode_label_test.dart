import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/backoffice/barcode_sheet_page.dart';

void main() {
  test('a label carries the name, the price and the barcode value', () {
    const item = BarcodePickItem(
      partCode: 'P0001',
      name: 'ตะปู 3*10',
      barcode: 'P0001',
      price: '35',
      qty: 3,
    );
    expect(item.labelHeading, 'ตะปู 3*10  35 บาท');
  });

  test('an unpriced product keeps the sticker to just its name', () {
    // Better a sticker with no price than one reading "0 บาท".
    const item = BarcodePickItem(
      partCode: 'P0002',
      name: 'ของแถม',
      barcode: 'P0002',
      qty: 1,
    );
    expect(item.labelHeading, 'ของแถม');
  });
}
