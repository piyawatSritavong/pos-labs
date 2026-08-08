import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_operations.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/qty_stepper.dart';
import 'package:provider/provider.dart';

class RequisitionDialog extends StatefulWidget {
  const RequisitionDialog({super.key});

  @override
  State<RequisitionDialog> createState() => _RequisitionDialogState();
}

class _RequisitionDialogState extends State<RequisitionDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _createKey = GlobalKey<_CreateRestockTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _editDraft(String id) {
    _tabController.animateTo(1);
    _createKey.currentState?.loadDraft(id);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_shipping_outlined,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'เบิกสินค้าเข้ารถ',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'ประวัติใบเบิก'),
                Tab(text: 'สร้างใบเบิก'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _MyRestocksTab(onEditDraft: _editDraft),
                  _CreateRestockTab(key: _createKey),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyRestocksTab extends StatefulWidget {
  const _MyRestocksTab({required this.onEditDraft});

  final ValueChanged<String> onEditDraft;

  @override
  State<_MyRestocksTab> createState() => _MyRestocksTabState();
}

class _MyRestocksTabState extends State<_MyRestocksTab> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _transfers = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().token ?? '';
    if (token.isEmpty) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final list = await ApiOperationsService.getTransfers(
        token: token,
        transferMode: 'pos_restock',
        limit: 80,
      );
      if (mounted) setState(() => _transfers = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cancel(String id) async {
    final token = context.read<AuthProvider>().token ?? '';
    try {
      await ApiOperationsService.cancelTransfer(token: token, id: id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ยกเลิกใบเบิกแล้ว')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ยกเลิกไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('ลองใหม่')),
          ],
        ),
      );
    }
    if (_transfers.isEmpty) {
      return const Center(
        child: Text('ยังไม่มีใบเบิก', style: TextStyle(color: AppColors.muted)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _transfers.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final transfer = _transfers[index];
          final id = transfer['id']?.toString() ?? '';
          final status = transfer['status']?.toString() ?? '';
          final createdAt = _shortDate(transfer['createdAt']);
          final isStale = transfer['isStale'] == true;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        id,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    _StatusBadge(status: status),
                  ],
                ),
                if (createdAt.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    createdAt,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (isStale) ...[
                  const SizedBox(height: 8),
                  Text(
                    transfer['staleReason']?.toString() ?? 'ใบค้าง',
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (status == 'draft' || status == 'review') ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      if (status == 'draft')
                        OutlinedButton.icon(
                          onPressed: () => widget.onEditDraft(id),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('แก้ไข'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => _cancel(id),
                        icon: const Icon(Icons.close, size: 16),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                        ),
                        label: const Text('ยกเลิก'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CreateRestockTab extends StatefulWidget {
  const _CreateRestockTab({super.key});

  @override
  State<_CreateRestockTab> createState() => _CreateRestockTabState();
}

class _CreateRestockTabState extends State<_CreateRestockTab> {
  final _scanController = TextEditingController();
  final _notesController = TextEditingController();
  final List<_RestockLine> _lines = [];
  // Kept for draft enrichment lookups; no longer preloaded with the whole
  // catalog — part search is server-side now (see the Autocomplete below).
  final List<Map<String, dynamic>> _parts = [];
  String? _draftId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scanController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> loadDraft(String id) async {
    final token = context.read<AuthProvider>().token ?? '';
    if (token.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final transfer = await ApiOperationsService.getTransfer(
        token: token,
        id: id,
      );
      final items = (transfer['items'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      _lines
        ..clear()
        ..addAll(
          items.map((item) {
            final code = item['partCode']?.toString() ?? '';
            final part =
                _findCachedPart(code) ??
                {
                  'code': code,
                  'barCode': item['barCode'] ?? '',
                  'nameTh': item['partNameTh'] ?? item['partName'] ?? code,
                  'unit': {'labelTh': item['unit'] ?? ''},
                  'availableQty': item['requestedQty'] ?? 0,
                  'price': item['salePrice'] ?? 0,
                };
            return _RestockLine(part: part, qty: _toInt(item['requestedQty']));
          }),
        );
      _draftId = id;
      _notesController.text = transfer['notes']?.toString() ?? '';
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic>? _findCachedPart(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final part in _parts) {
      final code = part['code']?.toString().toLowerCase() ?? '';
      final barcode = part['barCode']?.toString().toLowerCase() ?? '';
      if (code == q || barcode == q) return part;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _findPart(String query) async {
    final cached = _findCachedPart(query);
    if (cached != null) return cached;
    final token = context.read<AuthProvider>().token ?? '';
    final results = await ApiOperationsService.searchRestockCatalog(
      token: token,
      query: query,
      limit: 20,
    );
    if (results.isEmpty) return null;
    return results.first;
  }

  Future<void> _addFromInput() async {
    final raw = _scanController.text.trim();
    if (raw.isEmpty) return;
    setState(() => _error = null);
    try {
      final part = await _findPart(raw);
      if (part == null) {
        setState(() => _error = 'ไม่พบสินค้า: $raw');
        return;
      }
      _addPart(part);
      _scanController.clear();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _addPart(Map<String, dynamic> part) {
    final code = part['code']?.toString() ?? '';
    if (code.isEmpty) return;
    setState(() {
      final existing = _lines.where((line) => line.code == code).toList();
      if (existing.isNotEmpty) {
        if (existing.first.qty < existing.first.availableQty) {
          existing.first.qty++;
        }
      } else {
        _lines.add(_RestockLine(part: part, qty: 1));
      }
    });
  }

  List<Map<String, dynamic>> _itemsPayload() => _lines
      .where((line) => line.qty > 0 && line.code.isNotEmpty)
      .map((line) => {'partCode': line.code, 'requestedQty': line.qty})
      .toList();

  Future<String?> _saveDraft() async {
    final token = context.read<AuthProvider>().token ?? '';
    final items = _itemsPayload();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_draftId == null) {
        final created = await ApiOperationsService.createPosRestock(
          token: token,
          notes: _notesController.text.trim(),
          items: items,
        );
        _draftId = created['id']?.toString();
      } else {
        await ApiOperationsService.updateTransferItems(
          token: token,
          id: _draftId!,
          items: items,
        );
      }
      return _draftId;
    } catch (e) {
      setState(() => _error = e.toString());
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submit() async {
    if (_itemsPayload().isEmpty) {
      setState(() => _error = 'กรุณาเพิ่มรายการสินค้าอย่างน้อย 1 รายการ');
      return;
    }
    final id = await _saveDraft();
    if (id == null || !mounted) return;
    final token = context.read<AuthProvider>().token ?? '';
    setState(() => _saving = true);
    try {
      await ApiOperationsService.submitTransfer(token: token, id: id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ส่งใบเบิกให้ HQ ตรวจแล้ว')));
      _clear();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelDraft() async {
    final token = context.read<AuthProvider>().token ?? '';
    if (_draftId != null) {
      try {
        await ApiOperationsService.cancelTransfer(token: token, id: _draftId!);
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
        return;
      }
    }
    _clear();
  }

  void _clear() {
    setState(() {
      _draftId = null;
      _lines.clear();
      _scanController.clear();
      _notesController.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_draftId != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Draft: $_draftId',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: RestockCatalogPicker(
                        controller: _scanController,
                        onSubmitted: _addFromInput,
                        onSelected: _addPart,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _addFromInput,
                      child: const Text('เพิ่ม'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'รายการสินค้า (${_lines.length} รายการ / ${_lines.fold<int>(0, (sum, line) => sum + line.qty)} ชิ้น)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_lines.isEmpty)
                  Container(
                    height: 140,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'ยังไม่มีสินค้าในใบเบิก',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  )
                else
                  ..._lines.asMap().entries.map((entry) {
                    final index = entry.key;
                    final line = entry.value;
                    return _LineTile(
                      line: line,
                      onQtyChanged: (qty) => setState(() => line.qty = qty),
                      // Stepping below 1 drops the line, the way it did when
                      // the quantity was not editable.
                      onStepBelowOne: () =>
                          setState(() => _lines.removeAt(index)),
                      onDelete: () => setState(() => _lines.removeAt(index)),
                    );
                  }),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'หมายเหตุ (ไม่บังคับ)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : _cancelDraft,
                child: const Text('Cancel'),
              ),
              OutlinedButton(
                onPressed: _saving ? null : _saveDraft,
                child: const Text('บันทึก Draft'),
              ),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit ให้ HQ ตรวจ'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

typedef RestockCatalogLoader =
    Future<RestockCatalogPage> Function(String query, int limit, int offset);

/// Unified product lookup used by vehicle restock requests. The optional
/// loader keeps the widget independently testable while production uses the
/// authenticated API service.
class RestockCatalogPicker extends StatefulWidget {
  const RestockCatalogPicker({
    super.key,
    required this.controller,
    required this.onSubmitted,
    required this.onSelected,
    this.loadPage,
  });

  final TextEditingController controller;
  final VoidCallback onSubmitted;
  final ValueChanged<Map<String, dynamic>> onSelected;
  final RestockCatalogLoader? loadPage;

  @override
  State<RestockCatalogPicker> createState() => _RestockCatalogPickerState();
}

class _RestockCatalogPickerState extends State<RestockCatalogPicker> {
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
      final page = widget.loadPage != null
          ? await widget.loadPage!(query, _pageSize, offset)
          : await ApiOperationsService.getRestockCatalogPage(
              token: token,
              query: query,
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
        _items = reset ? page.items : [..._items, ...page.items];
        _total = page.total;
      });
    } catch (e) {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loadError = e.toString());
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
        if (openMenu && !_menuController.isOpen) {
          _menuController.open();
        }
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

  bool _handleMenuScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 80 &&
        !_loading &&
        _items.length < _total) {
      _loadMore();
    }
    return false;
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
    if (_items.isEmpty) {
      return const Center(child: Text('ไม่พบสินค้าที่พร้อมเบิก'));
    }

    final hasFooter = _loading || _items.length < _total || _loadError != null;
    return NotificationListener<ScrollNotification>(
      onNotification: _handleMenuScroll,
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
                child: SizedBox(
                  width: 18,
                  height: 18,
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
                _partLabel(item),
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
          key: const Key('restock-unified-search'),
          controller: widget.controller,
          decoration: InputDecoration(
            labelText: 'สแกน/ค้นหาสินค้า',
            hintText: 'ชื่อสินค้า, รหัสสินค้า หรือ Barcode',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.qr_code_scanner),
            suffixIcon: IconButton(
              key: const Key('restock-catalog-dropdown'),
              tooltip: 'ดูรายการสินค้าที่พร้อมเบิก',
              onPressed: _toggleMenu,
              icon: Icon(
                controller.isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              ),
            ),
          ),
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onTap: () {
            if (_items.isEmpty) _load(reset: true, openMenu: true);
          },
          onSubmitted: (_) => widget.onSubmitted(),
        ),
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.onQtyChanged,
    required this.onStepBelowOne,
    required this.onDelete,
  });

  final _RestockLine line;
  final ValueChanged<int> onQtyChanged;
  final VoidCallback onStepBelowOne;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${line.code}${line.barcode.isNotEmpty ? ' / ${line.barcode}' : ''}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  'พร้อมเบิก ${line.availableQty} ${line.unit} • ราคาขาย ฿${line.price.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          QtyStepper(
            // Keyed by product so reusing the tile for a different line resets
            // the field instead of carrying the previous number over.
            key: ValueKey('restock-qty-${line.code}'),
            value: line.qty,
            min: 1,
            max: line.availableQty,
            onChanged: onQtyChanged,
            onDecrementBelowMin: onStepBelowOne,
          ),
          IconButton(
            onPressed: onDelete,
            color: AppColors.danger,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'draft' => Colors.blueGrey,
      'review' => Colors.deepOrange,
      'approved' => Colors.blue,
      'completed' => Colors.green,
      'cancelled' => Colors.grey,
      _ => Colors.grey,
    };
    final label = switch (status) {
      'draft' => 'Draft',
      'review' => 'รอ HQ ตรวจ',
      'approved' => 'Approved',
      'completed' => 'Completed',
      'cancelled' => 'Cancelled',
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _RestockLine {
  _RestockLine({required this.part, required this.qty});

  final Map<String, dynamic> part;
  int qty;

  String get code => part['code']?.toString() ?? '';
  String get barcode => part['barCode']?.toString() ?? '';
  String get name =>
      (part['nameTh'] ?? part['name'] ?? part['partNameTh'] ?? code).toString();
  int get availableQty => _toInt(part['availableQty']);
  double get price => double.tryParse(part['price']?.toString() ?? '') ?? 0;
  String get unit {
    final raw = part['unit'];
    if (raw is Map) return (raw['labelTh'] ?? raw['label'] ?? '').toString();
    return raw?.toString() ?? 'ชิ้น';
  }
}

String _partLabel(Map<String, dynamic> part) {
  final code = part['code']?.toString() ?? '';
  final barcode = part['barCode']?.toString() ?? '';
  final name = (part['nameTh'] ?? part['name'] ?? '').toString();
  final available = _toInt(part['availableQty']);
  final price = double.tryParse(part['price']?.toString() ?? '') ?? 0;
  return '${[code, name, barcode].where((v) => v.isNotEmpty).join(' - ')} • พร้อมเบิก $available • ฿${price.toStringAsFixed(2)}';
}

String _shortDate(dynamic value) {
  final text = value?.toString() ?? '';
  return text.length >= 10 ? text.substring(0, 10) : text;
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
