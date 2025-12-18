import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
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
      final bills = await ApiService.getBills(token: token, limit: 200, offset: 0);
      final filtered = bills.whereType<Map<String, dynamic>>().where((bill) {
        final status = (bill['status']?.toString().toLowerCase() ?? '');
        if (status == 'hold') return false;
        final created = _parseDate(bill['createdAt']?.toString());
        return _isToday(created);
      }).toList()
        ..sort((a, b) {
          final aTime = _parseDate(a['createdAt']?.toString());
          final bTime = _parseDate(b['createdAt']?.toString());
          return (bTime ?? DateTime(0)).compareTo(aTime ?? DateTime(0));
        });
      setState(() => _todayBills = filtered);
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
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 580),
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
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final bill = _todayBills[index];
                                    final id = bill['id']?.toString() ??
                                        bill['billId']?.toString() ??
                                        '-';
                                    final status =
                                        (bill['status']?.toString() ?? '')
                                            .toUpperCase();
                                    final created =
                                        _parseDate(bill['createdAt']?.toString());
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
                                    final total = _resolveAmount(bill, [
                                      'totalAmount',
                                      'total_amount',
                                      'total',
                                    ]);
                                    final items = bill['details'] is List
                                        ? (bill['details'] as List).length
                                        : bill['items'] is List
                                            ? (bill['items'] as List).length
                                            : 0;

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
                                                id,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
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
                                                      BorderRadius.circular(12),
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
                                                value: '$items ชิ้น',
                                              ),
                                              const SizedBox(width: 12),
                                              _Detail(
                                                label: 'ก่อนลด',
                                                value:
                                                    '฿${subtotal.toStringAsFixed(2)}',
                                              ),
                                              const SizedBox(width: 12),
                                              _Detail(
                                                label: 'ส่วนลด',
                                                value:
                                                    '-฿${discount.toStringAsFixed(2)}',
                                                accent: true,
                                              ),
                                              const SizedBox(width: 12),
                                              _Detail(
                                                label: 'รวมสุทธิ',
                                                value:
                                                    '฿${total.toStringAsFixed(2)}',
                                                bold: true,
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
