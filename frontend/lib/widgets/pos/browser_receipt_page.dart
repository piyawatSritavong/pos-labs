import 'package:flutter/material.dart';
import 'package:frontend/services/browser_receipt.dart';
import 'package:frontend/services/app_dialog_service.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// A user-initiated Print action opens the OS/browser print dialog, not the
/// cloud server's printer. Opening or cancelling it is not proof of printing.
class BrowserReceiptPage extends StatelessWidget {
  const BrowserReceiptPage({
    super.key,
    required this.receipts,
    required this.company,
  });

  final List<BrowserReceipt> receipts;
  final Map<String, dynamic> company;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('พิมพ์ใบเสร็จผ่านเครื่องนี้')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'กดไอคอนพิมพ์ด้านล่าง แล้วเลือกเครื่องพิมพ์ใบเสร็จของ Windows '
            'ตั้งกระดาษ 80 มม. และขนาดจริง (100%) '
            'รายการขายบันทึกแล้ว ไม่ต้องชำระเงินซ้ำ',
          ),
        ),
        Expanded(
          child: PdfPreview(
            maxPageWidth: 320,
            build: (_) => BrowserReceipt.buildPdf(receipts, company),
            initialPageFormat: const PdfPageFormat(
              80 * PdfPageFormat.mm,
              297 * PdfPageFormat.mm,
            ),
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            dynamicLayout: false,
            allowSharing: false,
            onError: (_, error) => const Center(
              child: Text(
                'สร้างตัวอย่างใบเสร็จไม่สำเร็จ กรุณากลับแล้วลองพิมพ์ใหม่ รายการขายบันทึกแล้ว',
              ),
            ),
            onPrintError: (printContext, error) => AppDialogService.showError(
              printContext,
              error: error,
              fallback:
                  'เปิดหน้าต่างพิมพ์ไม่สำเร็จ กรุณาตรวจสอบ browser และเครื่องพิมพ์ รายการขายบันทึกแล้ว',
            ),
            pdfFileName: 'receipt-${receipts.first.id}.pdf',
          ),
        ),
      ],
    ),
  );
}

Future<void> showBrowserReceipts(
  BuildContext context, {
  required List<BrowserReceipt> receipts,
  required Map<String, dynamic> company,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => BrowserReceiptPage(receipts: receipts, company: company),
  ),
);
