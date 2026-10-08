// Manual smoke test without production API access or real sales:
// flutter run -d web-server -t tool/receipt_print_smoke.dart
import 'package:flutter/material.dart';
import 'package:frontend/services/browser_receipt.dart';
import 'package:frontend/widgets/pos/browser_receipt_page.dart';
import 'package:frontend/widgets/pos/checkout_completion_dialog.dart';

void main() => runApp(
  MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: CheckoutCompletionDialog(
          hasPurchaseItems: true,
          hasReturnItems: false,
          allReceiptsPrinted: false,
          billId: 'TEST-20261008',
          onPrintReceipt: () => showBrowserReceipts(
            context,
            receipts: [
              BrowserReceipt({
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
                  },
                  {
                    'partCode': 'P0002',
                    'name': 'MDF 3 มิล',
                    'qty': 1,
                    'price': 100,
                  },
                  {
                    'partCode': 'P0004',
                    'name': 'MDF 6 มิล',
                    'qty': 1,
                    'price': 200,
                  },
                  {
                    'partCode': 'P0007',
                    'name': 'MDF 15 มิล',
                    'qty': 1,
                    'price': 370,
                  },
                ],
              }),
            ],
            company: {
              'companyNameTh': 'ใจเฮง (ข้อมูลทดสอบ)',
              'companyAddressTh': 'ที่อยู่ร้านค้าเพื่อทดสอบภาษาไทย',
              'receiptFooter': 'ข้อมูลทดสอบ ไม่ใช่ใบเสร็จจากการขายจริง',
            },
          ),
        ),
      ),
    ),
  ),
);
