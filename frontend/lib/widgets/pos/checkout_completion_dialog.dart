import 'package:flutter/material.dart';

class CheckoutCompletionDialog extends StatelessWidget {
  const CheckoutCompletionDialog({
    super.key,
    required this.hasPurchaseItems,
    required this.hasReturnItems,
    required this.allReceiptsPrinted,
    this.billId,
  });

  final bool hasPurchaseItems;
  final bool hasReturnItems;
  final bool allReceiptsPrinted;
  final String? billId;

  String get _completionMessage {
    final normalizedBillId = billId?.trim() ?? '';
    if (hasPurchaseItems && normalizedBillId.isNotEmpty) {
      return 'ปิดการขายบิลเลขที่ $normalizedBillId เรียบร้อยแล้ว';
    }
    if (hasPurchaseItems && hasReturnItems) {
      return 'ปิดการขายและบันทึกรายการคืนสินค้าเรียบร้อยแล้ว';
    }
    if (hasPurchaseItems) {
      return 'ปิดการขายเรียบร้อยแล้ว';
    }
    return 'บันทึกรายการคืนสินค้าเรียบร้อยแล้ว';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.check_circle, color: Color(0xFF1F6F5D)),
          SizedBox(width: 10),
          Expanded(child: Text('ดำเนินการเสร็จสิ้น')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_completionMessage),
          if (!allReceiptsPrinted) ...[
            const SizedBox(height: 12),
            const Text(
              'ระบบบันทึกรายการสำเร็จแล้ว แต่ใบเสร็จไม่ได้พิมพ์ '
              'กรุณาตรวจสอบเครื่องพิมพ์ หรือพิมพ์ซ้ำจากประวัติบิล',
            ),
          ],
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ตกลง'),
        ),
      ],
    );
  }
}

Future<void> showCheckoutCompletionDialog(
  BuildContext context, {
  required bool hasPurchaseItems,
  required bool hasReturnItems,
  required bool allReceiptsPrinted,
  String? billId,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CheckoutCompletionDialog(
      hasPurchaseItems: hasPurchaseItems,
      hasReturnItems: hasReturnItems,
      allReceiptsPrinted: allReceiptsPrinted,
      billId: billId,
    ),
  );
}
