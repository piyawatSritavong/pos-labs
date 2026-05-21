import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/backoffice/barcode_sheet_page.dart';
import 'package:provider/provider.dart';

/// Backoffice page (admin only) that lets the operator pick which parts to
/// print barcodes for and how many copies of each. Selecting "Print"
/// navigates to [BarcodeSheetPage] which renders an A4-friendly grid and
/// triggers `window.print()`.
///
/// User journey:
///   1. Page loads → fetch all parts (up to 2,000)
///   2. Operator ticks rows + adjusts the quantity field for each picked row
///      ("Select all" toggle + per-row checkbox)
///   3. Operator clicks "พิมพ์ X รายการ (Y ดวงรวม)" → BarcodeSheetPage opens
class BarcodePrintPage extends StatefulWidget {
  const BarcodePrintPage({super.key});

  @override
  State<BarcodePrintPage> createState() => _BarcodePrintPageState();
}

class _BarcodePrintPageState extends State<BarcodePrintPage> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _parts = [];
  // partCode → copies to print. Presence in the map = row is selected.
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
        _selectedQty[code] = _selectedQty[code] ?? 1;
      } else {
        _selectedQty.remove(code);
      }
    });
  }

  void _setQty(String code, int qty) {
    if (qty < 1) qty = 1;
    if (qty > 999) qty = 999; // sane upper bound — one A4 page holds 36
    setState(() {
      _selectedQty[code] = qty;
    });
  }

  void _toggleSelectAll(bool? checked) {
    setState(() {
      _selectedQty.clear();
      if (checked == true) {
        for (final p in _filtered) {
          final code = (p['code'] ?? '').toString();
          if (code.isNotEmpty) _selectedQty[code] = 1;
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
                '(${_totalCopies} ดวงรวม)',
                style: const TextStyle(color: Colors.grey),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _selectedQty.isEmpty ? null : _openSheet,
                icon: const Icon(Icons.print),
                label: Text(
                  'พิมพ์ ${_selectedQty.length} รายการ ($_totalCopies ดวงรวม)',
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
                              DataColumn(label: Text('จำนวนพิมพ์')),
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
                              final qty = _selectedQty[code] ?? 1;
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
                                  DataCell(
                                    SizedBox(
                                      width: 80,
                                      child: TextFormField(
                                        key: ValueKey('qty-$code'),
                                        initialValue: qty.toString(),
                                        enabled: selected,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly,
                                        ],
                                        textAlign: TextAlign.center,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          contentPadding:
                                              EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 8,
                                          ),
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (v) {
                                          final n = int.tryParse(v) ?? 1;
                                          _setQty(code, n);
                                        },
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
