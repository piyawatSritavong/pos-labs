import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_operations.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class PurchaseOrdersPage extends StatefulWidget {
  const PurchaseOrdersPage({super.key});

  @override
  State<PurchaseOrdersPage> createState() => _PurchaseOrdersPageState();
}

class _PurchaseOrdersPageState extends State<PurchaseOrdersPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().token ?? '';
    if (token.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final orders = await ApiOperationsService.getPurchaseOrders(token: token);
      if (mounted) setState(() => _orders = orders);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreatePurchaseOrderDialog(),
    );
    if (saved == true) await _load();
  }

  Future<void> _showDetail(String id) async {
    final token = context.read<AuthProvider>().token ?? '';
    try {
      final order = await ApiOperationsService.getPurchaseOrder(
        token: token,
        id: id,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _PurchaseOrderDetail(order: order),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('เปิดเอกสารไม่สำเร็จ: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.playlist_add),
              label: const Text('สร้างใบสั่งซื้อสินค้าเข้า'),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _load,
              tooltip: 'รีเฟรช',
              icon: const Icon(Icons.refresh),
            ),
            const Spacer(),
            const Text('บันทึกแล้วสินค้าและจำนวนจะเข้าคลังหลักทันที'),
          ],
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        Expanded(
          child: Card(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _orders.isEmpty
                ? const Center(child: Text('ยังไม่มีใบสั่งซื้อสินค้าเข้า'))
                : SingleChildScrollView(
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('เลขที่เอกสาร')),
                        DataColumn(label: Text('วันที่')),
                        DataColumn(label: Text('หมายเหตุ')),
                        DataColumn(label: Text('มูลค่าต้นทุน')),
                        DataColumn(label: Text('มูลค่าราคาขาย')),
                        DataColumn(label: Text('เปิด')),
                      ],
                      rows: _orders.map((order) {
                        final id = order['id']?.toString() ?? '';
                        return DataRow(
                          cells: [
                            DataCell(Text(id)),
                            DataCell(
                              Text(order['orderDate']?.toString() ?? ''),
                            ),
                            DataCell(Text(order['notes']?.toString() ?? '')),
                            DataCell(Text(_money(order['totalCost']))),
                            DataCell(Text(_money(order['totalSaleValue']))),
                            DataCell(
                              IconButton(
                                tooltip: 'ดูรายละเอียด',
                                icon: const Icon(Icons.visibility_outlined),
                                onPressed: () => _showDetail(id),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _CreatePurchaseOrderDialog extends StatefulWidget {
  const _CreatePurchaseOrderDialog();

  @override
  State<_CreatePurchaseOrderDialog> createState() =>
      _CreatePurchaseOrderDialogState();
}

class _CreatePurchaseOrderDialogState
    extends State<_CreatePurchaseOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _productSearch = TextEditingController();
  final List<_PurchaseLineControllers> _lines = [_PurchaseLineControllers()];
  late DateTime _date;
  late final String _requestId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    _requestId = 'PO-WEB-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _productSearch.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _selectProduct(Map<String, dynamic> product) {
    final code = product['code']?.toString().trim() ?? '';
    if (code.isEmpty) return;
    final existing = _lines.where((line) => line.code.text.trim() == code);
    setState(() {
      if (existing.isNotEmpty) {
        final line = existing.first;
        line.qty.text = '${(int.tryParse(line.qty.text) ?? 0) + 1}';
        return;
      }
      final blank = _lines.where((line) => line.isBlank);
      final target = blank.isNotEmpty
          ? blank.first
          : (_lines..add(_PurchaseLineControllers())).last;
      target.fillFromProduct(product);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final token = context.read<AuthProvider>().token ?? '';
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiOperationsService.createPurchaseOrder(
        token: token,
        requestId: _requestId,
        orderDate: _dateText(_date),
        notes: '',
        items: _lines.map((line) => line.payload).toList(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1260, maxHeight: 820),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'สร้างใบสั่งซื้อสินค้าเข้า',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _date,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() => _date = picked);
                              }
                            },
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text('วันที่ ${_dateText(_date)}'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PurchaseOrderProductPicker(
                        controller: _productSearch,
                        onSelected: _selectProduct,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'รายการสินค้า',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const _PurchaseLineHeader(),
                        for (var index = 0; index < _lines.length; index++)
                          _PurchaseLineRow(
                            key: ValueKey(_lines[index]),
                            line: _lines[index],
                            lineNumber: index + 1,
                            canDelete: _lines.length > 1,
                            onDelete: () => setState(
                              () => _lines.removeAt(index).dispose(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => setState(
                              () => _lines.add(_PurchaseLineControllers()),
                            ),
                      icon: const Icon(Icons.add),
                      label: const Text('เพิ่มรายการ'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('ยกเลิก'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('บันทึกและรับเข้าคลังหลัก'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PurchaseLineHeader extends StatelessWidget {
  const _PurchaseLineHeader();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Row(
      children: [
        SizedBox(width: 32, child: Text('#')),
        Expanded(flex: 2, child: Text('รหัส (ว่าง=อัตโนมัติ)')),
        SizedBox(width: 8),
        Expanded(flex: 3, child: Text('ชื่อสินค้า')),
        SizedBox(width: 8),
        Expanded(flex: 2, child: Text('Barcode')),
        SizedBox(width: 8),
        Expanded(child: Text('จำนวน')),
        SizedBox(width: 8),
        Expanded(child: Text('ต้นทุน')),
        SizedBox(width: 8),
        Expanded(child: Text('ราคาขาย')),
        SizedBox(width: 8),
        Expanded(child: Text('ราคาต่ำสุด')),
        SizedBox(width: 48),
      ],
    ),
  );
}

class _PurchaseLineRow extends StatelessWidget {
  const _PurchaseLineRow({
    super.key,
    required this.line,
    required this.lineNumber,
    required this.canDelete,
    required this.onDelete,
  });
  final _PurchaseLineControllers line;
  final int lineNumber;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    InputDecoration input(String hint) => InputDecoration(
      hintText: hint,
      border: const OutlineInputBorder(),
      isDense: true,
    );
    String? requiredText(String? value) =>
        value == null || value.trim().isEmpty ? 'จำเป็น' : null;
    String? positive(String? value) =>
        (double.tryParse(value ?? '') ?? 0) <= 0 ? '> 0' : null;
    String? nonNegative(String? value) =>
        (double.tryParse(value ?? '') ?? -1) < 0 ? '≥ 0' : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('$lineNumber'),
            ),
          ),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: line.code,
              decoration: input('P0801'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: line.name,
              decoration: input('ชื่อสินค้า'),
              validator: requiredText,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: line.barcode,
              decoration: input('ว่าง=ใช้รหัส'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: line.qty,
              decoration: input('1'),
              keyboardType: TextInputType.number,
              validator: positive,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: line.cost,
              decoration: input('0.00'),
              keyboardType: TextInputType.number,
              validator: nonNegative,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: line.price,
              decoration: input('0.00'),
              keyboardType: TextInputType.number,
              validator: nonNegative,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: line.minPrice,
              decoration: input('0.00'),
              keyboardType: TextInputType.number,
              validator: (value) {
                final minPrice = double.tryParse(value ?? '');
                final price = double.tryParse(line.price.text);
                if (minPrice == null || minPrice < 0) return '≥ 0';
                if (price != null && minPrice > price) return 'เกินราคาขาย';
                return null;
              },
            ),
          ),
          SizedBox(
            width: 48,
            child: IconButton(
              onPressed: canDelete ? onDelete : null,
              icon: const Icon(Icons.delete_outline),
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseLineControllers {
  final code = TextEditingController();
  final name = TextEditingController();
  final barcode = TextEditingController();
  final qty = TextEditingController(text: '1');
  final cost = TextEditingController(text: '0');
  final price = TextEditingController(text: '0');
  final minPrice = TextEditingController(text: '0');
  bool get isBlank =>
      code.text.trim().isEmpty &&
      name.text.trim().isEmpty &&
      barcode.text.trim().isEmpty;

  void fillFromProduct(Map<String, dynamic> product) {
    code.text = product['code']?.toString() ?? '';
    name.text = (product['nameTh'] ?? product['name'] ?? '').toString();
    barcode.text = product['barCode']?.toString() ?? '';
    qty.text = '1';
    cost.text = _purchaseDecimalText(product['cost']);
    price.text = _purchaseDecimalText(product['price']);
    minPrice.text = _purchaseDecimalText(product['minPrice']);
  }

  Map<String, dynamic> get payload => {
    'partCode': code.text.trim(),
    'partName': name.text.trim(),
    'barCode': barcode.text.trim(),
    'qty': int.tryParse(qty.text) ?? 0,
    'cost': double.tryParse(cost.text) ?? -1,
    'price': double.tryParse(price.text) ?? -1,
    'minPrice': double.tryParse(minPrice.text) ?? -1,
  };
  void dispose() {
    code.dispose();
    name.dispose();
    barcode.dispose();
    qty.dispose();
    cost.dispose();
    price.dispose();
    minPrice.dispose();
  }
}

String _purchaseDecimalText(dynamic value) {
  final number = double.tryParse(value?.toString() ?? '') ?? 0;
  return number.toStringAsFixed(2);
}

typedef PurchaseOrderProductLoader =
    Future<({List<Map<String, dynamic>> parts, int total})> Function(
      String query,
      int limit,
      int offset,
    );

/// Searchable catalog picker for existing products in an inbound purchase
/// order. Archived products remain selectable so receiving stock can reactivate
/// them through the existing purchase-order transaction.
class PurchaseOrderProductPicker extends StatefulWidget {
  const PurchaseOrderProductPicker({
    super.key,
    required this.controller,
    required this.onSelected,
    this.loadPage,
  });

  final TextEditingController controller;
  final ValueChanged<Map<String, dynamic>> onSelected;
  final PurchaseOrderProductLoader? loadPage;

  @override
  State<PurchaseOrderProductPicker> createState() =>
      _PurchaseOrderProductPickerState();
}

class _PurchaseOrderProductPickerState
    extends State<PurchaseOrderProductPicker> {
  static const _pageSize = 50;
  final MenuController _menuController = MenuController();
  Timer? _debounce;
  List<Map<String, dynamic>> _items = [];
  String _loadedQuery = '';
  int _total = 0;
  bool _loading = false;
  String? _loadError;
  int _requestGeneration = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({required bool reset, bool openMenu = false}) async {
    final query = widget.controller.text.trim();
    final generation = ++_requestGeneration;
    final token = widget.loadPage == null
        ? context.read<AuthProvider>().token ?? ''
        : '';
    if (widget.loadPage == null && token.isEmpty) return;
    setState(() {
      _loading = true;
      _loadError = null;
      if (reset) {
        _items = [];
        _total = 0;
      }
    });
    try {
      final offset = reset ? 0 : _items.length;
      final result = widget.loadPage != null
          ? await widget.loadPage!(query, _pageSize, offset)
          : await ApiService.searchPartsPaged(
              token: token,
              query: query,
              crossBranch: true,
              limit: _pageSize,
              offset: offset,
            );
      if (!mounted ||
          generation != _requestGeneration ||
          query != widget.controller.text.trim()) {
        return;
      }
      setState(() {
        _loadedQuery = query;
        _items = reset ? result.parts : [..._items, ...result.parts];
        _total = result.total;
      });
    } catch (error) {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loadError = error.toString());
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
        if (openMenu && !_menuController.isOpen) _menuController.open();
      }
    }
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _load(reset: true, openMenu: true),
    );
  }

  Future<void> _toggleMenu() async {
    if (_menuController.isOpen) {
      _menuController.close();
      return;
    }
    if (_loadedQuery != widget.controller.text.trim() || _items.isEmpty) {
      await _load(reset: true);
    }
    if (mounted && !_menuController.isOpen) _menuController.open();
  }

  void _select(Map<String, dynamic> item) {
    widget.onSelected(item);
    widget.controller.clear();
    _loadedQuery = '';
    _menuController.close();
  }

  Future<void> _loadMore() async {
    if (_loading || _items.length >= _total) return;
    await _load(reset: false);
  }

  bool _handleScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 80 &&
        !_loading &&
        _items.length < _total) {
      _loadMore();
    }
    return false;
  }

  String _label(Map<String, dynamic> item) {
    final code = item['code']?.toString() ?? '';
    final name = (item['nameTh'] ?? item['name'] ?? '').toString();
    final barcode = item['barCode']?.toString() ?? '';
    final inactive = item['isActive'] == false ? ' • ปิดใช้งาน' : '';
    return '${[code, name, barcode].where((value) => value.isNotEmpty).join(' - ')}$inactive';
  }

  Widget _menuContent() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_loadError != null && _items.isEmpty) {
      return Center(
        child: TextButton(
          onPressed: () => _load(reset: true, openMenu: true),
          child: const Text('โหลดไม่สำเร็จ — กดเพื่อลองใหม่'),
        ),
      );
    }
    if (_items.isEmpty) return const Center(child: Text('ไม่พบสินค้า'));

    final hasFooter = _loading || _items.length < _total || _loadError != null;
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScroll,
      child: ListView.separated(
        primary: false,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _items.length + (hasFooter ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            if (_loadError != null) {
              return TextButton(
                onPressed: _loadMore,
                child: const Text('โหลดต่อไม่สำเร็จ — กดเพื่อลองใหม่'),
              );
            }
            return const SizedBox(
              height: 48,
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final item = _items[index];
          return InkWell(
            onTap: () => _select(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                _label(item),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => MenuAnchor(
        controller: _menuController,
        crossAxisUnconstrained: false,
        style: MenuStyle(
          minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
          maximumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 360)),
        ),
        menuChildren: [
          SizedBox(
            width: constraints.maxWidth,
            height: 320,
            child: _menuContent(),
          ),
        ],
        builder: (context, controller, child) => TextField(
          key: const Key('purchase-order-product-search'),
          controller: widget.controller,
          decoration: InputDecoration(
            labelText: 'สแกน/ค้นหาสินค้า',
            hintText: 'ชื่อสินค้า, รหัสสินค้า หรือ Barcode',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              key: const Key('purchase-order-product-dropdown'),
              tooltip: 'ดูรายการสินค้า',
              onPressed: _toggleMenu,
              icon: Icon(
                controller.isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              ),
            ),
          ),
          onChanged: _onChanged,
          onTap: () {
            if (_items.isEmpty) _load(reset: true, openMenu: true);
          },
        ),
      ),
    );
  }
}

class _PurchaseOrderDetail extends StatelessWidget {
  const _PurchaseOrderDetail({required this.order});
  final Map<String, dynamic> order;
  @override
  Widget build(BuildContext context) {
    final items = (order['items'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    return AlertDialog(
      title: Text('ใบสั่งซื้อสินค้าเข้า ${order['id'] ?? ''}'),
      content: SizedBox(
        width: 980,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'วันที่ ${order['orderDate'] ?? ''}   หมายเหตุ ${order['notes'] ?? '-'}',
              ),
              const SizedBox(height: 12),
              DataTable(
                columns: const [
                  DataColumn(label: Text('รหัส')),
                  DataColumn(label: Text('ชื่อ')),
                  DataColumn(label: Text('จำนวน')),
                  DataColumn(label: Text('ต้นทุน')),
                  DataColumn(label: Text('ราคาขาย')),
                  DataColumn(label: Text('ราคาต่ำสุด')),
                ],
                rows: items
                    .map(
                      (item) => DataRow(
                        cells: [
                          DataCell(Text(item['partCode']?.toString() ?? '')),
                          DataCell(Text(item['partName']?.toString() ?? '')),
                          DataCell(Text(item['qty']?.toString() ?? '')),
                          DataCell(Text(_money(item['cost']))),
                          DataCell(Text(_money(item['price']))),
                          DataCell(Text(_money(item['minPrice']))),
                        ],
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'รวมต้นทุน ${_money(order['totalCost'])}   มูลค่าราคาขาย ${_money(order['totalSaleValue'])}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ปิด'),
        ),
      ],
    );
  }
}

String _dateText(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _money(dynamic value) =>
    '฿${(double.tryParse(value?.toString() ?? '') ?? 0).toStringAsFixed(2)}';
