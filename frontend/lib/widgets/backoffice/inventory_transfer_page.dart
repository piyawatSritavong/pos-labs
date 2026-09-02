import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_operations.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class InventoryTransferPage extends StatefulWidget {
  const InventoryTransferPage({super.key});

  @override
  State<InventoryTransferPage> createState() => _InventoryTransferPageState();
}

class _InventoryTransferPageState extends State<InventoryTransferPage> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _transfers = [];
  Map<String, dynamic>? _selectedTransfer;
  List<Map<String, dynamic>> _branches = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    await Future.wait([_loadTransfers(), _loadBranches()]);
  }

  Future<void> _loadBranches() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    try {
      final branches = await ApiService.getBranches(token: token);
      if (mounted) setState(() => _branches = branches);
    } catch (_) {}
  }

  Future<void> _loadTransfers() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) {
      setState(() {
        _error = 'ไม่พบ token กรุณา login ใหม่';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final transfers = await ApiOperationsService.getTransfers(
        token: token,
        limit: 50,
      );
      if (mounted) {
        setState(() {
          _transfers = transfers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadTransferDetail(String id) async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    try {
      final detail = await ApiOperationsService.getTransfer(
        token: token,
        id: id,
      );
      if (mounted) setState(() => _selectedTransfer = detail);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ดึงรายละเอียดไม่สำเร็จ: $e')));
      }
    }
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'requested':
        return Colors.deepOrange;
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.blue;
      case 'dispatched':
        return Colors.purple;
      case 'received':
        return Colors.green;
      case 'cancelled':
        return AppColors.muted;
      default:
        return AppColors.muted;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'requested':
        return 'คำขอเบิก';
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

  Future<void> _openCreateDialog() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _CreateTransferDialog(
        branches: _branches,
        token: token,
        authBranchId: auth.branchId ?? '',
        isSuperAdmin: auth.isSuperAdmin,
      ),
    );
    await _loadTransfers();
  }

  Future<void> _acknowledge(String id) async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    try {
      await ApiOperationsService.acknowledgeTransfer(token: token, id: id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('รับเรื่องแล้ว — รอการอนุมัติ')),
        );
        await _loadTransfers();
        await _loadTransferDetail(id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('รับเรื่องไม่สำเร็จ: $e')));
      }
    }
  }

  Future<void> _approve(String id) async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    try {
      await ApiOperationsService.approveTransfer(token: token, id: id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('อนุมัติแล้ว')));
        await _loadTransfers();
        await _loadTransferDetail(id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('อนุมัติไม่สำเร็จ: $e')));
      }
    }
  }

  Future<void> _cancel(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยกเลิก Transfer'),
        content: const Text('ต้องการยกเลิก transfer นี้หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ไม่'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('ยกเลิก Transfer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    try {
      await ApiOperationsService.cancelTransfer(token: token, id: id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ยกเลิกแล้ว')));
        setState(() => _selectedTransfer = null);
        await _loadTransfers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ยกเลิกไม่สำเร็จ: $e')));
      }
    }
  }

  Future<void> _openDispatchDialog(
    String id,
    List<Map<String, dynamic>> items,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _DispatchDialog(transferId: id, items: items),
    );
    await _loadTransfers();
    await _loadTransferDetail(id);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left panel
        SizedBox(
          width: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'ใบโอนสินค้า',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'รีเฟรช',
                    onPressed: _isLoading ? null : _loadTransfers,
                    icon: const Icon(Icons.refresh),
                  ),
                  ElevatedButton.icon(
                    onPressed: _openCreateDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('สร้าง'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              style: const TextStyle(color: AppColors.danger),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: _loadTransfers,
                              child: const Text('ลองใหม่'),
                            ),
                          ],
                        ),
                      )
                    : _transfers.isEmpty
                    ? const Center(child: Text('ยังไม่มีรายการโอนสินค้า'))
                    : ListView.separated(
                        itemCount: _transfers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, i) {
                          final t = _transfers[i];
                          final id = t['id']?.toString() ?? '-';
                          final status = t['status']?.toString() ?? '';
                          final from = t['fromBranchId']?.toString() ?? '-';
                          final to = t['toBranchId']?.toString() ?? '-';
                          final rawItems = t['items'];
                          final itemCount = rawItems is List
                              ? rawItems.length
                              : 0;
                          final isSelected =
                              _selectedTransfer?['id']?.toString() == id;

                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _loadTransferDetail(id),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.08)
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary.withValues(alpha: 0.4)
                                      : AppColors.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '#$id',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          '$from → $to  •  $itemCount รายการ',
                                          style: const TextStyle(
                                            color: AppColors.muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _statusColor(
                                        status,
                                      ).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: _statusColor(
                                          status,
                                        ).withValues(alpha: 0.4),
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
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        // Right panel - detail
        Expanded(
          child: _selectedTransfer == null
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_shipping_outlined,
                        size: 56,
                        color: AppColors.muted,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'เลือก Transfer เพื่อดูรายละเอียด',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                )
              : _buildDetail(_selectedTransfer!),
        ),
      ],
    );
  }

  Widget _buildDetail(Map<String, dynamic> transfer) {
    final id = transfer['id']?.toString() ?? '-';
    final status = transfer['status']?.toString() ?? '';
    final from = transfer['fromBranchId']?.toString() ?? '-';
    final to = transfer['toBranchId']?.toString() ?? '-';
    final notes = transfer['notes']?.toString() ?? '';
    final createdAt = transfer['createdAt']?.toString() ?? '';
    final rawItems = transfer['items'];
    final items = rawItems is List
        ? rawItems.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Transfer #$id',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
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
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                // Action buttons
                if (status == 'requested') ...[
                  OutlinedButton(
                    onPressed: () => _cancel(id),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                    ),
                    child: const Text('ปฏิเสธ'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _acknowledge(id),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('รับเรื่อง'),
                  ),
                ],
                if (status == 'pending') ...[
                  OutlinedButton(
                    onPressed: () => _cancel(id),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                    ),
                    child: const Text('ยกเลิก'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _approve(id),
                    child: const Text('อนุมัติ'),
                  ),
                ],
                if (status == 'approved') ...[
                  OutlinedButton(
                    onPressed: () => _cancel(id),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                    ),
                    child: const Text('ยกเลิก'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _openDispatchDialog(id, items),
                    child: const Text('จัดส่ง'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _InfoChip('จาก', from),
                _InfoChip('ไปยัง', to),
                if (createdAt.isNotEmpty) _InfoChip('วันที่', createdAt),
                if (notes.isNotEmpty) _InfoChip('หมายเหตุ', notes),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'รายการสินค้า',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('ไม่มีรายการสินค้า'))
                  : SingleChildScrollView(
                      child: DataTable(
                        columnSpacing: 16,
                        columns: const [
                          DataColumn(label: Text('รหัสสินค้า')),
                          DataColumn(label: Text('ชื่อ')),
                          DataColumn(label: Text('ขอโอน'), numeric: true),
                          DataColumn(label: Text('ส่ง'), numeric: true),
                          DataColumn(label: Text('รับ'), numeric: true),
                        ],
                        rows: items.map((item) {
                          final code = item['partCode']?.toString() ?? '-';
                          final name =
                              item['partNameTh']?.toString() ??
                              item['partName']?.toString() ??
                              '-';
                          final req = _toDouble(
                            item['requestedQty'] ?? item['requested_qty'],
                          );
                          final dis = _toDouble(
                            item['dispatchedQty'] ?? item['dispatched_qty'],
                          );
                          final rec = _toDouble(
                            item['receivedQty'] ?? item['received_qty'],
                          );
                          return DataRow(
                            cells: [
                              DataCell(Text(code)),
                              DataCell(Text(name)),
                              DataCell(
                                Text(
                                  req.toStringAsFixed(
                                    req.truncateToDouble() == req ? 0 : 2,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  dis.toStringAsFixed(
                                    dis.truncateToDouble() == dis ? 0 : 2,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  rec.toStringAsFixed(
                                    rec.truncateToDouble() == rec ? 0 : 2,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────
// Create Transfer Dialog
// ──────────────────────────────────────────────────────
class _CreateTransferDialog extends StatefulWidget {
  const _CreateTransferDialog({
    required this.branches,
    required this.token,
    required this.authBranchId,
    required this.isSuperAdmin,
  });
  final List<Map<String, dynamic>> branches;
  final String token;
  final String authBranchId;
  final bool isSuperAdmin;

  @override
  State<_CreateTransferDialog> createState() => _CreateTransferDialogState();
}

class _VanStaffDestinationOption {
  const _VanStaffDestinationOption({
    required this.key,
    required this.branchId,
    required this.label,
  });

  final String key;
  final String branchId;
  final String label;
}

class _CreateTransferDialogState extends State<_CreateTransferDialog> {
  final _notesController = TextEditingController();

  // Source branch (Super Admin can pick; HQ Manager fixed to authBranchId)
  String? _fromBranchId;

  // Destination: selected POS Staff user + branch mapping
  String? _selectedVanStaffOptionKey;

  List<Map<String, dynamic>> _vanStaff = [];
  Map<String, List<String>> _vanStaffBranchIdsByUserId = {};
  bool _isLoadingData = true;

  // Item rows: each entry has 'partCode' (String) and a qty TextEditingController
  final List<Map<String, dynamic>> _itemRows = [];
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fromBranchId = widget.isSuperAdmin ? null : widget.authBranchId;
    _addItem();
    _loadData(branchId: _fromBranchId);
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (final row in _itemRows) {
      (row['qtyCtrl'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  Future<void> _loadData({String? branchId}) async {
    try {
      // Parts are searched server-side in the Autocomplete below, so we no
      // longer preload the whole catalog here.
      final results = await Future.wait<dynamic>([
        ApiService.getUsers(token: widget.token, limit: 200, offset: 0),
      ]);
      final users = (results[0] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      final vanStaff = users
          .where((u) => u['roleId'] == 'role.van_staff')
          .toList();
      final vanStaffBranchIds = <String, List<String>>{};
      final branchMappings = await Future.wait(
        vanStaff.map((u) async {
          final userId = u['id']?.toString() ?? '';
          if (userId.isEmpty) {
            return const MapEntry<String, List<String>>('', <String>[]);
          }
          try {
            final mappings = await ApiService.getUserBranches(
              token: widget.token,
              userId: userId,
            );
            final branchIds =
                mappings
                    .map(
                      (m) =>
                          (m['branchId'] ?? m['branch_id'])?.toString() ?? '',
                    )
                    .where((id) => id.isNotEmpty)
                    .toSet()
                    .toList()
                  ..sort();
            return MapEntry(userId, branchIds);
          } catch (_) {
            return MapEntry(userId, <String>[]);
          }
        }),
      );
      for (final entry in branchMappings) {
        if (entry.key.isNotEmpty) {
          vanStaffBranchIds[entry.key] = entry.value;
        }
      }
      if (!mounted) return;
      setState(() {
        _vanStaff = vanStaff;
        _vanStaffBranchIdsByUserId = vanStaffBranchIds;
        _isLoadingData = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  void _addItem() {
    setState(() {
      _itemRows.add({
        'partCode': '',
        'qtyCtrl': TextEditingController(text: '1'),
      });
    });
  }

  void _removeItem(int index) {
    if (_itemRows.length <= 1) return;
    (_itemRows[index]['qtyCtrl'] as TextEditingController).dispose();
    setState(() => _itemRows.removeAt(index));
  }

  String _branchDisplay(Map<String, dynamic> b) {
    final code = b['branchId']?.toString() ?? b['id']?.toString() ?? '';
    final name =
        b['branchName']?.toString() ?? b['branchNameTh']?.toString() ?? '';
    return code.isNotEmpty && name.isNotEmpty ? '$code - $name' : code;
  }

  String _vanStaffDisplay(Map<String, dynamic> u) {
    final name = u['name']?.toString() ?? '';
    final username = u['username']?.toString() ?? '';
    return name.isNotEmpty ? name : username;
  }

  String _branchLabel(String branchId) {
    for (final branch in widget.branches) {
      final currentBranchId = (branch['branchId'] ?? branch['id'] ?? '')
          .toString();
      if (currentBranchId == branchId) {
        return _branchDisplay(branch);
      }
    }
    return branchId;
  }

  List<_VanStaffDestinationOption> _buildVanStaffDestinationOptions() {
    final options = <_VanStaffDestinationOption>[];
    for (final user in _vanStaff) {
      final userId = user['id']?.toString() ?? '';
      if (userId.isEmpty) continue;
      final resolvedBranchIds = <String>{
        ...?_vanStaffBranchIdsByUserId[userId],
      };
      final fallbackBranchId = (user['branchId'] ?? '').toString();
      if (fallbackBranchId.isNotEmpty) {
        resolvedBranchIds.add(fallbackBranchId);
      }
      final candidateBranchIds =
          resolvedBranchIds.where((branchId) => branchId.isNotEmpty).toList()
            ..sort();
      for (final branchId in candidateBranchIds) {
        options.add(
          _VanStaffDestinationOption(
            key: '$userId::$branchId',
            branchId: branchId,
            label: '${_vanStaffDisplay(user)} (${_branchLabel(branchId)})',
          ),
        );
      }
    }
    return options;
  }

  String _partDisplay(Map<String, dynamic> p) {
    final code = p['partCode']?.toString() ?? p['code']?.toString() ?? '';
    final name = p['nameTh']?.toString() ?? p['nameEn']?.toString() ?? '';
    return name.isNotEmpty ? '$code — $name' : code;
  }

  Future<void> _submit() async {
    final from = _fromBranchId ?? '';
    final destinationOptions = _buildVanStaffDestinationOptions();
    _VanStaffDestinationOption? selectedOption;
    for (final option in destinationOptions) {
      if (option.key == _selectedVanStaffOptionKey) {
        selectedOption = option;
        break;
      }
    }
    final to = selectedOption?.branchId ?? '';
    if (from.isEmpty || to.isEmpty) {
      setState(() => _error = 'กรุณาเลือกสาขาต้นทางและ POS Staff ปลายทาง');
      return;
    }

    final items = <Map<String, dynamic>>[];
    for (final row in _itemRows) {
      final code = (row['partCode'] as String).trim();
      final qty =
          double.tryParse(
            (row['qtyCtrl'] as TextEditingController).text.trim(),
          ) ??
          0;
      if (code.isEmpty) continue;
      items.add({'partCode': code, 'requestedQty': qty});
    }

    if (items.isEmpty) {
      setState(() => _error = 'กรุณาเพิ่มรายการสินค้าอย่างน้อย 1 รายการ');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await ApiOperationsService.createTransfer(
        token: widget.token,
        fromBranchId: from,
        toBranchId: to,
        notes: _notesController.text.trim(),
        items: items,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinationOptions = _buildVanStaffDestinationOptions();
    final selectedDestinationKey =
        destinationOptions.any(
          (option) => option.key == _selectedVanStaffOptionKey,
        )
        ? _selectedVanStaffOptionKey
        : null;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.radius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'สร้างใบโอนสินค้า',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_isLoadingData)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Source branch ──
                        if (widget.isSuperAdmin)
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              'create_transfer_source_${_fromBranchId ?? ''}',
                            ),
                            initialValue: _fromBranchId,
                            decoration: const InputDecoration(
                              labelText: 'สาขาต้นทาง',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: widget.branches
                                .map(
                                  (b) => DropdownMenuItem(
                                    value: (b['branchId'] ?? b['id'] ?? '')
                                        .toString(),
                                    child: Text(_branchDisplay(b)),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              setState(() {
                                _fromBranchId = v;
                                _selectedVanStaffOptionKey = null;
                              });
                              if (v != null) _loadData(branchId: v);
                            },
                          )
                        else
                          InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'สาขาต้นทาง',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            child: Text(
                              widget.authBranchId,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        // ── Destination POS Staff ──
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'create_transfer_destination_${selectedDestinationKey ?? ''}',
                          ),
                          initialValue: selectedDestinationKey,
                          decoration: const InputDecoration(
                            labelText: 'POS Staff ปลายทาง (รถ)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: destinationOptions
                              .map(
                                (option) => DropdownMenuItem(
                                  value: option.key,
                                  child: Text(option.label),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedVanStaffOptionKey = v),
                        ),
                        if (destinationOptions.isEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'ไม่พบ POS Staff ปลายทาง',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextField(
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
                              onPressed: _addItem,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('เพิ่มรายการ'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(_itemRows.length, (i) {
                          final row = _itemRows[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Autocomplete<Map<String, dynamic>>(
                                    initialValue: TextEditingValue(
                                      text: row['partCode'] as String,
                                    ),
                                    // Server-side search (min 2 chars) instead of
                                    // filtering a preloaded catalog in Dart.
                                    optionsBuilder: (textEditingValue) async {
                                      final q = textEditingValue.text.trim();
                                      if (q.length < 2) {
                                        return const Iterable<
                                            Map<String, dynamic>>.empty();
                                      }
                                      try {
                                        // Archived products have no live
                                        // stock row to move, so offering them
                                        // here only reproduces the duplicate
                                        // names the catalog was cleaned of.
                                        return await ApiService.searchParts(
                                          token: widget.token,
                                          query: q,
                                          isActive: true,
                                          limit: 20,
                                        );
                                      } catch (_) {
                                        return const Iterable<
                                            Map<String, dynamic>>.empty();
                                      }
                                    },
                                    displayStringForOption: (p) =>
                                        (p['partCode'] ?? p['code'] ?? '')
                                            .toString(),
                                    fieldViewBuilder:
                                        (
                                          ctx,
                                          fieldController,
                                          fieldFocus,
                                          onFieldSubmitted,
                                        ) {
                                          return TextField(
                                            controller: fieldController,
                                            focusNode: fieldFocus,
                                            decoration: const InputDecoration(
                                              labelText: 'Part Code',
                                              border: OutlineInputBorder(),
                                              isDense: true,
                                            ),
                                          );
                                        },
                                    optionsViewBuilder:
                                        (ctx, onSelected, options) {
                                          return Align(
                                            alignment: Alignment.topLeft,
                                            child: Material(
                                              elevation: 4,
                                              child: SizedBox(
                                                width: 320,
                                                child: ListView.builder(
                                                  padding: EdgeInsets.zero,
                                                  shrinkWrap: true,
                                                  itemCount: options.length,
                                                  itemBuilder: (_, j) {
                                                    final p = options.elementAt(
                                                      j,
                                                    );
                                                    return ListTile(
                                                      dense: true,
                                                      title: Text(
                                                        _partDisplay(p),
                                                      ),
                                                      onTap: () =>
                                                          onSelected(p),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                    onSelected: (p) {
                                      setState(() {
                                        _itemRows[i]['partCode'] =
                                            (p['partCode'] ?? p['code'] ?? '')
                                                .toString();
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 120,
                                  child: TextField(
                                    controller:
                                        row['qtyCtrl'] as TextEditingController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'จำนวน',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _itemRows.length > 1
                                      ? () => _removeItem(i)
                                      : null,
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    color: AppColors.danger,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('ยกเลิก'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _submit,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('สร้างใบโอน'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────
// Dispatch Dialog
// ──────────────────────────────────────────────────────
class _DispatchDialog extends StatefulWidget {
  const _DispatchDialog({required this.transferId, required this.items});
  final String transferId;
  final List<Map<String, dynamic>> items;

  @override
  State<_DispatchDialog> createState() => _DispatchDialogState();
}

class _DispatchDialogState extends State<_DispatchDialog> {
  final Map<String, TextEditingController> _controllers = {};
  bool _isSaving = false;
  String? _error;

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    for (final item in widget.items) {
      final code = item['partCode']?.toString() ?? '';
      final req = _toDouble(item['requestedQty'] ?? item['requested_qty']);
      _controllers[code] = TextEditingController(
        text: req.toStringAsFixed(req.truncateToDouble() == req ? 0 : 2),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final dispatchItems = widget.items.map((item) {
        final code = item['partCode']?.toString() ?? '';
        final qty = double.tryParse(_controllers[code]?.text.trim() ?? '') ?? 0;
        return {'partCode': code, 'dispatchedQty': qty};
      }).toList();

      await ApiOperationsService.dispatchTransfer(
        token: token,
        id: widget.transferId,
        items: dispatchItems,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.radius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'จัดส่งสินค้า',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: widget.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = widget.items[i];
                    final code = item['partCode']?.toString() ?? '';
                    final name =
                        item['partNameTh']?.toString() ??
                        item['partName']?.toString() ??
                        code;
                    final controller = _controllers[code];
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                code,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: controller,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              labelText: 'จำนวน',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('ยกเลิก'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _submit,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('ยืนยันจัดส่ง'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────
// Small helper widgets
// ──────────────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  const _InfoChip(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ],
    );
  }
}
