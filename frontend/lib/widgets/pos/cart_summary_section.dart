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

  void _applyQuickDiscount(
    BuildContext context,
    double percent,
    double subtotal,
  ) {
    final bill = context.read<BillProvider>();
    setState(() {
      _isPercentMode = true;
      _discountController.text = percent.toStringAsFixed(0);
      _discountAmount = subtotal * (percent / 100.0);
    });
    bill.applyLocalDiscount(discountAmount: _discountAmount);
  }

  void _recalculateDiscount(BuildContext context, double subtotal) {
    final bill = context.read<BillProvider>();
    final raw = _discountController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _discountAmount = 0.0;
      });
      bill.applyLocalDiscount(discountAmount: 0.0);
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
    });
    bill.applyLocalDiscount(discountAmount: _discountAmount);
  }

  Future<void> _mockSetManualDiscount() async {
    await Future.delayed(const Duration(milliseconds: 350));
  }

  void _resetPaymentState() {
    setState(() {
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

    final total = bill.total;

    // Show payment method dialog first
    final selectedMethod = await showDialog<PaymentMethod>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PaymentMethodDialog(),
    );

    if (selectedMethod == null || !mounted) return;

    // If QR, show QR payment dialog
    if (selectedMethod == PaymentMethod.qr) {
      // แจ้งให้ฝั่ง CustomerScreen แสดงหน้าสแกน QR
      bill.setAwaitingQrPayment(true);

      if (!mounted) return;

      // ยืนยันจากพนักงานว่าลูกค้าจ่ายเงินผ่าน QR ครบแล้ว
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('ลูกค้าชำระเงินเรียบร้อย'),
          content: Text(
            'ลูกค้าชำระเงินผ่าน QR Code ตามยอด ฿${total.toStringAsFixed(2)} เรียบร้อยแล้วหรือไม่?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ไม่ใช่'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ใช่'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (confirmed != true) {
        // ยกเลิกการชำระเงินผ่าน QR ปิดสถานะรอชำระที่ฝั่งลูกค้า
        bill.setAwaitingQrPayment(false);
        return;
      }

      // ลูกค้าชำระเงินผ่าน QR เรียบร้อย ปิด popup ที่ฝั่งลูกค้า
      bill.setAwaitingQrPayment(false);
    } else if (selectedMethod == PaymentMethod.cash) {
      // แจ้งฝั่ง CustomerScreen ให้แสดง popup ชำระเงินสด
      bill.setAwaitingCashPayment(value: true, amount: total);

      if (!mounted) return;

      // ยืนยันจากพนักงานโดยกรอกจำนวนเงินที่ลูกค้าชำระ และแสดงเงินทอนแบบเรียลไทม์
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _CashConfirmDialog(total: total),
      );

      if (!mounted) return;

      if (confirmed != true) {
        // ยกเลิกการชำระเงินสด ปิดสถานะรอชำระเงินที่ฝั่งลูกค้า
        bill.setAwaitingCashPayment(value: false);
        return;
      }

      // ลูกค้าชำระเงินสดเรียบร้อย ปิด popup ที่ฝั่งลูกค้า
      bill.setAwaitingCashPayment(value: false);
    }

    if (!mounted) return;

    var usedMock = false;
    try {
      await bill.setManualDiscount(token: token, promotionCode: 'PROMO001');
    } catch (e) {
      usedMock = true;
      await _mockSetManualDiscount();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('API ยังไม่พร้อม: $e')));
      }
    }

    if (!mounted) return;
    bill.setShowThankYouOverlay(true);
    final paid = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const ReceiptDialog(),
    );

    if (paid == true && mounted) {
      _resetPaymentState();
    }

    if (mounted) {
      bill.setShowThankYouOverlay(false);
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
    final tax = bill.tax;
    final effectiveDiscount = bill.discount;
    final total = bill.total;

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
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      'ยังไม่มีสินค้าในตะกร้า',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    itemBuilder: (context, index) {
                      final it = items[index];
                      final lineTotal = (it.price * it.qty).toStringAsFixed(2);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    it.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    it.code,
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '${it.qty}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: Text(
                                '฿$lineTotal',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Divider(height: 1, color: AppColors.border.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Column(
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
                            context,
                            percent.toDouble(),
                            subtotal,
                          ),
                          child: Text('$percent'),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
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
                      onChanged: (_) => _recalculateDiscount(context, subtotal),
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
                      _recalculateDiscount(context, subtotal);
                    },
                    items: const [
                      DropdownMenuItem(value: true, child: Text('%')),
                      DropdownMenuItem(value: false, child: Text('บาท')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
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
          const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final auth = Provider.of<AuthProvider>(
                    context,
                    listen: false,
                  );
                  final userName = auth.name ?? 'Admin';
                  final now = DateTime.now();
                  final dateTimeStr =
                      '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'พนักงาน: $userName',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'วันที่: $dateTimeStr',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              if (bill.items.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: Text(
                        'สินค้า',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        'จำนวน',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'ราคา',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: bill.items.map<Widget>((raw) {
                    double _toDouble(dynamic v) {
                      if (v == null) return 0.0;
                      if (v is num) return v.toDouble();
                      return double.tryParse(v.toString()) ?? 0.0;
                    }

                    final qtyRaw = _toDouble(
                      raw['qty'] ?? raw['quantity'] ?? raw['amount'],
                    );
                    final qty = qtyRaw <= 0 ? 1 : qtyRaw.toInt();
                    final price = _toDouble(
                      raw['unitPrice'] ?? raw['price'] ?? raw['unit_price'],
                    );
                    final total = _toDouble(
                      raw['amount'] ?? raw['total'] ?? price * qty,
                    );
                    final resolvedPrice = price > 0
                        ? price
                        : (qty > 0 ? total / qty : total);
                    final name =
                        raw['nameTh']?.toString() ??
                        raw['name']?.toString() ??
                        raw['description']?.toString() ??
                        'สินค้า';
                    final code =
                        raw['partCode']?.toString() ??
                        raw['code']?.toString() ??
                        '-';
                    final lineTotal = (resolvedPrice * qty).toStringAsFixed(2);

                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 6,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
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
                            Expanded(
                              flex: 1,
                              child: Text(
                                '$qty',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '฿$lineTotal',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
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
                'Thank You\nPowered by Super POS Man',
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
                      const SnackBar(
                        content: Text('token หาย กรุณา login ใหม่'),
                      ),
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
                      onPressed: () =>
                          Navigator.of(context).pop(PaymentMethod.cash),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('เงินสด'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(PaymentMethod.qr),
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

// --- Inserted: _CashConfirmDialog ---
class _CashConfirmDialog extends StatefulWidget {
  const _CashConfirmDialog({required this.total});

  final double total;

  @override
  State<_CashConfirmDialog> createState() => _CashConfirmDialogState();
}

class _CashConfirmDialogState extends State<_CashConfirmDialog> {
  final TextEditingController _controller = TextEditingController();
  double _paidAmount = 0.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final cleaned = value.replaceAll(',', '').trim();
    final parsed = double.tryParse(cleaned);
    setState(() {
      _paidAmount = parsed ?? 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.total;
    final change = _paidAmount - total;
    final bool isEnough = _paidAmount >= total && total > 0;

    // กำหนด label / สี / ค่า สำหรับแถว "เงินทอน / ขาดอีก"
    String changeLabel;
    Color changeColor;
    String changeValue;

    if (_paidAmount <= 0) {
      changeLabel = 'เงินทอน';
      changeColor = Colors.grey;
      changeValue = '-';
    } else if (!isEnough) {
      changeLabel = 'ขาดอีก';
      changeColor = Colors.red;
      changeValue = '฿${(-change).toStringAsFixed(2)}';
    } else {
      changeLabel = 'เงินทอน';
      changeColor = Colors.green;
      changeValue = '฿${change.toStringAsFixed(2)}';
    }

    return AlertDialog(
      title: const Text('ลูกค้าชำระเงินสด'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCashRow(
              label: 'ยอดที่ต้องชำระ',
              rightWidget: Text(
                '฿${total.toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildCashRow(
              label: 'จำนวนที่ลูกค้าชำระ',
              rightWidget: TextField(
                controller: _controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  hintText: 'เช่น 1000',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: _onChanged,
              ),
            ),
            const SizedBox(height: 12),
            _buildCashRow(
              label: changeLabel,
              labelColor: changeColor,
              rightWidget: Text(
                changeValue,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: changeColor,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton(
          onPressed: isEnough ? () => Navigator.of(context).pop(true) : null,
          child: const Text('ยืนยัน'),
        ),
      ],
    );
  }

  Widget _buildCashRow({
    required String label,
    required Widget rightWidget,
    Color? labelColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: labelColor ?? Colors.black,
            ),
          ),
        ),
        const SizedBox(width: 32),
        SizedBox(
          width: 120,
          child: rightWidget,
        ),
      ],
    );
  }
}