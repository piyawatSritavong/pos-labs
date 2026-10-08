import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Only persisted, completed documents may be printed. No payment is performed
/// here: a cancelled print dialog must never cause another sale or refund.
class BrowserReceipt {
  BrowserReceipt(Map<String, dynamic> data, {this.isReturn = false})
    : data = Map<String, dynamic>.from(data) {
    if (data['status'] != 'completed' || id.isEmpty || items.isEmpty) {
      throw StateError('พิมพ์ได้เฉพาะบิลที่บันทึกเสร็จสิ้นและมีรายการสินค้า');
    }
  }

  final Map<String, dynamic> data;
  final bool isReturn;
  String get id => data['id']?.toString() ?? '';
  List<Map<String, dynamic>> get items =>
      ((data['details'] ?? data['items']) as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  static double number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  static String text(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String money(dynamic value) => number(value).toStringAsFixed(2);

  static String date(dynamic value) {
    final parsed = DateTime.tryParse('$value')?.toLocal();
    if (parsed == null) return '-';
    return '${parsed.day}/${parsed.month}/${parsed.year} '
        '${parsed.hour.toString().padLeft(2, '0')}:'
        '${parsed.minute.toString().padLeft(2, '0')}';
  }

  pw.Widget _amount(String label, dynamic amount) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [pw.Text(label), pw.Text(money(amount))],
  );

  List<pw.Widget> _content(Map<String, dynamic> company) {
    final meta = data['paymentMeta'];
    final payment = switch (data['paymentMethod']) {
      'cash' => 'เงินสด',
      'transfer' => 'โอนเงิน',
      'bank' => 'โอนเงิน',
      'credit_term' => 'เงินเซ็น',
      'exchange' => 'แลกเปลี่ยนสินค้า',
      _ => text(data, ['paymentMethod']),
    };
    return [
      pw.Center(
        child: pw.Text(text(company, ['companyNameTh', 'companyName'])),
      ),
      pw.Center(
        child: pw.Text(
          text(company, ['companyAddressTh', 'companyAddress']),
          textAlign: pw.TextAlign.center,
        ),
      ),
      if (text(company, ['taxId']).isNotEmpty)
        pw.Text('เลขประจำตัวผู้เสียภาษี ${company['taxId']}'),
      if (text(company, ['phone']).isNotEmpty)
        pw.Text('โทร ${company['phone']}'),
      pw.Divider(),
      pw.Center(child: pw.Text(isReturn ? 'ใบคืนสินค้า' : 'ใบเสร็จรับเงิน')),
      pw.Text('เลขที่ $id'),
      pw.Text('วันที่ ${date(data['updatedAt'] ?? data['createdAt'])}'),
      if (text(data, ['updatedByName', 'createdByName']).isNotEmpty)
        pw.Text('พนักงานขาย ${text(data, ['updatedByName', 'createdByName'])}'),
      if (isReturn) pw.Text('อ้างอิงบิล ${data['referenceBillId'] ?? '-'}'),
      if (payment.isNotEmpty) pw.Text('วิธีชำระเงิน $payment'),
      pw.Divider(),
      for (final item in items) ...[
        pw.Text(text(item, ['receiptName', 'name', 'partName', 'partCode'])),
        pw.Text(text(item, ['partCode'])),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '${number(item['qty']).toStringAsFixed(0)} x ${money(item['price'] ?? item['unitPrice'])}',
            ),
            pw.Text(
              money(
                item['lineTotal'] ??
                    item['amount'] ??
                    number(item['qty']) *
                        number(item['price'] ?? item['unitPrice']),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 5),
      ],
      pw.Divider(),
      if (isReturn) ...[
        _amount('ยอดคืนสินค้า', data['refundAmount']),
        _amount('ยอดซื้อสินค้า', data['purchaseAmount']),
        _amount('ยอดสุทธิซื้อ/คืน', data['netAmount']),
        pw.Text(
          'การคืนเงิน ${switch (data['settlementMode']) {
            'cash_refund' => 'คืนเงินสด',
            'customer_credit' => 'เครดิตลูกค้า',
            'exchange' => 'แลกเปลี่ยนสินค้า',
            _ => text(data, ['settlementMode']),
          }}',
        ),
      ] else ...[
        _amount('ก่อนลด', data['purchaseAmount']),
        _amount('ส่วนลด', data['totalDiscount']),
        _amount(
          'หลังหักส่วนลด',
          data['amountAfterDiscount'] ??
              number(data['purchaseAmount']) - number(data['totalDiscount']),
        ),
        _amount('ภาษีมูลค่าเพิ่ม', data['vatAmount']),
        _amount('รวมสุทธิ', data['totalAmount']),
        if (meta is Map && meta['receivedAmount'] != null)
          _amount('รับเงิน', meta['receivedAmount']),
        if (meta is Map && meta['changeAmount'] != null)
          _amount('เงินทอน', meta['changeAmount']),
      ],
      pw.Divider(),
      pw.Center(
        child: pw.Text(
          text(company, ['receiptFooter']),
          textAlign: pw.TextAlign.center,
        ),
      ),
    ];
  }

  /// Fresh bytes per preview/print request: web printing may transfer/detach
  /// the buffer. Bundle the Thai font so printing does not need a font CDN.
  static Future<Uint8List> buildPdf(
    List<BrowserReceipt> receipts,
    Map<String, dynamic> company,
  ) async {
    if (receipts.isEmpty) throw StateError('ไม่พบใบเสร็จ');
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Sarabun-Regular.ttf'),
    );
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    for (final receipt in receipts) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          build: (_) => pw.DefaultTextStyle(
            style: pw.TextStyle(font: font, fontSize: 10),
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: receipt._content(company),
            ),
          ),
        ),
      );
    }
    return document.save();
  }
}
