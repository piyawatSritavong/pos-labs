import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/providers/auth_provider.dart';

class AddressesManagementSection extends StatefulWidget {
  const AddressesManagementSection({super.key});

  @override
  State<AddressesManagementSection> createState() =>
      _AddressesManagementSectionState();
}

class _AddressesManagementSectionState
    extends State<AddressesManagementSection> {
  // Server-side search + paging: one page of /addresses at a time, filtered by
  // q/storeId on the backend instead of loading the whole catalog into Dart.
  static const int _pageSize = 50;

  bool _isLoading = false;
  String? _errorMessage;

  // Current page of results.
  List<Map<String, dynamic>> _addresses = [];

  // Stores seen so far across loaded pages — used to populate the Store filter
  // without fetching the entire catalog (the text search also matches store
  // name server-side, so this only needs to grow as the user browses).
  final Map<String, String> _knownStores = {};

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
    _load(resetOffset: true);
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
      final items = await ApiService.getAddresses(
        token: token,
        limit: _pageSize,
        offset: _offset,
        query: _query,
        storeId: _selectedStoreId,
      );

      if (!mounted) return;
      setState(() {
        _addresses = items;
        _hasMore = items.length == _pageSize;
        for (final a in items) {
          final storeId = (a['storeId'] ?? '').toString();
          if (storeId.isEmpty) continue;
          _knownStores[storeId] = (a['storeName'] ?? storeId).toString();
        }
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

  List<DropdownMenuItem<String>> _buildStoreDropdownItems() {
    return _knownStores.entries
        .map(
          (e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value)),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
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
                        labelText: 'Store',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      value: _selectedStoreId,
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('All Stores'),
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
                        hintText: 'Search by part code, name, store...',
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
                    tooltip: 'Refresh',
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
                        ? const Center(child: Text('No addresses found.'))
                        : _buildDataTable(_addresses),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Server-side pagination controls.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Previous',
                    onPressed: (_isLoading || _offset <= 0) ? null : _prevPage,
                  ),
                  Text('Page ${(_offset ~/ _pageSize) + 1}'),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Next',
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

  // Edit the low-stock thresholds (Min / ROP / Max) for one address. ROP is the
  // reorder point the POS "สต็อกใกล้หมด" alert uses (per product). Current
  // qty/shelf/remarks are re-sent so a partial update never wipes them.
  Future<void> _editThreshold(Map<String, dynamic> a) async {
    final code = (a['code'] ?? '').toString();
    if (code.isEmpty) return;
    final minC = TextEditingController(text: (a['min'] ?? '').toString());
    final ropC = TextEditingController(text: (a['rop'] ?? '').toString());
    final maxC = TextEditingController(text: (a['max'] ?? '').toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ตั้งค่าแจ้งเตือนสต๊อก — ${(a['partCode'] ?? '')}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: minC,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Min (ขั้นต่ำ)',
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
              controller: maxC,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Max (สูงสุด)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
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
      await ApiService.updateAddress(
        token: token,
        code: code,
        partCode: (a['partCode'] ?? '').toString(),
        storeId: (a['storeId'] ?? '').toString(),
        shelf: (a['shelf'] ?? '').toString(),
        qty: toInt(a['qty']),
        remarks: (a['remarks'] ?? '').toString(),
        min: toInt(minC.text),
        rop: toInt(ropC.text),
        max: toInt(maxC.text),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกค่าแจ้งเตือนแล้ว')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
      );
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
              DataColumn(label: Text('Part Code')),
              DataColumn(label: Text('Part Name')),
              DataColumn(label: Text('Store')),
              DataColumn(label: Text('Shelf')),
              DataColumn(label: Text('Qty')),
              DataColumn(label: Text('Min / ROP')),
              DataColumn(label: Text('Max')),
              DataColumn(label: Text('ตั้งค่าแจ้งเตือน')),
            ],
            rows: items.map((a) {
              final partCode = (a['partCode'] ?? '').toString();
              final partName = (a['partName'] ?? '').toString();
              final storeName = (a['storeName'] ?? a['storeId'] ?? '')
                  .toString();
              final shelf = (a['shelf'] ?? '').toString();
              final qty = (a['qty'] ?? '').toString();
              final min = (a['min'] ?? '').toString();
              final rop = (a['rop'] ?? '').toString();
              final max = (a['max'] ?? '').toString();

              return DataRow(
                cells: [
                  DataCell(Text(partCode)),
                  DataCell(Text(partName.isEmpty ? '-' : partName)),
                  DataCell(Text(storeName.isEmpty ? '-' : storeName)),
                  DataCell(Text(shelf.isEmpty ? '-' : shelf)),
                  DataCell(Text(qty.isEmpty ? '-' : qty)),
                  DataCell(
                    Text(
                      '${min.isEmpty ? '-' : min} / ${rop.isEmpty ? '-' : rop}',
                    ),
                  ),
                  DataCell(Text(max.isEmpty ? '-' : max)),
                  DataCell(
                    IconButton(
                      icon: const Icon(Icons.edit_notifications_outlined),
                      tooltip: 'ตั้งค่าจุดแจ้งเตือน (Min/ROP/Max)',
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
