import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_operations.dart';
import 'package:frontend/theme/app_theme.dart';
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
                      child: TextField(
                        controller: _scanController,
                        decoration: const InputDecoration(
                          labelText: 'สแกน/ค้นหาสินค้า',
                          hintText: 'รหัสสินค้า, barcode, ชื่อสินค้า',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.qr_code_scanner),
                        ),
                        onSubmitted: (_) => _addFromInput(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _addFromInput,
                      child: const Text('เพิ่ม'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Autocomplete<Map<String, dynamic>>(
                  displayStringForOption: _partLabel,
                  // Server-side search (no full-catalog preload). Min 2 chars to
                  // avoid noisy queries; Autocomplete uses the latest result.
                  optionsBuilder: (value) async {
                    final q = value.text.trim();
                    if (q.length < 2) {
                      return const Iterable<Map<String, dynamic>>.empty();
                    }
                    final token = context.read<AuthProvider>().token ?? '';
                    if (token.isEmpty) {
                      return const Iterable<Map<String, dynamic>>.empty();
                    }
                    try {
                      return await ApiOperationsService.searchRestockCatalog(
                        token: token,
                        query: q,
                        limit: 20,
                      );
                    } catch (_) {
                      return const Iterable<Map<String, dynamic>>.empty();
                    }
                  },
                  onSelected: _addPart,
                  fieldViewBuilder: (context, controller, focusNode, _) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'ค้นหาจากรายการสินค้า',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                    );
                  },
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
                      onMinus: () {
                        setState(() {
                          if (line.qty > 1) {
                            line.qty--;
                          } else {
                            _lines.removeAt(index);
                          }
                        });
                      },
                      onPlus: line.qty >= line.availableQty
                          ? null
                          : () => setState(() => line.qty++),
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

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.onMinus,
    required this.onPlus,
    required this.onDelete,
  });

  final _RestockLine line;
  final VoidCallback onMinus;
  final VoidCallback? onPlus;
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
          IconButton(onPressed: onMinus, icon: const Icon(Icons.remove)),
          SizedBox(
            width: 44,
            child: Text(
              '${line.qty}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(onPressed: onPlus, icon: const Icon(Icons.add)),
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
