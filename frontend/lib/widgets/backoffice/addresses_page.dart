import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/providers/auth_provider.dart';

class AddressesManagementSection extends StatefulWidget {
  const AddressesManagementSection({super.key, this.autoLoad = true});

  final bool autoLoad;

  @override
  State<AddressesManagementSection> createState() =>
      _AddressesManagementSectionState();
}

class _AddressesManagementSectionState
    extends State<AddressesManagementSection> {
  // Server-side search + paging: one page of /addresses at a time, filtered by
  // q/storeId on the backend instead of loading the whole catalog into Dart.
  // Page size is user-selectable (20/50/100) to match the Parts page.
  int _pageSize = 50;

  bool _isLoading = false;
  String? _errorMessage;

  // Current page of results.
  List<Map<String, dynamic>> _addresses = [];

  // Total matches across all pages (from backend `total`) — drives page-jump.
  int _total = 0;

  // Canonical store list from GET /stores (same source the Parts page uses, so
  // the two store dropdowns are always identical). Each entry:
  // {id, label, branchId, branchName}.
  List<Map<String, String>> _stores = [];

  // Filters + paging state.
  String? _selectedStoreId;
  String _query = '';
  int _offset = 0;
  bool _hasMore = false;

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      _load(resetOffset: true);
      _loadStores();
    }
  }

  Future<void> _loadStores() async {
    final token = context.read<AuthProvider>().token;
    if (token == null || token.isEmpty) return;
    try {
      final list = await ApiService.getStores(token: token);
      final stores = list
          .map(
            (s) => {
              'id': (s['id'] ?? '').toString(),
              'label': (s['labelTh'] ?? s['label'] ?? s['id'] ?? '').toString(),
              'branchId': (s['branchId'] ?? '').toString(),
              'branchName': (s['branchNameTh'] ?? s['branchName'] ?? '')
                  .toString(),
            },
          )
          .where((s) => (s['id'] ?? '').isNotEmpty)
          .toList();
      if (mounted) setState(() => _stores = stores);
    } catch (_) {
      // ใช้งานหน้าต่อได้แม้โหลดคลังไม่ได้
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool resetOffset = false}) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;

    if (token == null || token.isEmpty) {
      setState(() {
        _errorMessage = 'No auth token. Please login again.';
      });
      return;
    }

    if (resetOffset) _offset = 0;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await ApiService.getAddressesPaged(
        token: token,
        limit: _pageSize,
        offset: _offset,
        query: _query,
        storeId: _selectedStoreId,
      );
      final items = result.addresses;

      if (!mounted) return;
      setState(() {
        _addresses = items;
        _total = result.total;
        _hasMore = _offset + items.length < _total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = value.trim();
      _load(resetOffset: true);
    });
  }

  Future<void> _nextPage() async {
    if (!_hasMore || _isLoading) return;
    _offset += _pageSize;
    await _load();
  }

  Future<void> _prevPage() async {
    if (_offset <= 0 || _isLoading) return;
    _offset = (_offset - _pageSize).clamp(0, _offset);
    await _load();
  }

  int get _pageCount =>
      _total <= 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);
  int get _currentPage => (_offset ~/ _pageSize) + 1;

  Future<void> _goToPage(int page) async {
    if (_isLoading) return;
    final p = page.clamp(1, _pageCount);
    _offset = (p - 1) * _pageSize;
    await _load();
  }

  Future<void> _setPageSize(int size) async {
    if (_isLoading || size == _pageSize) return;
    _pageSize = size;
    _offset = 0;
    await _load();
  }

  List<DropdownMenuItem<String>> _buildStoreDropdownItems() {
    return _stores
        .map(
          (s) => DropdownMenuItem<String>(
            value: s['id'],
            child: Text(s['label'] ?? s['id'] ?? ''),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: double.infinity),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Filters row (store selector + search + refresh)
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'คลังสินค้า',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      value: _selectedStoreId,
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('ทุกคลัง'),
                        ),
                        ..._buildStoreDropdownItems(),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedStoreId = value;
                        });
                        _load(resetOffset: true);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'ค้นหาด้วยรหัสสินค้า ชื่อสินค้า หรือคลัง...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: _onSearchChanged,
                      onSubmitted: (value) {
                        _debounce?.cancel();
                        _query = value.trim();
                        _load(resetOffset: true);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'รีเฟรช',
                    onPressed: _isLoading ? null : () => _load(),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Main card with inventory table
              Expanded(
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.all(16.0),
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _errorMessage != null
                        ? _buildErrorState()
                        : _addresses.isEmpty
                        ? const Center(child: Text('ไม่พบข้อมูลคลังสินค้า'))
                        : _buildDataTable(_addresses),
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
                        .map(
                          (s) => DropdownMenuItem(value: s, child: Text('$s')),
                        )
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
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, color: Colors.red),
        const SizedBox(height: 8),
        Text(_errorMessage ?? 'Unknown error', textAlign: TextAlign.center),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () => _load(),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }

  // Edit the stock and its single low-stock threshold. ROP is the reorder
  // point the POS "สต็อกใกล้หมด" alert uses (per product). Current
  // qty/shelf/remarks are re-sent so a partial update never wipes them.
  Future<void> _editThreshold(Map<String, dynamic> a) async {
    final code = (a['code'] ?? '').toString();
    if (code.isEmpty) return;
    final qtyC = TextEditingController(text: (a['qty'] ?? '').toString());
    final ropC = TextEditingController(text: (a['rop'] ?? '').toString());
    final costC = TextEditingController(text: (a['cost'] ?? '0').toString());
    final priceC = TextEditingController(text: (a['price'] ?? '0').toString());
    final minPriceC = TextEditingController(
      text: (a['minPrice'] ?? a['min_price'] ?? '0').toString(),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('แก้ไขสต๊อก/แจ้งเตือน — ${(a['partCode'] ?? '')}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'จำนวนคงเหลือ (Qty)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ropC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'ROP (จุดสั่งซื้อ — ใช้แจ้งเตือนสต๊อกใกล้หมด)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: costC,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'ต้นทุน',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priceC,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'ราคาขายจริง',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: minPriceC,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'ราคาลดได้ (ราคาขายขั้นต่ำ)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final token = context.read<AuthProvider>().token ?? '';
    if (token.isEmpty) return;
    int? toInt(dynamic v) => int.tryParse((v ?? '').toString().trim());
    try {
      final cost = double.tryParse(costC.text.replaceAll(',', '').trim());
      final price = double.tryParse(priceC.text.replaceAll(',', '').trim());
      final minPrice = double.tryParse(
        minPriceC.text.replaceAll(',', '').trim(),
      );
      if (cost == null ||
          price == null ||
          minPrice == null ||
          cost < 0 ||
          minPrice < 0 ||
          minPrice > price) {
        throw Exception(
          'ราคาต้องเป็นตัวเลขไม่ติดลบ และราคาลดได้ต้องไม่สูงกว่าราคาขายจริง',
        );
      }
      final part = await ApiService.getPartByCode(
        token: token,
        code: (a['partCode'] ?? '').toString(),
      );
      final unit = part['unit'];
      await ApiService.updatePart(
        token: token,
        code: (a['partCode'] ?? '').toString(),
        name: (part['name'] ?? part['nameTh'] ?? '').toString(),
        nameTh: (part['nameTh'] ?? part['name'] ?? '').toString(),
        barcode: (part['barCode'] ?? part['barcode'] ?? '').toString(),
        unitId: unit is Map
            ? (unit['id'] ?? 'pcs').toString()
            : (unit ?? 'pcs').toString(),
        cost: cost,
        price: price,
        minPrice: minPrice,
      );
      await ApiService.updateAddress(
        token: token,
        code: code,
        partCode: (a['partCode'] ?? '').toString(),
        storeId: (a['storeId'] ?? '').toString(),
        shelf: (a['shelf'] ?? '').toString(),
        qty: toInt(qtyC.text),
        remarks: (a['remarks'] ?? '').toString(),
        rop: toInt(ropC.text),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('บันทึกค่าแจ้งเตือนแล้ว')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
    }
  }

  Widget _buildDataTable(List<Map<String, dynamic>> items) {
    return Scrollbar(
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 44,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 56,
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text('รหัสสินค้า')),
              DataColumn(label: Text('ชื่อสินค้า')),
              DataColumn(label: Text('คลัง')),
              DataColumn(label: Text('ชั้นวาง')),
              DataColumn(label: Text('จำนวน')),
              DataColumn(label: Text('ต้นทุน')),
              DataColumn(label: Text('ราคาขายจริง')),
              DataColumn(label: Text('ราคาลดได้')),
              DataColumn(label: Text('จุดสั่งซื้อ (ROP)')),
              DataColumn(label: Text('แก้ไข')),
            ],
            rows: items.map((a) {
              final partCode = (a['partCode'] ?? '').toString();
              final partName = (a['partName'] ?? '').toString();
              final storeName = (a['storeName'] ?? a['storeId'] ?? '')
                  .toString();
              final shelf = (a['shelf'] ?? '').toString();
              final qty = (a['qty'] ?? '').toString();
              String money(dynamic value) {
                final parsed = double.tryParse((value ?? '').toString());
                return parsed == null ? '-' : '฿${parsed.toStringAsFixed(2)}';
              }

              final rop = (a['rop'] ?? '').toString();

              return DataRow(
                cells: [
                  DataCell(Text(partCode)),
                  DataCell(Text(partName.isEmpty ? '-' : partName)),
                  DataCell(Text(storeName.isEmpty ? '-' : storeName)),
                  DataCell(Text(shelf.isEmpty ? '-' : shelf)),
                  DataCell(Text(qty.isEmpty ? '-' : qty)),
                  DataCell(Text(money(a['cost']))),
                  DataCell(Text(money(a['price']))),
                  DataCell(Text(money(a['minPrice'] ?? a['min_price']))),
                  DataCell(Text(rop.isEmpty ? '-' : rop)),
                  DataCell(
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'แก้ไขจำนวนและจุดแจ้งเตือน',
                      onPressed: () => _editThreshold(a),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
