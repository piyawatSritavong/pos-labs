import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/bill_provider.dart';
import 'package:frontend/services/api_service.dart';
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

  @override
  void dispose() {
    _invoiceController.dispose();
    super.dispose();
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

  Future<void> _searchReferenceBill() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) {
      setState(() {
        _error = 'หมดเซสชัน กรุณาเข้าสู่ระบบใหม่';
      });
      return;
    }

    final billId = _invoiceController.text.trim();
    if (billId.isEmpty) {
      setState(() {
        _error = 'กรุณากรอกเลขที่บิล';
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
      final bill = await ApiService.getBill(token: token, billId: billId);
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

      setState(() {
        _referenceBill = bill;
        _details = mapped;
      });
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
                'สแกน/กรอกเลขที่บิลเดิม แล้วเลือกรายการคืนเพื่อสร้างยอดติดลบในธุรกรรมปัจจุบัน',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _invoiceController,
                      decoration: const InputDecoration(
                        labelText: 'เลขที่บิลเดิม (Invoice ID)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.receipt_long),
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
                const Expanded(
                  child: Center(
                    child: Text(
                      'ยังไม่ได้เลือกบิลอ้างอิง',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
                )
              else
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          'บิลอ้างอิง: ${_referenceBill!['id'] ?? '-'}'
                          '  •  รวม ${_referenceBill!['totalAmount'] ?? '0.00'}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
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
                            final maxQty = _toDouble(detail['qty']).toInt();
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
                                          '$code • ซื้อแล้ว $maxQty ชิ้น • ฿${unitPrice.toStringAsFixed(2)}',
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
                    child: const Text('ยกเลิก'),
                  ),
                  const Spacer(),
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
}
