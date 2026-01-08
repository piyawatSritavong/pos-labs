import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/bill_provider.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class CartSummarySection extends StatefulWidget {
  const CartSummarySection({super.key});

  @override
  State<CartSummarySection> createState() => _CartSummarySectionState();
}

class _CartSummarySectionState extends State<CartSummarySection> {
  final TextEditingController _discountController = TextEditingController();
  bool _isPercentMode = true; // true = %, false = บาท
  double _discountAmount = 0.0;
  PaymentMethod? _selectedMethod;
  bool _qrPaymentVerified = false;

  @override
  void dispose() {
    _discountController.dispose();
    super.dispose();
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  List<_BillLineItem> _mapItems(List<Map<String, dynamic>> rawItems) {
    return rawItems.map((item) {
      final qtyRaw = _toDouble(
        item['qty'] ?? item['quantity'] ?? item['amount'],
      );
      final qty = qtyRaw <= 0 ? 1 : qtyRaw.toInt();
      final price = _toDouble(
        item['unitPrice'] ?? item['price'] ?? item['unit_price'],
      );
      final total = _toDouble(item['amount'] ?? item['total'] ?? price * qty);
      final resolvedPrice = price > 0 ? price : (qty > 0 ? total / qty : total);
      final partCode = item['partCode']?.toString() ?? item['code']?.toString();
      final addressCode =
          item['addressCode']?.toString() ?? item['storeCode']?.toString();

      return _BillLineItem(
        name:
            item['nameTh']?.toString() ??
            item['name']?.toString() ??
            item['description']?.toString() ??
            'สินค้า',
        code: partCode ?? '-',
        qty: qty,
        price: resolvedPrice,
        partCode: partCode,
        addressCode: addressCode,
      );
    }).toList();
  }

  Future<void> _holdBill(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final bill = context.read<BillProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final token = auth.token;
    if (token == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
      );
      return;
    }

    try {
      await bill.switchBill(token: token);
      messenger.showSnackBar(
        const SnackBar(content: Text('พักบิลและสร้างบิลใหม่แล้ว')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('พักบิลไม่สำเร็จ: $e')));
    }
  }

  Future<void> _clearBill(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final bill = context.read<BillProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final token = auth.token;
    if (token == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
      );
      return;
    }

    await bill.clearBill(token: token);
    messenger.showSnackBar(const SnackBar(content: Text('ล้างตะกร้าแล้ว')));
  }

  void _applyQuickDiscount(double percent, double subtotal) {
    setState(() {
      _isPercentMode = true;
      _discountController.text = percent.toStringAsFixed(0);
      _discountAmount = subtotal * (percent / 100.0);
      _qrPaymentVerified = false;
    });
  }

  void _recalculateDiscount(double subtotal) {
    final raw = _discountController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _discountAmount = 0.0;
      });
      return;
    }

    final parsed = double.tryParse(raw.replaceAll(',', ''));
    if (parsed == null) {
      return;
    }

    setState(() {
      if (_isPercentMode) {
        _discountAmount = subtotal * (parsed / 100.0);
      } else {
        _discountAmount = parsed;
      }
      _qrPaymentVerified = false;
    });
  }

  bool get _canConfirmPayment {
    return _selectedMethod == PaymentMethod.cash ||
        (_selectedMethod == PaymentMethod.qr && _qrPaymentVerified);
  }

  Future<void> _handleSelectPayment(PaymentMethod method) async {
    if (!mounted) return;
    if (method == PaymentMethod.cash) {
      setState(() {
        _selectedMethod = PaymentMethod.cash;
        _qrPaymentVerified = false;
      });
      return;
    }

    setState(() {
      _selectedMethod = PaymentMethod.qr;
      _qrPaymentVerified = false;
    });

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _QrPaymentDialog(),
    );
    if (!mounted) return;
    setState(() {
      _qrPaymentVerified = result == true;
    });
  }

  Future<void> _mockSetManualDiscount() async {
    await Future.delayed(const Duration(milliseconds: 350));
  }

  void _resetPaymentState() {
    setState(() {
      _selectedMethod = null;
      _qrPaymentVerified = false;
      _discountAmount = 0.0;
      _isPercentMode = true;
      _discountController.clear();
    });
  }

  Future<void> _handleConfirmPayment(BuildContext context) async {
    final bill = context.read<BillProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
      );
      return;
    }

    // Show payment method dialog first
    final selectedMethod = await showDialog<PaymentMethod>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PaymentMethodDialog(),
    );

    if (selectedMethod == null || !mounted) return;

    setState(() {
      _selectedMethod = selectedMethod;
      _qrPaymentVerified = false;
    });

    // If QR, show QR payment dialog
    if (selectedMethod == PaymentMethod.qr) {
      final qrVerified = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _QrPaymentDialog(),
      );
      if (!mounted) return;
      if (qrVerified != true) {
        return;
      }
      setState(() => _qrPaymentVerified = true);
    }

    if (!mounted) return;

    var usedMock = false;
    try {
      await bill.setManualDiscount(token: token, promotionCode: 'PROMO001');
    } catch (e) {
      usedMock = true;
      await _mockSetManualDiscount();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('API ยังไม่พร้อม: $e'),
          ),
        );
      }
    }

    if (!mounted) return;
    final paid = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const ReceiptDialog(),
    );

    if (paid == true && mounted) {
      _resetPaymentState();
    }

    if (usedMock && mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('แสดงใบเสร็จด้วยข้อมูล mock')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bill = context.watch<BillProvider>();
    final items = _mapItems(bill.items);
    final subtotal = bill.subtotal;
    final taxRate = bill.taxRate;
    final tax = subtotal * taxRate;
    final effectiveDiscount = _discountAmount.clamp(0.0, subtotal);
    final total = subtotal - effectiveDiscount + tax;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ตะกร้าสินค้า',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '${items.length} รายการ',
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDialogSummaryRow(
                    'Subtotal',
                    '฿${subtotal.toStringAsFixed(2)}',
                  ),
                  const SizedBox(height: 8),
                  _buildDialogSummaryRow(
                    'ส่วนลด',
                    '- ฿${effectiveDiscount.toStringAsFixed(2)}',
                  ),
                  const SizedBox(height: 8),
                  _buildDialogSummaryRow(
                    'ภาษี (${(taxRate * 100).toStringAsFixed(0)}%)',
                    '฿${tax.toStringAsFixed(2)}',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: const Text(
                          'ส่วนลด',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final percent in [5, 10, 15, 20])
                            OutlinedButton(
                              onPressed: () => _applyQuickDiscount(
                                percent.toDouble(),
                                subtotal,
                              ),
                              child: Text('$percent'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _discountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'ส่วนลด',
                            hintText: 'เช่น 5 หรือ 100',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => _recalculateDiscount(subtotal),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<bool>(
                        value: _isPercentMode,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _isPercentMode = value;
                          });
                          _recalculateDiscount(subtotal);
                        },
                        items: const [
                          DropdownMenuItem(value: true, child: Text('%')),
                          DropdownMenuItem(value: false, child: Text('บาท')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(AppSizes.radius),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'รวมสุทธิ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '฿${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: (bill.isLoading || total <= 0)
                ? null
                : () => _handleConfirmPayment(context),
            child: Text(
              'ยืนยัน • ${items.length} รายการ • ฿${total.toStringAsFixed(2)}',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: bill.isLoading ? null : () => _holdBill(context),
                  child: const Text('พักบิล'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  onPressed: bill.isLoading ? null : () => _clearBill(context),
                  child: const Text('ล้างบิล'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDialogSummaryRow(
    String label,
    String value, {
    bool isEmphasis = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isEmphasis ? FontWeight.bold : FontWeight.normal,
            fontSize: isEmphasis ? 16 : 14,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isEmphasis ? FontWeight.bold : FontWeight.normal,
            fontSize: isEmphasis ? 16 : 14,
            color: isEmphasis ? AppColors.primary : null,
          ),
        ),
      ],
    );
  }
}

class _QrPaymentDialog extends StatefulWidget {
  const _QrPaymentDialog();

  @override
  State<_QrPaymentDialog> createState() => _QrPaymentDialogState();
}

class _QrPaymentDialogState extends State<_QrPaymentDialog> {
  bool _showSuccess = false;

  Future<void> _handleConfirm() async {
    if (_showSuccess) return;
    setState(() => _showSuccess = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'สแกนเพื่อชำระเงิน',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 440,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        'images/shop_qr.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Text(
                              'กรุณาเพิ่มรูป QR code ที่ assets/images/shop_qr.png',
                              textAlign: TextAlign.center,
                            ),
                          );
                        },
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: _showSuccess ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(color: Colors.black),
                    ),
                    AnimatedScale(
                      scale: _showSuccess ? 1.0 : 0.6,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutBack,
                      child: AnimatedOpacity(
                        opacity: _showSuccess ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 96,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _handleConfirm,
                child: const Text('ชำระเสร็จสิ้น'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('ยกเลิก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BillLineItem {
  _BillLineItem({
    required this.name,
    required this.code,
    required this.qty,
    required this.price,
    this.partCode,
    this.addressCode,
  });

  final String name;
  final String code;
  final int qty;
  final double price;
  final String? partCode;
  final String? addressCode;
}

enum PaymentMethod { cash, qr }

class ReceiptDialog extends StatelessWidget {
  const ReceiptDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final bill = Provider.of<BillProvider>(context, listen: false);

    final subtotal = bill.subtotal;
    final discount = bill.discount;
    final taxRate = bill.taxRate;
    final tax = subtotal * taxRate;
    final total = bill.total;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ใบเสร็จรับเงิน',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _buildReceiptRow('Subtotal', '฿${subtotal.toStringAsFixed(2)}'),
              const SizedBox(height: 4),
              _buildReceiptRow('ส่วนลด', '- ฿${discount.toStringAsFixed(2)}'),
              const SizedBox(height: 4),
              _buildReceiptRow(
                'ภาษี (${(taxRate * 100).toStringAsFixed(0)}%)',
                '฿${tax.toStringAsFixed(2)}',
              ),
              const Divider(height: 16, thickness: 1),
              _buildReceiptRow(
                'รวมสุทธิ',
                '฿${total.toStringAsFixed(2)}',
                isEmphasis: true,
              ),
              const SizedBox(height: 16),
              const Text(
                '*** จำลองการพิมพ์ใบเสร็จ ***\nคุณสามารถเชื่อมต่อกับระบบพิมพ์จริงได้ที่จุดนี้',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  final auth = Provider.of<AuthProvider>(
                    context,
                    listen: false,
                  );
                  final billProvider = bill;
                  final messenger = ScaffoldMessenger.of(context);
                  final token = auth.token;
                  if (token == null) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
                    );
                    return;
                  }

                  try {
                    await billProvider.payCurrentBill(token: token);
                    await billProvider.switchBill(token: token);
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('บันทึกบิลไม่สำเร็จ: $e')),
                    );
                    return;
                  }

                  if (context.mounted) {
                    Navigator.of(context).pop(true);
                  }
                },
                child: const Text('กลับหน้าหลัก'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptRow(
    String label,
    String value, {
    bool isEmphasis = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isEmphasis ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isEmphasis ? FontWeight.bold : FontWeight.normal,
            color: isEmphasis ? const Color(0xFF1F6F5D) : null,
          ),
        ),
      ],
    );
  }
}

class _PaymentMethodDialog extends StatelessWidget {
  const _PaymentMethodDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'วิธีชำระเงิน',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(PaymentMethod.cash),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('เงินสด'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(PaymentMethod.qr),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('QR Code'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('ยกเลิก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
