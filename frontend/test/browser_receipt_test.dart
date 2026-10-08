import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/browser_receipt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bill = <String, dynamic>{
    'id': 'TEST-20261008',
    'status': 'completed',
    'updatedAt': '2026-10-08T06:49:00Z',
    'updatedByName': 'POS Cashier 1',
    'paymentMethod': 'cash',
    'paymentMeta': {'receivedAmount': 1000, 'changeAmount': 255},
    'purchaseAmount': 745,
    'totalDiscount': 0,
    'amountAfterDiscount': 745,
    'totalAmount': 745,
    'vatAmount': 0,
    'details': [
      {
        'partCode': 'P0001',
        'name': 'MDF 2.5 มิล (ขายส่ง)',
        'qty': 1,
        'price': 75,
        'lineTotal': 75,
      },
      {
        'partCode': 'P0002',
        'name': 'MDF 3 มิล',
        'qty': 1,
        'price': 100,
        'lineTotal': 100,
      },
      {
        'partCode': 'P0004',
        'name': 'MDF 6 มิล',
        'qty': 1,
        'price': 200,
        'lineTotal': 200,
      },
      {
        'partCode': 'P0007',
        'name': 'MDF 15 มิล',
        'qty': 1,
        'price': 370,
        'lineTotal': 370,
      },
    ],
  };
  final company = <String, dynamic>{
    'companyNameTh': 'ใจเฮง (ข้อมูลทดสอบ)',
    'companyAddressTh': 'ที่อยู่ร้านค้าเพื่อทดสอบภาษาไทย',
    'phone': 'TEST',
    'receiptFooter': 'ขอบคุณที่ใช้บริการ',
  };

  test('rejects drafts, cancellations, missing IDs and empty receipts', () {
    for (final status in ['draft', 'pending', 'cancelled']) {
      expect(
        () => BrowserReceipt({...bill, 'status': status}),
        throwsStateError,
      );
    }
    expect(() => BrowserReceipt({...bill, 'id': ''}), throwsStateError);
    expect(() => BrowserReceipt({...bill, 'details': []}), throwsStateError);
  });

  test(
    'builds fresh Thai 80mm sale and return PDFs from saved values',
    () async {
      final sale = BrowserReceipt(bill);
      final returned = BrowserReceipt({
        ...bill,
        'id': 'CN-TEST-20261008',
        'referenceBillId': bill['id'],
        'refundAmount': 745,
        'purchaseAmount': 0,
        'netAmount': -745,
        'settlementMode': 'cash_refund',
      }, isReturn: true);
      final first = await BrowserReceipt.buildPdf([sale, returned], company);
      final second = await BrowserReceipt.buildPdf([sale, returned], company);
      expect(String.fromCharCodes(first.take(4)), '%PDF');
      expect(first.length, greaterThan(1000));
      expect(identical(first.buffer, second.buffer), isFalse);
      final originalFirstByte = first[0];
      first[0] = 0;
      expect(second[0], originalFirstByte);
      first[0] = originalFirstByte;
      expect(sale.items.length, 4);
      expect(BrowserReceipt.money(sale.data['totalAmount']), '745.00');
      final outputDir = Platform.environment['POS_RECEIPT_QA_DIRECTORY'];
      if (outputDir != null) {
        await File('$outputDir/receipt.pdf').writeAsBytes(first);
        final longReceipt = BrowserReceipt({
          ...bill,
          'details': [
            for (var i = 0; i < 100; i++)
              {
                'partCode': 'TEST-$i',
                'name':
                    'สินค้าทดสอบชื่อยาว ภาษาไทย ต้องไม่ถูกตัดออกจากใบเสร็จ $i',
                'qty': 1,
                'price': 7.45,
                'lineTotal': 7.45,
              },
          ],
        });
        await File(
          '$outputDir/long-receipt.pdf',
        ).writeAsBytes(await BrowserReceipt.buildPdf([longReceipt], company));
      }
    },
  );
}
