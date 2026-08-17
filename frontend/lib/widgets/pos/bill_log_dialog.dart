import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/utils/bill_line_format.dart';
import 'package:frontend/services/api_bills.dart';
import 'package:frontend/services/api_operations.dart';
import 'package:frontend/services/pos_mirror_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class BillsLogDialog extends StatefulWidget {
  const BillsLogDialog({super.key});

  @override
  State<BillsLogDialog> createState() => _BillsLogDialogState();
}

class _BillsLogDialogState extends State<BillsLogDialog> {
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _todayBills = [];

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  @override
  void dispose() {
    PosMirrorService.current?.notifyDialogState(null);
    super.dispose();
  }

  void _broadcastState() {
    PosMirrorService.current?.notifyDialogState({
      'type': 'bill_log',
      'bills': _todayBills.map((bill) {
        final details = _extractDetails(bill);
        return {
          'id': bill['id']?.toString() ?? '',
          'total': _resolveAmount(bill, [
            'totalAmount',
            'total_amount',
            'total',
          ]),
          'itemCount': (bill['itemCount'] as num?)?.toInt() ?? details.length,
          'totalQty': _resolveTotalQty(bill, details),
          'createdAt': bill['createdAt']?.toString() ?? '',
        };
      }).toList(),
    });
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

  List<Map<String, dynamic>> _extractDetails(Map<String, dynamic> bill) {
    final raw = bill['details'] ?? bill['items'];
    if (raw is! List) {
      return const [];
    }
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  int _resolveTotalQty(
    Map<String, dynamic> bill,
    List<Map<String, dynamic>> details,
  ) {
    final raw = bill['totalQty'];
    if (raw is num) {
      return raw.toInt();
    }
    return details.fold<int>(
      0,
      (sum, item) => sum + _toDouble(item['qty']).toInt(),
    );
  }

  Future<void> _loadBills() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null) {
      setState(() {
        _error = 'token หาย กรุณา login ใหม่';
        _todayBills = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Only show the current shift (bills since the last close); fall back to
      // "today" when the shift start can't be determined.
      final shiftStart = await ApiOperationsService.getShiftStart(
        token: token,
        branchId: auth.branchId ?? '',
        posId: auth.posId ?? '',
      );
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
            final created = _parseDate(bill['createdAt']?.toString());
            if (created == null) return false;
            if (shiftStart != null) return !created.isBefore(shiftStart);
            return _isToday(created);
          }).toList()..sort((a, b) {
            final aTime = _parseDate(a['createdAt']?.toString());
            final bTime = _parseDate(b['createdAt']?.toString());
            return (bTime ?? DateTime(0)).compareTo(aTime ?? DateTime(0));
          });
      setState(() => _todayBills = filtered);
      _broadcastState();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 680),
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
                    'ประวัติบิลวันนี้',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'รีเฟรช',
                    onPressed: _isLoading ? null : _loadBills,
                    icon: const Icon(Icons.refresh),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'ปิด',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? _ErrorBanner(message: _error!, onRetry: _loadBills)
                      : _todayBills.isEmpty
                      ? const _EmptyBills()
                      : ListView.separated(
                          itemCount: _todayBills.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final bill = _todayBills[index];
                            final id =
                                bill['id']?.toString() ??
                                bill['billId']?.toString() ??
                                '-';
                            final status = (bill['status']?.toString() ?? '')
                                .toUpperCase();
                            final created = _parseDate(
                              bill['createdAt']?.toString(),
                            );
                            final subtotal = _resolveAmount(bill, [
                              'purchaseAmount',
                              'purchase_amount',
                              'subtotal',
                            ]);
                            final discount = _resolveAmount(bill, [
                              'totalDiscount',
                              'total_discount',
                              'discount',
                            ]);
                            final afterDiscount = (subtotal - discount)
                                .clamp(0.0, double.infinity)
                                .toDouble();
                            final total = _resolveAmount(bill, [
                              'totalAmount',
                              'total_amount',
                              'total',
                            ]);
                            final details = _extractDetails(bill);
                            final itemCount =
                                (bill['itemCount'] as num?)?.toInt() ??
                                details.length;
                            final totalQty = _resolveTotalQty(bill, details);

                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.bg,
                                borderRadius: BorderRadius.circular(
                                  AppSizes.radius,
                                ),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        id,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.08,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          status,
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _formatTime(created),
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      _Detail(
                                        label: 'จำนวนสินค้า',
                                        value: '$itemCount รายการ',
                                      ),
                                      const SizedBox(width: 12),
                                      _Detail(
                                        label: 'จำนวนรวม',
                                        value: '$totalQty ชิ้น',
                                      ),
                                      const SizedBox(width: 12),
                                      _Detail(
                                        label: 'ก่อนลด',
                                        value:
                                            '฿${subtotal.toStringAsFixed(2)}',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      _Detail(
                                        label: 'ส่วนลด',
                                        value:
                                            '-฿${discount.toStringAsFixed(2)}',
                                        accent: true,
                                      ),
                                      const SizedBox(width: 12),
                                      _Detail(
                                        label: 'หลังลด',
                                        value:
                                            '฿${afterDiscount.toStringAsFixed(2)}',
                                      ),
                                      const SizedBox(width: 12),
                                      _Detail(
                                        label: 'รวมสุทธิ',
                                        value: '฿${total.toStringAsFixed(2)}',
                                        bold: true,
                                      ),
                                    ],
                                  ),
                                  if (details.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.border,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'รายการสินค้า',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          ...details.map((detail) {
                                            final name =
                                                detail['partName']
                                                    ?.toString() ??
                                                detail['name']?.toString() ??
                                                detail['partCode']
                                                    ?.toString() ??
                                                '-';
                                            // Show the multiplication, not just
                                            // its answer — the price each is
                                            // what anyone checking the bill
                                            // wants to see.
                                            final amount = billLineTotal(
                                              detail,
                                            );
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 4,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Expanded(child: Text(name)),
                                                  Text(
                                                    billLineQtyPriceLabel(
                                                      detail,
                                                    ),
                                                    style: const TextStyle(
                                                      color: AppColors.muted,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Text(
                                                    '฿${amount.toStringAsFixed(2)}',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                  ],
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

class _Detail extends StatelessWidget {
  const _Detail({
    required this.label,
    required this.value,
    this.bold = false,
    this.accent = false,
  });

  final String label;
  final String value;
  final bool bold;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: accent ? AppColors.accent : AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyBills extends StatelessWidget {
  const _EmptyBills();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.receipt_long, size: 64, color: AppColors.muted),
          SizedBox(height: 12),
          Text('วันนี้ยังไม่มีบิล'),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

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
          OutlinedButton(onPressed: onRetry, child: const Text('ลองใหม่')),
        ],
      ),
    );
  }
}
