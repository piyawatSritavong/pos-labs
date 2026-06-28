import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// One item picked on [BarcodePrintPage] — partCode + name shown beneath the
/// rendered Code128 + qty (number of copies to print, always a multiple of 3).
class BarcodePickItem {
  const BarcodePickItem({
    required this.partCode,
    required this.name,
    required this.barcode,
    required this.qty,
  });

  final String partCode;
  final String name;
  final String barcode;
  final int qty;
}

/// Builds an exact-millimetre label PDF for the EasyPrint ES-9920UW thermal
/// printer and shows it in a [PdfPreview] (with a built-in print button).
///
/// Media: Direct Thermal DT PP stickers, 32×25 mm, **3 labels per row**.
/// The printer feeds one row at a time, so each PDF *page* holds exactly one
/// row of 3 labels. Labels are packed left-to-right in pick order, filling each
/// row before the next; any quantity is allowed and only the final row is
/// padded with blank cells (e.g. 4 labels → [a,b,c] then [d, blank, blank]).
///
/// Why PDF instead of `window.print()`: Flutter Web renders to a CanvasKit
/// bitmap, so browser printing scales the canvas and cannot guarantee exact mm
/// sizes — unacceptable for die-cut label stock. A PDF with a precise
/// [PdfPageFormat] prints 1:1.
class BarcodeSheetPage extends StatefulWidget {
  const BarcodeSheetPage({super.key, required this.items});

  final List<BarcodePickItem> items;

  @override
  State<BarcodeSheetPage> createState() => _BarcodeSheetPageState();
}

class _BarcodeSheetPageState extends State<BarcodeSheetPage> {
  // ── Physical label geometry (calibrate to the real sticker roll) ──────────
  static const double _labelWmm = 32;
  static const double _labelHmm = 25;
  static const int _cols = 3;
  // Horizontal gap between the 3 labels in a row. Adjust if the printed
  // barcodes drift off the die-cut on the first test print.
  static const double _gapMm = 2;

  // One PDF page == one printer row of 3 labels.
  PdfPageFormat get _rowFormat => PdfPageFormat(
        (_labelWmm * _cols + _gapMm * (_cols - 1)) * PdfPageFormat.mm,
        _labelHmm * PdfPageFormat.mm,
        marginAll: 0,
      );

  // Cached Thai font — the `pdf` package's default Helvetica cannot render Thai
  // glyphs, so product names need a bundled TTF.
  pw.Font? _thaiFont;

  Future<pw.Font> _loadFont() async {
    return _thaiFont ??=
        pw.Font.ttf(await rootBundle.load('assets/fonts/Sarabun-Regular.ttf'));
  }

  /// Flatten every copy in pick order, then pack [_cols] labels per row so each
  /// row is filled before starting the next. Only the final row is padded with
  /// blank cells (null). e.g. 4 different items × 1 → [a,b,c] then [d, null,
  /// null] = 2 rows; a single item qty 1 → [item, null, null].
  List<List<BarcodePickItem?>> _rows() {
    final copies = <BarcodePickItem>[];
    for (final it in widget.items) {
      for (var i = 0; i < it.qty; i++) {
        copies.add(it);
      }
    }
    final rows = <List<BarcodePickItem?>>[];
    for (var i = 0; i < copies.length; i += _cols) {
      rows.add([
        for (var c = 0; c < _cols; c++)
          (i + c < copies.length) ? copies[i + c] : null,
      ]);
    }
    return rows;
  }

  Future<Uint8List> _buildPdf(PdfPageFormat _) async {
    final font = await _loadFont();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );

    // One PDF page per printer row; blank cells render as empty space.
    for (final row in _rows()) {
      doc.addPage(
        pw.Page(
          pageFormat: _rowFormat,
          build: (ctx) => pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < _cols; c++) ...[
                if (c > 0) pw.SizedBox(width: _gapMm * PdfPageFormat.mm),
                pw.Expanded(
                  child: row[c] != null ? _buildLabel(row[c]!) : pw.SizedBox(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return doc.save();
  }

  pw.Widget _buildLabel(BarcodePickItem it) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.3),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          // Top — product name (truncated to one line)
          pw.Text(
            it.name,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: const pw.TextStyle(fontSize: 6.5),
          ),
          // Middle — Code128 barcode
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.code128(escapes: false),
                data: it.barcode,
                drawText: false,
                color: PdfColors.black,
              ),
            ),
          ),
          // Bottom — human-readable barcode value
          pw.Text(
            it.barcode,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 6, letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.fold<int>(0, (sum, it) => sum + it.qty);
    final rows = _rows().length;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'กลับ',
        ),
        title: Text('พิมพ์บาร์โค้ด ($total ดวง = $rows แถว)'),
      ),
      body: PdfPreview(
        build: _buildPdf,
        initialPageFormat: _rowFormat,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        useActions: true,
        pdfFileName: 'barcodes.pdf',
      ),
    );
  }
}
