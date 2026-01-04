import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_parts.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class StockDialog extends StatefulWidget {
  const StockDialog({super.key});

  @override
  State<StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<StockDialog> {
  bool _isLoading = false;
  String? _error;
  List<_LowStockPart> _lowStock = [];
  static const double _threshold = 10;

  @override
  void initState() {
    super.initState();
    _loadLowStock();
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  List<_LowStockPart> _buildLowStock(List<Map<String, dynamic>> raw) {
    final List<_LowStockPart> result = [];
    for (final part in raw) {
      final addresses = (part['addresses'] as List?) ?? [];
      double total = 0;
      final mappedAddresses = <_AddressStock>[];
      for (final entry in addresses.whereType<Map<String, dynamic>>()) {
        final qty = _toDouble(
          entry['qty'] ??
              entry['quantity'] ??
              entry['qtyOnHand'] ??
              entry['balance'] ??
              entry['stock'],
        );
        total += qty;
        mappedAddresses.add(
          _AddressStock(
            label: entry['labelTh']?.toString() ??
                entry['label']?.toString() ??
                entry['addressName']?.toString() ??
                entry['addressCode']?.toString() ??
                '-',
            qty: qty,
          ),
        );
      }

      if (mappedAddresses.isEmpty) {
        continue;
      }

      if (total <= _threshold) {
        result.add(
          _LowStockPart(
            code: part['code']?.toString() ?? '',
            name: part['nameTh']?.toString() ??
                part['name']?.toString() ??
                'ไม่ทราบชื่อ',
            totalQty: total,
            addresses: mappedAddresses,
          ),
        );
      }
    }
    result.sort((a, b) => a.totalQty.compareTo(b.totalQty));
    return result;
  }

  Future<void> _loadLowStock() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null) {
      setState(() {
        _error = 'token หาย กรุณา login ใหม่';
        _lowStock = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final parts = await ApiPartsService.getParts(token: token, limit: 200, offset: 0);
      final filtered = _buildLowStock(parts);
      setState(() {
        _lowStock = filtered;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
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
                    'สต็อกใกล้หมด',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'ต่ำกว่า $_threshold ชิ้น',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'รีเฟรช',
                    onPressed: _isLoading ? null : _loadLowStock,
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
              const SizedBox(height: 16),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? _ErrorBanner(message: _error!, onRetry: _loadLowStock)
                          : _lowStock.isEmpty
                              ? const _EmptyStock()
                              : ListView.separated(
                                  itemCount: _lowStock.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final part = _lowStock[index];
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
                                                part.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '#${part.code}',
                                                style: const TextStyle(
                                                  color: AppColors.muted,
                                                ),
                                              ),
                                              const Spacer(),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: AppColors.danger
                                                      .withValues(alpha: 0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(999),
                                                ),
                                                child: Text(
                                                  '${part.totalQty.toStringAsFixed(0)} ชิ้น',
                                                  style: const TextStyle(
                                                    color: AppColors.danger,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: part.addresses
                                                .map(
                                                  (address) => Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 12,
                                                      vertical: 6,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.surface,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              999),
                                                      border: Border.all(
                                                        color: AppColors.border,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      '${address.label}: ${address.qty.toStringAsFixed(0)}',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: AppColors.text,
                                                      ),
                                                    ),
                                                  ),
                                                )
                                                .toList(),
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

class _LowStockPart {
  _LowStockPart({
    required this.code,
    required this.name,
    required this.totalQty,
    required this.addresses,
  });

  final String code;
  final String name;
  final double totalQty;
  final List<_AddressStock> addresses;
}

class _AddressStock {
  _AddressStock({required this.label, required this.qty});

  final String label;
  final double qty;
}

class _EmptyStock extends StatelessWidget {
  const _EmptyStock();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.check_circle_outline,
              size: 56, color: AppColors.primary),
          SizedBox(height: 12),
          Text('สต็อกเพียงพอทุกสินค้าแล้ว'),
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
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('ลองใหม่'),
          ),
        ],
      ),
    );
  }
}
