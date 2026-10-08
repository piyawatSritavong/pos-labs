import 'package:flutter/material.dart';
import 'package:frontend/services/app_dialog_service.dart';

class CheckoutCompletionDialog extends StatefulWidget {
  const CheckoutCompletionDialog({
    super.key,
    required this.hasPurchaseItems,
    required this.hasReturnItems,
    required this.allReceiptsPrinted,
    this.billId,
    this.onPrintReceipt,
  });

  final bool hasPurchaseItems;
  final bool hasReturnItems;
  final bool allReceiptsPrinted;
  final String? billId;
  final Future<void> Function()? onPrintReceipt;

  @override
  State<CheckoutCompletionDialog> createState() =>
      _CheckoutCompletionDialogState();
}

class _CheckoutCompletionDialogState extends State<CheckoutCompletionDialog> {
  bool _openingPrint = false;

  Future<void> _printReceipt() async {
    if (_openingPrint) return;
    setState(() => _openingPrint = true);
    try {
      await widget.onPrintReceipt!();
    } catch (error) {
      if (!mounted) return;
      await AppDialogService.showError(
        context,
        error: error,
        fallback:
            'เปิดใบเสร็จไม่สำเร็จ รายการขายยังบันทึกแล้ว กรุณาพิมพ์ซ้ำจากประวัติบิล',
      );
    } finally {
      if (mounted) setState(() => _openingPrint = false);
    }
  }

  String get _completionMessage {
    final normalizedBillId = widget.billId?.trim() ?? '';
    if (widget.hasPurchaseItems && normalizedBillId.isNotEmpty) {
      return 'ปิดการขายบิลเลขที่ $normalizedBillId เรียบร้อยแล้ว';
    }
    if (widget.hasPurchaseItems && widget.hasReturnItems) {
      return 'ปิดการขายและบันทึกรายการคืนสินค้าเรียบร้อยแล้ว';
    }
    if (widget.hasPurchaseItems) {
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
          if (!widget.allReceiptsPrinted) ...[
            const SizedBox(height: 12),
            const Text(
              'ระบบบันทึกรายการสำเร็จแล้ว แต่ใบเสร็จไม่ได้พิมพ์อัตโนมัติ '
              'กดพิมพ์ใบเสร็จเพื่อเลือกเครื่องพิมพ์ของเครื่องนี้ '
              'หรือพิมพ์ซ้ำจากประวัติบิล ไม่ต้องชำระเงินซ้ำ',
            ),
          ],
        ],
      ),
      actions: [
        if (widget.onPrintReceipt != null)
          OutlinedButton.icon(
            onPressed: _openingPrint ? null : _printReceipt,
            icon: const Icon(Icons.print),
            label: Text(_openingPrint ? 'กำลังเปิดใบเสร็จ...' : 'พิมพ์ใบเสร็จ'),
          ),
        ElevatedButton(
          onPressed: _openingPrint ? null : () => Navigator.of(context).pop(),
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
  Future<void> Function()? onPrintReceipt,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CheckoutCompletionDialog(
      hasPurchaseItems: hasPurchaseItems,
      hasReturnItems: hasReturnItems,
      allReceiptsPrinted: allReceiptsPrinted,
      billId: billId,
      onPrintReceipt: onPrintReceipt,
    ),
  );
}
