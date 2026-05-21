import 'package:barcode_widget/barcode_widget.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// One item picked on [BarcodePrintPage] — partCode + name shown beneath the
/// rendered Code128 + qty (number of copies to print).
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

/// Renders the picked items as a printable A4 sheet:
/// - 4 columns × 9 rows = 36 labels per page (50×30 mm each)
/// - Each label: Code128 barcode, the barcode value below, the part name below
/// - On first mount the page auto-triggers `window.print()` so the operator
///   sees the system print dialog immediately
/// - The screen-only "พิมพ์อีกครั้ง" / "กลับ" buttons are hidden during print
///   via the `no-print` CSS class declared in web/index.html
class BarcodeSheetPage extends StatefulWidget {
  const BarcodeSheetPage({super.key, required this.items});

  final List<BarcodePickItem> items;

  @override
  State<BarcodeSheetPage> createState() => _BarcodeSheetPageState();
}

class _BarcodeSheetPageState extends State<BarcodeSheetPage> {
  // 50 mm × 30 mm — at 96 DPI ≈ 189 × 113 px. Use logical px close enough.
  static const double _labelW = 189;
  static const double _labelH = 113;
  static const int _cols = 4;

  // Hide the AppBar (and any other screen-only chrome) while the browser
  // print dialog is open. Flutter Web's canvas renderer doesn't attach HTML
  // classes, so the `.no-print` CSS rule in index.html can't reach Flutter
  // widgets. Instead we listen for `beforeprint` / `afterprint` events and
  // toggle Flutter state so the layout re-renders without the AppBar during
  // print, then restores it after.
  bool _isPrinting = false;
  // dart:html does not expose typed Stream getters for beforeprint/afterprint,
  // so we attach raw EventListeners via addEventListener and remove them in
  // dispose. Storing them as `html.EventListener` is required for removal.
  html.EventListener? _beforePrintHandler;
  html.EventListener? _afterPrintHandler;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _beforePrintHandler = (html.Event _) {
        if (mounted) setState(() => _isPrinting = true);
      };
      _afterPrintHandler = (html.Event _) {
        if (mounted) setState(() => _isPrinting = false);
      };
      html.window.addEventListener('beforeprint', _beforePrintHandler);
      html.window.addEventListener('afterprint', _afterPrintHandler);

      // Auto-open the browser print dialog once the sheet has been laid out.
      // Fire after one extra frame so BarcodeWidget actually paints first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 250), () {
          try {
            html.window.print();
          } catch (_) {
            // Some browsers throw if window is not focused — operator can
            // still click "พิมพ์อีกครั้ง" manually.
          }
        });
      });
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      if (_beforePrintHandler != null) {
        html.window.removeEventListener('beforeprint', _beforePrintHandler);
      }
      if (_afterPrintHandler != null) {
        html.window.removeEventListener('afterprint', _afterPrintHandler);
      }
    }
    super.dispose();
  }

  void _printAgain() {
    if (kIsWeb) {
      try {
        html.window.print();
      } catch (_) {}
    }
  }

  /// Expand each picked item into individual copies. e.g. {P0001, qty:3} →
  /// 3 cells. Preserves operator's row order.
  List<BarcodePickItem> _expanded() {
    final out = <BarcodePickItem>[];
    for (final it in widget.items) {
      for (var i = 0; i < it.qty; i++) {
        out.add(it);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final copies = _expanded();
    return Scaffold(
      backgroundColor: Colors.white,
      // During print: AppBar is removed entirely → only the barcode Wrap
      // remains, which is exactly what the printer should produce.
      appBar: _isPrinting ? null : PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          // The whole app bar is screen-only — hidden in print via no-print.
          color: Colors.white,
          child: SafeArea(
            child: Row(
              children: [
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'กลับ',
                ),
                Text(
                  'พิมพ์บาร์โค้ด (${copies.length} ดวง)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: ElevatedButton.icon(
                    onPressed: _printAgain,
                    icon: const Icon(Icons.print),
                    label: const Text('พิมพ์อีกครั้ง'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        // The sheet itself — visible in both screen + print views.
        // class="printable" lets the print CSS strip page chrome around it.
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: copies.map((it) => _buildLabel(it)).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(BarcodePickItem it) {
    return Container(
      width: _labelW,
      height: _labelH,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 0.5),
      ),
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top — product name (truncated)
          Text(
            it.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w500),
          ),
          // Middle — barcode
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: BarcodeWidget(
                data: it.barcode,
                barcode: Barcode.code128(escapes: false),
                drawText: false,
                color: Colors.black,
              ),
            ),
          ),
          // Bottom — barcode value (human-readable) + part code
          Text(
            it.barcode,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // Helper kept for clarity in case we expand the layout later.
  // ignore: unused_element
  int get _maxCols => _cols;
}
