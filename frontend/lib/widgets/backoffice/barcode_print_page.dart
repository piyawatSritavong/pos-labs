import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/backoffice/barcode_sheet_page.dart';
import 'package:provider/provider.dart';

/// Backoffice page (admin only) that lets the operator pick which parts to
/// print barcodes for and how many copies of each. Selecting "Print"
/// navigates to [BarcodeSheetPage] which builds an exact-mm label PDF
/// (32×25 mm, 3 labels per row) for the EasyPrint ES-9920UW thermal printer.
///
/// The printer feeds one row (3 labels) at a time, so the per-item quantity is
/// constrained to multiples of 3 — each picked product then fills whole rows
/// and rows are never mixed across products.
///
/// User journey:
///   1. Page loads → fetch all parts (up to 2,000)
///   2. Operator ticks rows + adjusts the quantity (stepper, ±3) for each
///      picked row ("Select all" toggle + per-row checkbox)
///   3. Operator clicks "พิมพ์ X รายการ (Y ดวง = Z แถว)" → BarcodeSheetPage opens
class BarcodePrintPage extends StatefulWidget {
  const BarcodePrintPage({super.key});

  @override
  State<BarcodePrintPage> createState() => _BarcodePrintPageState();
}

class _BarcodePrintPageState extends State<BarcodePrintPage> {
  // Labels are printed 3 across (one printer row), so every quantity is a
  // multiple of this step. _step also serves as the default/minimum copies.
  static const int _step = 3;

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _parts = [];
  // partCode → copies to print (always a multiple of _step). Presence in the
  // map = row is selected.
  final Map<String, int> _selectedQty = {};
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadParts();
  }

  Future<void> _loadParts() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null) {
      setState(() {
        _isLoading = false;
        _error = 'ยังไม่ได้ login';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await ApiService.getParts(token: token, limit: 2000);
      if (!mounted) return;
      setState(() {
        _parts = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _parts;
    final q = _search.toLowerCase();
    return _parts.where((p) {
      final code = (p['code'] ?? '').toString().toLowerCase();
      final name =
          ((p['nameTh'] ?? p['name'] ?? '') as Object).toString().toLowerCase();
      final bar = (p['barCode'] ?? '').toString().toLowerCase();
      return code.contains(q) || name.contains(q) || bar.contains(q);
    }).toList();
  }

  int get _totalCopies =>
      _selectedQty.values.fold<int>(0, (sum, q) => sum + q);

  void _toggleRow(String code, bool? checked) {
    setState(() {
      if (checked == true) {
        _selectedQty[code] = _selectedQty[code] ?? _step;
      } else {
        _selectedQty.remove(code);
      }
    });
  }

  /// Snap [qty] to the nearest multiple of [_step] (min one row, max 999).
  void _setQty(String code, int qty) {
    if (qty < _step) qty = _step;
    if (qty > 999) qty = 999;
    qty = ((qty + _step ~/ 2) ~/ _step) * _step; // round to nearest row
    setState(() {
      _selectedQty[code] = qty;
    });
  }

  void _bumpQty(String code, int rows) {
    final current = _selectedQty[code] ?? _step;
    _setQty(code, current + rows * _step);
  }

  void _toggleSelectAll(bool? checked) {
    setState(() {
      _selectedQty.clear();
      if (checked == true) {
        for (final p in _filtered) {
          final code = (p['code'] ?? '').toString();
          if (code.isNotEmpty) _selectedQty[code] = _step;
        }
      }
    });
  }

  void _openSheet() {
    // Build the print list — preserves the table's row order so the operator
    // can predict which barcode goes where on the sheet.
    final picks = <BarcodePickItem>[];
    for (final p in _parts) {
      final code = (p['code'] ?? '').toString();
      final qty = _selectedQty[code];
      if (qty == null || qty <= 0) continue;
      final name = (p['nameTh']?.toString().isNotEmpty == true
              ? p['nameTh']
              : p['name'])
          ?.toString() ??
          '';
      final barRaw = (p['barCode'] ?? '').toString();
      final barcode = barRaw.isEmpty ? code : barRaw;
      picks.add(BarcodePickItem(
        partCode: code,
        name: name,
        barcode: barcode,
        qty: qty,
      ));
    }
    if (picks.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BarcodeSheetPage(items: picks),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final allChecked = filtered.isNotEmpty &&
        filtered.every((p) => _selectedQty.containsKey(p['code']?.toString()));
    final partiallyChecked = !allChecked &&
        filtered.any((p) => _selectedQty.containsKey(p['code']?.toString()));

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadParts,
              icon: const Icon(Icons.refresh),
              label: const Text('โหลดใหม่'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header toolbar ───────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'ค้นหา (รหัส / ชื่อ / barcode)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v.trim()),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _loadParts,
                icon: const Icon(Icons.refresh),
                label: const Text('รีเฟรช'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                tristate: true,
                value: allChecked
                    ? true
                    : (partiallyChecked ? null : false),
                onChanged: (v) => _toggleSelectAll(v ?? false),
              ),
              const Text('เลือกทั้งหมด'),
              const SizedBox(width: 24),
              Text(
                'เลือกแล้ว: ${_selectedQty.length} รายการ '
                '($_totalCopies ดวง = ${_totalCopies ~/ _step} แถว)',
                style: const TextStyle(color: Colors.grey),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _selectedQty.isEmpty ? null : _openSheet,
                icon: const Icon(Icons.print),
                label: Text(
                  'พิมพ์ ${_selectedQty.length} รายการ '
                  '($_totalCopies ดวง = ${_totalCopies ~/ _step} แถว)',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── DataTable ────────────────────────────────────────────────────
          Expanded(
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: filtered.isEmpty
                  ? const Center(child: Text('ไม่พบสินค้า'))
                  : Scrollbar(
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowHeight: 44,
                            dataRowMinHeight: 44,
                            dataRowMaxHeight: 56,
                            columns: const [
                              DataColumn(label: SizedBox(width: 30)),
                              DataColumn(label: Text('รหัส')),
                              DataColumn(label: Text('ชื่อสินค้า')),
                              DataColumn(label: Text('Barcode')),
                              DataColumn(label: Text('จำนวนพิมพ์ (×3)')),
                            ],
                            rows: filtered.map((p) {
                              final code = (p['code'] ?? '').toString();
                              final name = (p['nameTh']?.toString().isNotEmpty == true
                                      ? p['nameTh']
                                      : p['name'])
                                  ?.toString() ??
                                  '';
                              final barRaw = (p['barCode'] ?? '').toString();
                              final bar = barRaw.isEmpty ? code : barRaw;
                              final selected = _selectedQty.containsKey(code);
                              final qty = _selectedQty[code] ?? _step;
                              return DataRow(
                                selected: selected,
                                cells: [
                                  DataCell(Checkbox(
                                    value: selected,
                                    onChanged: (v) => _toggleRow(code, v),
                                  )),
                                  DataCell(Text(code)),
                                  DataCell(Text(name)),
                                  DataCell(Text(bar)),
                                  // Quantity stepper — copies move in whole rows
                                  // of 3 (one printer feed). Disabled until the
                                  // row is selected.
                                  DataCell(
                                    Opacity(
                                      opacity: selected ? 1 : 0.4,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                                Icons.remove_circle_outline),
                                            iconSize: 20,
                                            visualDensity: VisualDensity.compact,
                                            tooltip: 'ลด 3',
                                            onPressed: selected
                                                ? () => _bumpQty(code, -1)
                                                : null,
                                          ),
                                          SizedBox(
                                            width: 40,
                                            child: Text(
                                              '$qty',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                                Icons.add_circle_outline),
                                            iconSize: 20,
                                            visualDensity: VisualDensity.compact,
                                            tooltip: 'เพิ่ม 3',
                                            onPressed: selected
                                                ? () => _bumpQty(code, 1)
                                                : null,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
