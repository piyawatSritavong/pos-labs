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
  bool _isLoading = false;
  String? _errorMessage;

  // ข้อมูลทั้งหมดจาก /addresses
  List<Map<String, dynamic>> _allAddresses = [];

  // filter
  String? _selectedStoreId;
  String _searchKeyword = '';

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;

    if (token == null || token.isEmpty) {
      setState(() {
        _errorMessage = 'No auth token. Please login again.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await ApiService.getAddresses(
        token: token,
        limit: 200,
        offset: 0,
      );

      setState(() {
        _allAddresses = items;
      });
    } catch (e) {
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

  List<Map<String, dynamic>> get _filteredAddresses {
    Iterable<Map<String, dynamic>> list = _allAddresses;

    if (_selectedStoreId != null && _selectedStoreId!.isNotEmpty) {
      list = list.where(
        (a) => (a['storeId'] ?? '').toString() == _selectedStoreId,
      );
    }

    if (_searchKeyword.isNotEmpty) {
      final q = _searchKeyword.toLowerCase();
      list = list.where((a) {
        final partCode = (a['partCode'] ?? '').toString().toLowerCase();
        final partName = (a['partName'] ?? '').toString().toLowerCase();
        final storeName = (a['storeName'] ?? '').toString().toLowerCase();
        return partCode.contains(q) ||
            partName.contains(q) ||
            storeName.contains(q);
      });
    }

    return list.toList();
  }

  List<DropdownMenuItem<String>> _buildStoreDropdownItems() {
    final Map<String, String> stores = {};

    for (final a in _allAddresses) {
      final storeId = (a['storeId'] ?? '').toString();
      if (storeId.isEmpty) continue;

      final storeName = (a['storeName'] ?? storeId).toString();
      stores[storeId] = storeName;
    }

    return stores.entries
        .map(
          (e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value)),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAddresses;

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
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 320,
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search by part code, name, store...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchKeyword = value;
                        });
                      },
                      onSubmitted: (value) {
                        setState(() {
                          _searchKeyword = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _isLoading ? null : _loadAddresses,
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
                        : filtered.isEmpty
                        ? const Center(child: Text('No addresses found.'))
                        : _buildDataTable(filtered),
                  ),
                ),
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
          onPressed: _loadAddresses,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
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
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
