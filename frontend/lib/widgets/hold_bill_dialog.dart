import 'package:flutter/material.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/bill_provider.dart';

class HoldBillDialog extends StatefulWidget {
  const HoldBillDialog({super.key});

  @override
  State<HoldBillDialog> createState() => _HoldBillDialogState();
}

class _HoldBillDialogState extends State<HoldBillDialog> {
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _heldBills = [];

  @override
  void initState() {
    super.initState();
    _loadHeldBills();
  }

  Future<void> _loadHeldBills() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;

    if (token == null) {
      setState(() {
        _error = 'token หาย กรุณา login ใหม่';
        _heldBills = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final bills = await ApiService.getBills(
        token: token,
        limit: 100,
        offset: 0,
      );

      final held = bills
          .where(
            (b) => (b['status']?.toString().toLowerCase() ?? '') == 'hold',
          )
          .cast<Map<String, dynamic>>()
          .toList();

      // เรียงจากแก้ไขล่าสุด -> เก่าสุด ถ้ามี updatedAt / createdAt
      held.sort((a, b) {
        final aTime = a['updatedAt'] ?? a['createdAt'];
        final bTime = b['updatedAt'] ?? b['createdAt'];
        return bTime.toString().compareTo(aTime.toString());
      });

      setState(() {
        _heldBills = held;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _billDisplayId(Map<String, dynamic> bill) {
    return bill['id']?.toString() ??
        bill['billId']?.toString() ??
        '(ไม่พบเลขที่บิล)';
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  double _resolveAmount(Map<String, dynamic> bill, List<String> keys) {
    for (final key in keys) {
      final value = bill[key];
      if (value != null) {
        return _toDouble(value);
      }
    }
    return 0.0;
  }

  Future<void> _resumeBill(Map<String, dynamic> bill) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final billProvider = Provider.of<BillProvider>(context, listen: false);
    final token = auth.token;

    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
      );
      return;
    }

    final targetId =
        bill['id']?.toString() ?? bill['billId']?.toString() ?? '';

    if (targetId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบเลขที่บิลสำหรับ resume')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // เรียก /bills/switch พร้อม targetBillId
      await billProvider.switchBill(token: token, targetBillId: targetId);

      if (!mounted) return;

      // ส่ง true กลับให้ caller รู้ว่ามีการ resume บิลแล้ว
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เรียกบิลกลับมาทำต่อไม่สำเร็จ: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _cancelBill(Map<String, dynamic> bill) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;

    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
      );
      return;
    }

    final billId =
        bill['id']?.toString() ?? bill['billId']?.toString() ?? '';

    if (billId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบเลขที่บิลสำหรับยกเลิก')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบบิล'),
        content: Text('ต้องการลบบิลเลขที่ ${_billDisplayId(bill)} หรือไม่ ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // ต้องมี endpoint /bills/:id/cancel ที่ backend
      await ApiService.cancelBill(token: token, billId: billId);
      await _loadHeldBills(); // reload list หลังลบ
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ลบบิลไม่สำเร็จ: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.radius),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.soft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'บิลที่ถูกพักไว้',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'รีเฟรช',
                    onPressed: _isLoading ? null : _loadHeldBills,
                    icon: const Icon(Icons.refresh),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'ปิด',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? _ErrorState(
                              message: _error!,
                              onRetry: _loadHeldBills,
                            )
                          : _heldBills.isEmpty
                              ? const _EmptyState()
                              : ListView.separated(
                                  itemCount: _heldBills.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final bill = _heldBills[index];
                                    final id = _billDisplayId(bill);
                                    final subtotal = _resolveAmount(bill, [
                                      'purchaseAmount',
                                      'purchase_amount',
                                      'subtotal',
                                    ]);
                                    final total = _resolveAmount(bill, [
                                      'totalAmount',
                                      'total_amount',
                                      'total',
                                    ]);
                                    final discount = _resolveAmount(bill, [
                                      'totalDiscount',
                                      'total_discount',
                                      'discount',
                                    ]);
                                    final createdAt =
                                        bill['createdAt']?.toString() ?? '';
                                    final List<dynamic> itemsCount =
                                        bill['details'] is List
                                            ? bill['details'] as List
                                            : bill['items'] is List
                                                ? bill['items'] as List
                                                : const [];

                                    return Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: AppColors.bg,
                                        borderRadius: BorderRadius.circular(
                                            AppSizes.radius),
                                        border:
                                            Border.all(color: AppColors.border),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                'บิล $id',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const Spacer(),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.primary
                                                      .withValues(alpha: 0.08),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: const Text(
                                                  'HOLD',
                                                  style: TextStyle(
                                                    color: AppColors.primary,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'สร้างเมื่อ: $createdAt',
                                            style: const TextStyle(
                                              color: AppColors.muted,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              _SummaryChip(
                                                label: 'จำนวนสินค้า',
                                                value:
                                                    '${itemsCount.length} ชิ้น',
                                              ),
                                              const SizedBox(width: 8),
                                              _SummaryChip(
                                                label: 'ยอดก่อนลด',
                                                value:
                                                    '฿${subtotal.toStringAsFixed(2)}',
                                              ),
                                              const SizedBox(width: 8),
                                              _SummaryChip(
                                                label: 'ส่วนลด',
                                                value:
                                                    '-฿${discount.toStringAsFixed(2)}',
                                                isAccent: true,
                                              ),
                                              const SizedBox(width: 8),
                                              _SummaryChip(
                                                label: 'รวม',
                                                value:
                                                    '฿${total.toStringAsFixed(2)}',
                                                isBold: true,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              OutlinedButton(
                                                onPressed: () =>
                                                    _cancelBill(bill),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      AppColors.danger,
                                                  side: const BorderSide(
                                                    color: AppColors.danger,
                                                  ),
                                                ),
                                                child: const Text('ลบบิล'),
                                              ),
                                              const SizedBox(width: 8),
                                              ElevatedButton(
                                                onPressed: () =>
                                                    _resumeBill(bill),
                                                child:
                                                    const Text('กลับมาทำต่อ'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    this.isAccent = false,
    this.isBold = false,
  });

  final String label;
  final String value;
  final bool isAccent;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isAccent ? AppColors.accent : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
              color: isAccent ? AppColors.accent : AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.pause_circle_outline,
              size: 64, color: AppColors.muted),
          SizedBox(height: 12),
          Text('ยังไม่มีบิลที่ถูกพักไว้'),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 48),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.danger),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('ลองใหม่'),
          ),
        ],
      ),
    );
  }
}
