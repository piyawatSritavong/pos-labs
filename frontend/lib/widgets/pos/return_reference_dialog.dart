import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/bill_provider.dart';
import 'package:frontend/services/api_bills.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/pos_mirror_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class ReturnReferenceDialog extends StatefulWidget {
  const ReturnReferenceDialog({super.key});

  @override
  State<ReturnReferenceDialog> createState() => _ReturnReferenceDialogState();
}

class _ReturnReferenceDialogState extends State<ReturnReferenceDialog> {
  final TextEditingController _invoiceController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _referenceBill;
  List<Map<String, dynamic>> _details = [];
  final Map<String, int> _selectedQtyByKey = {};

  // Stage 1 (bill picker): today's completed bills, browsable like the
  // "ประวัติบิลวันนี้" dialog. Each row has a "คืนของในบิลนี้" button.
  bool _isLoadingBills = false;
  String? _billsError;
  List<Map<String, dynamic>> _todayBills = [];

  @override
  void initState() {
    super.initState();
    _loadTodayBills();
  }

  @override
  void dispose() {
    _invoiceController.dispose();
    PosMirrorService.current?.notifyDialogState(null);
    super.dispose();
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '-';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  bool _isToday(DateTime? dt) {
    if (dt == null) return false;
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  // Load today's completed bills so the cashier can pick one to return against
  // without typing its id (the search box still finds any bill in the DB).
  Future<void> _loadTodayBills() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) {
      setState(() {
        _billsError = 'หมดเซสชัน กรุณาเข้าสู่ระบบใหม่';
        _todayBills = [];
      });
      return;
    }
    setState(() {
      _isLoadingBills = true;
      _billsError = null;
    });
    try {
      final bills = await ApiBillsService.getBills(
        token: token,
        limit: 200,
        offset: 0,
        statuses: const ['completed'],
        includeDetails: true,
        scope: 'pos',
      );
      final filtered =
          bills.whereType<Map<String, dynamic>>().where((bill) {
            return _isToday(_parseDate(bill['createdAt']?.toString()));
          }).toList()..sort((a, b) {
            final aTime = _parseDate(a['createdAt']?.toString());
            final bTime = _parseDate(b['createdAt']?.toString());
            return (bTime ?? DateTime(0)).compareTo(aTime ?? DateTime(0));
          });
      if (!mounted) return;
      setState(() => _todayBills = filtered);
    } catch (e) {
      if (!mounted) return;
      setState(() => _billsError = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoadingBills = false);
      }
    }
  }

  void _backToList() {
    setState(() {
      _referenceBill = null;
      _details = [];
      _selectedQtyByKey.clear();
      _error = null;
    });
    _broadcastState();
  }

  void _broadcastState() {
    final bill = _referenceBill;
    PosMirrorService.current?.notifyDialogState({
      'type': 'return',
      'stage': bill == null ? 'search' : 'selecting',
      'invoiceId': _invoiceController.text.trim(),
      if (bill != null) 'bill': {
        'id': bill['id']?.toString() ?? '',
        'total': bill['totalAmount'] ?? 0,
      },
      'items': _details.map((detail) {
        final key = _rowKey(detail);
        return {
          'partCode': detail['partCode']?.toString() ?? '',
          'partName': detail['name']?.toString() ?? detail['partCode']?.toString() ?? '',
          'originalQty': _toDouble(detail['originalQty'] ?? detail['qty']).toInt(),
          'alreadyReturned': _toDouble(detail['returnedQty']).toInt(),
          'maxReturnable': _toDouble(detail['remainingQty'] ?? detail['returnableQty'] ?? detail['qty']).toInt(),
          'selectedQty': _selectedQtyByKey[key] ?? 0,
        };
      }).toList(),
    });
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String _rowKey(Map<String, dynamic> detail) {
    final partCode = detail['partCode']?.toString() ?? '';
    final addressCode = detail['addressCode']?.toString() ?? '';
    return '$partCode|$addressCode';
  }

  // Search box: look up a bill by exact id anywhere in the database (any date
  // in this branch), then jump to the item-selection stage.
  Future<void> _searchReferenceBill() async {
    final billId = _invoiceController.text.trim();
    if (billId.isEmpty) {
      setState(() {
        _error = 'กรุณากรอกเลขที่บิล';
      });
      return;
    }
    await _loadReturnableBill(billId);
  }

  // Load a specific bill's returnable items and switch to the selection stage.
  // Used by both the search box and each "คืนของในบิลนี้" button in the list.
  Future<void> _loadReturnableBill(String billId) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) {
      setState(() {
        _error = 'หมดเซสชัน กรุณาเข้าสู่ระบบใหม่';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _referenceBill = null;
      _details = [];
      _selectedQtyByKey.clear();
    });

    try {
      final bill = await ApiService.getReturnReferenceBill(
        token: token,
        billId: billId,
      );
      final status = (bill['status']?.toString() ?? '').toLowerCase();
      if (status != 'completed') {
        setState(() {
          _error = 'บิลนี้ยังไม่จบการขาย (status: ${bill['status'] ?? '-'})';
        });
        return;
      }

      final rawDetails = bill['details'];
      if (rawDetails is! List) {
        setState(() {
          _error = 'ไม่พบรายการสินค้าในบิล';
        });
        return;
      }

      final mapped = rawDetails.whereType<Map<String, dynamic>>().toList();
      if (mapped.isEmpty) {
        setState(() {
          _error = 'ไม่พบรายการสินค้าในบิล';
        });
        return;
      }

      final returnable = mapped
          .where(
            (detail) =>
                _toDouble(
                  detail['remainingQty'] ?? detail['returnableQty'] ?? 0,
                ).toInt() >
                0,
          )
          .toList();
      if (returnable.isEmpty) {
        setState(() {
          _error = 'บิลนี้ถูกคืนครบแล้ว หรือไม่มีรายการที่ยังคืนได้';
        });
        return;
      }

      setState(() {
        _referenceBill = bill;
        _details = returnable;
      });
      _broadcastState();
    } catch (e) {
      setState(() {
        _error = 'ไม่พบบิลหรือดึงข้อมูลไม่สำเร็จ: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _applyReturnSelection() async {
    if (_referenceBill == null) {
      return;
    }

    final selected = _selectedQtyByKey.entries
        .where((e) => e.value > 0)
        .toList();
    if (selected.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยังไม่ได้เลือกรายการที่จะคืน')),
      );
      return;
    }

    final billProvider = context.read<BillProvider>();
    billProvider.startReturnSession(referenceBill: _referenceBill!);

    for (final detail in _details) {
      final key = _rowKey(detail);
      final qty = _selectedQtyByKey[key] ?? 0;
      if (qty > 0) {
        billProvider.setReturnLineFromDetail(detail: detail, qty: qty);
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'คืนของ (อ้างอิงบิลเดิม)',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'เลือกบิลจากรายการวันนี้ หรือค้นหาเลขที่บิลย้อนหลังทั้งหมด แล้วกด '
                '“คืนของในบิลนี้” เพื่อเลือกรายการคืน',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _invoiceController,
                      decoration: const InputDecoration(
                        labelText: 'ค้นหาเลขที่บิล (ย้อนหลังทั้งหมด)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onSubmitted: (_) => _searchReferenceBill(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _searchReferenceBill,
                      icon: const Icon(Icons.search),
                      label: const Text('ค้นหาบิล'),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 16),
              if (_isLoading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_referenceBill == null)
                Expanded(child: _buildBillsList())
              else
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'เลือกบิลใหม่',
                              onPressed: _isLoading ? null : _backToList,
                              icon: const Icon(Icons.arrow_back),
                            ),
                            Expanded(
                              child: Text(
                                'บิลอ้างอิง: ${_referenceBill!['id'] ?? '-'}'
                                '  •  รวม ${_referenceBill!['totalAmount'] ?? '0.00'}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.separated(
                          itemCount: _details.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final detail = _details[index];
                            final name =
                                detail['name']?.toString() ??
                                detail['nameTh']?.toString() ??
                                detail['partCode']?.toString() ??
                                'สินค้า';
                            final code = detail['partCode']?.toString() ?? '-';
                            final originalQty = _toDouble(
                              detail['originalQty'] ?? detail['qty'],
                            ).toInt();
                            final returnedQty = _toDouble(
                              detail['returnedQty'],
                            ).toInt();
                            final maxQty = _toDouble(
                              detail['remainingQty'] ??
                                  detail['returnableQty'] ??
                                  detail['qty'],
                            ).toInt();
                            final key = _rowKey(detail);
                            final selectedQty = _selectedQtyByKey[key] ?? 0;
                            final unitPrice = _toDouble(detail['price']);
                            final lineCredit = unitPrice * selectedQty;

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$code • ซื้อ $originalQty ชิ้น • คืนแล้ว $returnedQty • เหลือคืนได้ $maxQty • ฿${unitPrice.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            color: AppColors.muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: selectedQty <= 0
                                        ? null
                                        : () {
                                            setState(() {
                                              _selectedQtyByKey[key] =
                                                  selectedQty - 1;
                                            });
                                            _broadcastState();
                                          },
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 36,
                                    child: Text(
                                      '$selectedQty',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: selectedQty >= maxQty
                                        ? null
                                        : () {
                                            setState(() {
                                              _selectedQtyByKey[key] =
                                                  selectedQty + 1;
                                            });
                                            _broadcastState();
                                          },
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: Text(
                                      '- ฿${lineCredit.toStringAsFixed(2)}',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        color: AppColors.danger,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('ปิด'),
                  ),
                  const Spacer(),
                  // Confirm only makes sense once a bill is selected (stage 2).
                  if (_referenceBill != null)
                    ElevatedButton.icon(
                      onPressed: _applyReturnSelection,
                      icon: const Icon(Icons.assignment_return),
                      label: const Text('ยืนยันรายการคืน'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBillsList() {
    if (_isLoadingBills) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_billsError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 40),
            const SizedBox(height: 8),
            Text(
              _billsError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.danger),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _loadTodayBills,
              child: const Text('ลองใหม่'),
            ),
          ],
        ),
      );
    }
    if (_todayBills.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 56, color: AppColors.muted),
            SizedBox(height: 8),
            Text(
              'วันนี้ยังไม่มีบิล — ค้นหาเลขที่บิลย้อนหลังได้ด้านบน',
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'บิลวันนี้',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'รีเฟรช',
              onPressed: _isLoadingBills ? null : _loadTodayBills,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: _todayBills.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _buildBillCard(_todayBills[index]),
          ),
        ),
      ],
    );
  }

  double _resolveAmount(Map<String, dynamic> bill, List<String> keys) {
    for (final key in keys) {
      final v = bill[key];
      if (v != null) return _toDouble(v);
    }
    return 0.0;
  }

  Widget _buildBillCard(Map<String, dynamic> bill) {
    final id = bill['id']?.toString() ?? bill['billId']?.toString() ?? '-';
    final created = _parseDate(bill['createdAt']?.toString());
    final total = _resolveAmount(bill, [
      'totalAmount',
      'total_amount',
      'total',
    ]);
    final raw = bill['details'] ?? bill['items'];
    final itemCount = (bill['itemCount'] as num?)?.toInt() ??
        (raw is List ? raw.length : 0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg,
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
                  id,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'เวลา ${_formatTime(created)} • $itemCount รายการ • '
                  'รวม ฿${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : () => _loadReturnableBill(id),
            icon: const Icon(Icons.assignment_return),
            label: const Text('คืนของในบิลนี้'),
          ),
        ],
      ),
    );
  }
}
