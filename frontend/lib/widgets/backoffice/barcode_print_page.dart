import 'dart:async';

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
/// The printer feeds one row (3 labels) at a time. Any quantity is allowed —
/// labels are packed 3 per row (filling each row before the next) and only the
/// final row is padded with blank cells (e.g. 4 labels → [a,b,c] then
/// [d, blank, blank]).
///
/// Data is loaded one page at a time via server-side search (`/parts/search`)
/// instead of pulling the whole catalog, so it scales to thousands of parts.
/// The selection persists across searches/pages: [_selectedQty] and
/// [_selectedMeta] are keyed by part code, and each selection captures the
/// part's name + barcode at pick time so the print sheet can be built even for
/// items not on the currently visible page.
class BarcodePrintPage extends StatefulWidget {
  const BarcodePrintPage({super.key});

  @override
  State<BarcodePrintPage> createState() => _BarcodePrintPageState();
}

class _BarcodePrintPageState extends State<BarcodePrintPage> {
  // Labels are printed _perRow across (one printer row). Quantity is free-form
  // (min 1); a partial last row is padded with blanks on the sheet. _perRow is
  // only used to estimate the printed row count shown in the UI.
  static const int _perRow = 3;
  static const int _pageSize = 50;

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _parts = []; // current page
  String _query = '';
  int _offset = 0;
  bool _hasMore = false;

  // partCode → copies to print (>= 1). Presence in the map = selected.
  final Map<String, int> _selectedQty = {};
  // partCode → {name, barcode} captured at selection time so the print sheet can
  // be built for selections that are no longer on the visible page.
  final Map<String, Map<String, String>> _selectedMeta = {};

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadParts(resetOffset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadParts({bool resetOffset = false}) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null) {
      setState(() {
        _isLoading = false;
        _error = 'ยังไม่ได้ login';
      });
      return;
    }
    if (resetOffset) _offset = 0;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await ApiService.searchParts(
        token: token,
        query: _query,
        limit: _pageSize,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _parts = items;
        _hasMore = items.length == _pageSize;
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

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = value.trim();
      _loadParts(resetOffset: true);
    });
  }

  Future<void> _nextPage() async {
    if (!_hasMore || _isLoading) return;
    _offset += _pageSize;
    await _loadParts();
  }

  Future<void> _prevPage() async {
    if (_offset <= 0 || _isLoading) return;
    _offset = (_offset - _pageSize).clamp(0, _offset);
    await _loadParts();
  }

  String _nameOf(Map<String, dynamic> p) =>
      (p['nameTh']?.toString().isNotEmpty == true ? p['nameTh'] : p['name'])
          ?.toString() ??
      '';

  String _barcodeOf(Map<String, dynamic> p) {
    final code = (p['code'] ?? '').toString();
    final barRaw = (p['barCode'] ?? '').toString();
    return barRaw.isEmpty ? code : barRaw;
  }

  int get _totalCopies =>
      _selectedQty.values.fold<int>(0, (sum, q) => sum + q);

  // Estimated printed rows: all copies are packed _perRow per row, so the row
  // count is the total rounded up (only the final row is padded with blanks).
  int get _totalRows => (_totalCopies + _perRow - 1) ~/ _perRow;

  void _toggleRow(Map<String, dynamic> p, bool? checked) {
    final code = (p['code'] ?? '').toString();
    if (code.isEmpty) return;
    setState(() {
      if (checked == true) {
        _selectedQty[code] = _selectedQty[code] ?? 1;
        _selectedMeta[code] = {'name': _nameOf(p), 'barcode': _barcodeOf(p)};
      } else {
        _selectedQty.remove(code);
        _selectedMeta.remove(code);
      }
    });
  }

  /// Clamp [qty] to a valid count (min 1, max 999). Any value is allowed —
  /// the sheet pads partial rows with blanks.
  void _setQty(String code, int qty) {
    if (qty < 1) qty = 1;
    if (qty > 999) qty = 999;
    setState(() {
      _selectedQty[code] = qty;
    });
  }

  void _bumpQty(String code, int delta) {
    final current = _selectedQty[code] ?? 1;
    _setQty(code, current + delta);
  }

  /// Select/clear every row on the *current page* (selection on other pages is
  /// preserved). Server-side paging means we never have the whole catalog in
  /// memory, so "select all" is scoped to what is visible.
  void _toggleSelectPage(bool? checked) {
    setState(() {
      for (final p in _parts) {
        final code = (p['code'] ?? '').toString();
        if (code.isEmpty) continue;
        if (checked == true) {
          _selectedQty[code] = _selectedQty[code] ?? 1;
          _selectedMeta[code] = {'name': _nameOf(p), 'barcode': _barcodeOf(p)};
        } else {
          _selectedQty.remove(code);
          _selectedMeta.remove(code);
        }
      }
    });
  }

  void _openSheet() {
    // Build the print list from every selection (across all pages), using the
    // metadata captured at pick time. Sorted by code for predictable layout.
    final codes = _selectedQty.keys.toList()..sort();
    final picks = <BarcodePickItem>[];
    for (final code in codes) {
      final qty = _selectedQty[code];
      if (qty == null || qty <= 0) continue;
      final meta = _selectedMeta[code] ?? const {};
      final barcode = (meta['barcode']?.isNotEmpty == true)
          ? meta['barcode']!
          : code;
      picks.add(BarcodePickItem(
        partCode: code,
        name: meta['name'] ?? '',
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
    final pageChecked = _parts.isNotEmpty &&
        _parts.every((p) => _selectedQty.containsKey(p['code']?.toString()));
    final pagePartial = !pageChecked &&
        _parts.any((p) => _selectedQty.containsKey(p['code']?.toString()));

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
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'ค้นหา (รหัส / ชื่อ / barcode)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: _onSearchChanged,
                  onSubmitted: (v) {
                    _debounce?.cancel();
                    _query = v.trim();
                    _loadParts(resetOffset: true);
                  },
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _loadParts(),
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
                value: pageChecked ? true : (pagePartial ? null : false),
                onChanged: (v) => _toggleSelectPage(v ?? false),
              ),
              const Text('เลือกหน้านี้'),
              const SizedBox(width: 24),
              Text(
                'เลือกแล้ว: ${_selectedQty.length} รายการ '
                '($_totalCopies ดวง = $_totalRows แถว)',
                style: const TextStyle(color: Colors.grey),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _selectedQty.isEmpty ? null : _openSheet,
                icon: const Icon(Icons.print),
                label: Text(
                  'พิมพ์ ${_selectedQty.length} รายการ '
                  '($_totalCopies ดวง = $_totalRows แถว)',
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
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!,
                                  style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () => _loadParts(),
                                icon: const Icon(Icons.refresh),
                                label: const Text('โหลดใหม่'),
                              ),
                            ],
                          ),
                        )
                      : _parts.isEmpty
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
                                      DataColumn(
                                          label: Text('จำนวนพิมพ์')),
                                    ],
                                    rows: _parts.map((p) {
                                      final code = (p['code'] ?? '').toString();
                                      final name = _nameOf(p);
                                      final bar = _barcodeOf(p);
                                      final selected =
                                          _selectedQty.containsKey(code);
                                      final qty = _selectedQty[code] ?? 1;
                                      return DataRow(
                                        selected: selected,
                                        cells: [
                                          DataCell(Checkbox(
                                            value: selected,
                                            onChanged: (v) => _toggleRow(p, v),
                                          )),
                                          DataCell(Text(code)),
                                          DataCell(Text(name)),
                                          DataCell(Text(bar)),
                                          // Quantity stepper — ±1 (any count;
                                          // partial last row is padded blank).
                                          DataCell(
                                            Opacity(
                                              opacity: selected ? 1 : 0.4,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons
                                                        .remove_circle_outline),
                                                    iconSize: 20,
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    tooltip: 'ลด 1',
                                                    onPressed: selected
                                                        ? () =>
                                                            _bumpQty(code, -1)
                                                        : null,
                                                  ),
                                                  SizedBox(
                                                    width: 40,
                                                    child: Text(
                                                      '$qty',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600),
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons
                                                        .add_circle_outline),
                                                    iconSize: 20,
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    tooltip: 'เพิ่ม 1',
                                                    onPressed: selected
                                                        ? () =>
                                                            _bumpQty(code, 1)
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
          const SizedBox(height: 12),
          // Server-side pagination (page size = _pageSize).
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: 'ก่อนหน้า',
                onPressed: (_isLoading || _offset <= 0) ? null : _prevPage,
              ),
              Text('หน้า ${(_offset ~/ _pageSize) + 1}'),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: 'ถัดไป',
                onPressed: (_isLoading || !_hasMore) ? null : _nextPage,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
