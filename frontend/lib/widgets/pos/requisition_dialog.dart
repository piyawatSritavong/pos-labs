import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_operations.dart';
import 'package:frontend/services/api_service.dart';
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 700),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.request_page_outlined,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'คำขอเบิกสินค้า',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
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
                Tab(text: 'คำขอของฉัน'),
                Tab(text: 'สร้างคำขอใหม่'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [_MyRequisitionsTab(), _CreateRequisitionTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Tab 1: My Requisitions
// ============================================================

class _MyRequisitionsTab extends StatefulWidget {
  const _MyRequisitionsTab();

  @override
  State<_MyRequisitionsTab> createState() => _MyRequisitionsTabState();
}

class _MyRequisitionsTabState extends State<_MyRequisitionsTab> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _transfers = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token ?? '';
    final branchId = auth.branchId ?? '';
    if (token.isEmpty) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final list = await ApiOperationsService.getTransfers(
        token: token,
        toBranchId: branchId,
        limit: 50,
      );
      if (!mounted) return;
      setState(() => _transfers = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'requested':
        return Colors.deepOrange;
      case 'pending':
        return Colors.amber.shade700;
      case 'approved':
        return Colors.blue;
      case 'dispatched':
        return Colors.purple;
      case 'received':
        return Colors.green;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'requested':
        return 'รอรับเรื่อง';
      case 'pending':
        return 'รออนุมัติ';
      case 'approved':
        return 'อนุมัติแล้ว';
      case 'dispatched':
        return 'จัดส่งแล้ว';
      case 'received':
        return 'รับแล้ว';
      case 'cancelled':
        return 'ยกเลิก';
      default:
        return status;
    }
  }

  Future<void> _cancel(String id) async {
    final token = context.read<AuthProvider>().token ?? '';
    try {
      await ApiOperationsService.cancelTransfer(token: token, id: id);
      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ยกเลิกไม่สำเร็จ: $e')));
    }
  }

  Future<void> _receive(Map<String, dynamic> transfer) async {
    final token = context.read<AuthProvider>().token ?? '';
    final id = transfer['id']?.toString() ?? '';
    final rawItems = (transfer['items'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    // Build receive items list — confirm all dispatched quantities
    final receiveItems = rawItems
        .map(
          (item) => {
            'partCode': item['partCode']?.toString() ?? '',
            'receivedQty': item['dispatchedQty'] ?? item['qty'] ?? 0,
          },
        )
        .toList();
    try {
      await ApiOperationsService.receiveTransfer(
        token: token,
        id: id,
        items: receiveItems,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('รับสินค้าสำเร็จ')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('รับสินค้าไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 48, color: AppColors.muted),
            const SizedBox(height: 8),
            const Text(
              'ยังไม่มีคำขอ',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('รีเฟรช'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _transfers.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final t = _transfers[i];
          final id = t['id']?.toString() ?? '';
          final status = t['status']?.toString() ?? '';
          final notes = t['notes']?.toString() ?? '';
          final createdAt = (t['createdAt']?.toString() ?? '').length >= 10
              ? t['createdAt'].toString().substring(0, 10)
              : t['createdAt']?.toString() ?? '';
          final items = (t['items'] as List? ?? [])
              .cast<Map<String, dynamic>>();

          return Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'คำขอ #${id.length > 8 ? id.substring(0, 8) : id}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _statusColor(status).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          _statusLabel(status),
                          style: TextStyle(
                            color: _statusColor(status),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
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
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...items.map((item) {
                      final code = item['partCode']?.toString() ?? '';
                      final qty = item['qty']?.toString() ?? '0';
                      return Text(
                        '• $code  ×$qty',
                        style: const TextStyle(fontSize: 13),
                      );
                    }),
                  ],
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'หมายเหตุ: $notes',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  // Action buttons
                  if (status == 'requested') ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton(
                        onPressed: () => _cancel(id),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                        ),
                        child: const Text('ยกเลิกคำขอ'),
                      ),
                    ),
                  ],
                  if (status == 'dispatched') ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: () => _receive(t),
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('ยืนยันรับสินค้า'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// Tab 2: Create Requisition
// ============================================================

class _CreateRequisitionTab extends StatefulWidget {
  const _CreateRequisitionTab();

  @override
  State<_CreateRequisitionTab> createState() => _CreateRequisitionTabState();
}

class _CreateRequisitionTabState extends State<_CreateRequisitionTab> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  bool _isLoadingData = true;
  bool _isSubmitting = false;
  String? _error;

  List<Map<String, dynamic>> _parts = [];
  // Source branches = all branches excluding own branch
  List<Map<String, dynamic>> _sourceBranches = [];
  String? _selectedFromBranchId; // auto-selected, from _sourceBranches

  final List<_ItemRow> _itemRows = [];

  @override
  void initState() {
    super.initState();
    _itemRows.add(_ItemRow());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (final row in _itemRows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token ?? '';
    final myBranchId = auth.branchId ?? '';
    if (token.isEmpty) return;
    setState(() {
      _isLoadingData = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.getBranches(token: token, limit: 50),
        ApiService.getParts(token: token, limit: 500),
      ]);
      if (!mounted) return;
      final allBranches = results[0];
      final sources = allBranches
          .where((b) => (b['branchId']?.toString() ?? '') != myBranchId)
          .toList();
      setState(() {
        _parts = results[1];
        _sourceBranches = sources;
        _selectedFromBranchId = sources.isNotEmpty
            ? sources.first['branchId']?.toString()
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  String get _ownBranchDisplay {
    return context.read<AuthProvider>().branchId ?? '';
  }

  void _addRow() {
    setState(() => _itemRows.add(_ItemRow()));
  }

  void _removeRow(int index) {
    setState(() {
      _itemRows[index].dispose();
      _itemRows.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedFromBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบสาขาต้นทางที่ใช้เบิกสินค้าได้')),
      );
      return;
    }
    final validRows = _itemRows
        .where((r) => r.selectedPart != null && r.qty > 0)
        .toList();
    if (validRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาเพิ่มรายการสินค้าอย่างน้อย 1 รายการ'),
        ),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final token = auth.token ?? '';
    final toBranchId = auth.branchId ?? '';

    setState(() => _isSubmitting = true);
    try {
      await ApiOperationsService.createTransfer(
        token: token,
        fromBranchId: _selectedFromBranchId!,
        toBranchId: toBranchId,
        notes: _notesController.text.trim(),
        items: validRows
            .map(
              (r) => {
                'partCode': r.selectedPart!['code']?.toString() ?? '',
                'requestedQty': r.qty,
              },
            )
            .toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ส่งคำขอเบิกสินค้าสำเร็จ')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ส่งคำขอไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadData, child: const Text('ลองใหม่')),
          ],
        ),
      );
    }

    final auth = context.read<AuthProvider>();
    final myUsername = (auth.username?.trim().isNotEmpty == true)
        ? auth.username!
        : (auth.name ?? '');

    // No other branches to request from
    if (_sourceBranches.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.store_mall_directory_outlined,
              size: 48,
              color: AppColors.muted,
            ),
            const SizedBox(height: 12),
            const Text(
              'ไม่พบสาขาที่สามารถเบิกสินค้าได้',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('รีเฟรช'),
            ),
          ],
        ),
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'ต้นทาง (รถของฉัน)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Text(
                      myUsername,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'ปลายทาง (สาขาของฉัน)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Text(
                      _ownBranchDisplay,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'หมายเหตุ (ไม่บังคับ)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        'รายการสินค้า',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _addRow,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('เพิ่มรายการ'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._itemRows.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final row = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Autocomplete<Map<String, dynamic>>(
                              displayStringForOption: (p) =>
                                  '${p['code'] ?? ''} — ${p['nameTh'] ?? p['name'] ?? ''}',
                              optionsBuilder: (textEditingValue) {
                                final q = textEditingValue.text.toLowerCase();
                                if (q.isEmpty) return const [];
                                return _parts
                                    .where((p) {
                                      final code = (p['code'] ?? '')
                                          .toString()
                                          .toLowerCase();
                                      final name =
                                          (p['nameTh'] ?? p['name'] ?? '')
                                              .toString()
                                              .toLowerCase();
                                      return code.contains(q) ||
                                          name.contains(q);
                                    })
                                    .take(20);
                              },
                              onSelected: (p) {
                                setState(() => row.selectedPart = p);
                              },
                              fieldViewBuilder:
                                  (context, ctrl, focusNode, onFieldSubmitted) {
                                    if (row.selectedPart != null &&
                                        ctrl.text.isEmpty) {
                                      ctrl.text =
                                          '${row.selectedPart!['code'] ?? ''} — ${row.selectedPart!['nameTh'] ?? row.selectedPart!['name'] ?? ''}';
                                    }
                                    return TextFormField(
                                      controller: ctrl,
                                      focusNode: focusNode,
                                      decoration: const InputDecoration(
                                        labelText: 'Part Code',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      onChanged: (_) {
                                        setState(() => row.selectedPart = null);
                                      },
                                      validator: (_) => row.selectedPart == null
                                          ? 'เลือกสินค้า'
                                          : null,
                                    );
                                  },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 120,
                            child: TextFormField(
                              initialValue: row.qty > 0 ? '${row.qty}' : '',
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'จำนวน',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (v) {
                                row.qty = int.tryParse(v) ?? 0;
                              },
                              validator: (v) {
                                final n = int.tryParse(v ?? '');
                                if (n == null || n <= 0) return 'ระบุจำนวน';
                                return null;
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: AppColors.danger,
                            ),
                            onPressed: _itemRows.length > 1
                                ? () => _removeRow(idx)
                                : null,
                            tooltip: 'ลบรายการ',
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('ยกเลิก'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('ส่งคำขอเบิกสินค้า'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow {
  Map<String, dynamic>? selectedPart;
  int qty = 1;

  void dispose() {}
}
