import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/qty_stepper.dart';
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
  // Page size is user-selectable (20/50/100) to match the Parts page.
  int _pageSize = 50;

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _parts = []; // current page
  String _query = '';
  int _offset = 0;
  bool _hasMore = false;
  int _total = 0; // total matches across all pages (drives page-jump)

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
      final result = await ApiService.searchPartsPaged(
        token: token,
        query: _query,
        limit: _pageSize,
        offset: _offset,
        // Print labels for any product, including ones with no stock in the
        // current branch (e.g. just created), so they aren't hidden here.
        crossBranch: true,
      );
      final items = result.parts;
      if (!mounted) return;
      setState(() {
        _parts = items;
        _total = result.total;
        _hasMore = _offset + items.length < _total;
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

  int get _pageCount => _total <= 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);
  int get _currentPage => (_offset ~/ _pageSize) + 1;

  Future<void> _goToPage(int page) async {
    if (_isLoading) return;
    final p = page.clamp(1, _pageCount);
    _offset = (p - 1) * _pageSize;
    await _loadParts();
  }

  Future<void> _setPageSize(int size) async {
    if (_isLoading || size == _pageSize) return;
    _pageSize = size;
    _offset = 0;
    await _loadParts();
  }

  String _nameOf(Map<String, dynamic> p) =>
      (p['nameTh']?.toString().isNotEmpty == true ? p['nameTh'] : p['name'])
          ?.toString() ??
      '';

  /// Price as it should read on the sticker: whole baht lose the ".00", the
  /// rest keep two decimals. An unpriced product simply gets no price on it.
  String _priceOf(Map<String, dynamic> p) {
    final value = double.tryParse(p['price']?.toString() ?? '');
    if (value == null || value <= 0) return '';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

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
        _selectedMeta[code] = {
          'name': _nameOf(p),
          'barcode': _barcodeOf(p),
          'price': _priceOf(p),
        };
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
          _selectedMeta[code] = {
          'name': _nameOf(p),
          'barcode': _barcodeOf(p),
          'price': _priceOf(p),
        };
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
        price: meta['price'] ?? '',
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
                                          // Label count — steppable and
                                          // typeable (a partial last row is
                                          // padded blank).
                                          DataCell(
                                            Opacity(
                                              opacity: selected ? 1 : 0.4,
                                              child: QtyStepper(
                                                key:
                                                    ValueKey('label-qty-$code'),
                                                value: qty,
                                                min: 1,
                                                max: 999,
                                                enabled: selected,
                                                compact: true,
                                                fieldWidth: 48,
                                                decrementTooltip: 'ลด 1',
                                                incrementTooltip: 'เพิ่ม 1',
                                                onChanged: (v) =>
                                                    _setQty(code, v),
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
          // Server-side pagination: page-size filter + page-jump dropdown
          // (matches the Parts page).
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('แสดงหน้าละ'),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _pageSize,
                items: const [20, 50, 100]
                    .map((s) => DropdownMenuItem(value: s, child: Text('$s')))
                    .toList(),
                onChanged: _isLoading
                    ? null
                    : (v) {
                        if (v != null) _setPageSize(v);
                      },
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: 'ก่อนหน้า',
                onPressed: (_isLoading || _offset <= 0) ? null : _prevPage,
              ),
              const Text('หน้า'),
              const SizedBox(width: 6),
              DropdownButton<int>(
                value: _currentPage.clamp(1, _pageCount),
                items: [
                  for (var p = 1; p <= _pageCount; p++)
                    DropdownMenuItem(value: p, child: Text('$p')),
                ],
                onChanged: _isLoading
                    ? null
                    : (v) {
                        if (v != null) _goToPage(v);
                      },
              ),
              const SizedBox(width: 6),
              Text('/ $_pageCount  ($_total รายการ)'),
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
