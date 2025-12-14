import 'package:flutter/material.dart';
import 'package:frontend/providers/cart_provider.dart';
import 'package:provider/provider.dart';

class CartSummarySection extends StatelessWidget {
  const CartSummarySection({super.key});

  @override
  Widget build(BuildContext context) {
    // watch = rebuild เมื่อ state เปลี่ยน
    final cart = Provider.of<CartProvider>(context);

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ส่วนบน: แสดง subtotal / discount / tax / total
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal'),
                      Text('฿${cart.subtotal.toStringAsFixed(2)}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('ส่วนลด'),
                      Text('- ฿${cart.discount.toStringAsFixed(2)}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('ภาษี (${(cart.taxRate * 100).toStringAsFixed(0)}%)'),
                      Text('฿${cart.tax.toStringAsFixed(2)}'),
                    ],
                  ),
                  const Divider(height: 24, thickness: 1),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'รวมสุทธิ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '฿${cart.total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F6F5D),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ปุ่มล้าง / พักบิล
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1F6F5D),
                      side: const BorderSide(color: Color(0xFF1F6F5D)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      cart.clear();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ล้างตะกร้าแล้ว')),
                      );
                    },
                    child: const Text('ล้าง'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1F6F5D),
                      side: const BorderSide(color: Color(0xFF1F6F5D)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      // TODO: logic พักบิลจริง ๆ
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('พักบิล (mock)')),
                      );
                    },
                    child: const Text('พักบิล'),
                  ),
                ),
              ],
            ),
          ),

          // ปุ่มยืนยันด้านล่าง (เอาโค้ด Dialog เดิมของคุณมาวางได้เลย)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F6F5D),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () async {
                final result = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (dialogContext) => const PaymentDialog(),
                );

                if (result == true && context.mounted) {
                  await showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (dialogContext) => const ReceiptDialog(),
                  );
                }
              },
              child: const Text(
                'ยืนยัน',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum PaymentMethod {
  cash,
  qr,
}

class PaymentDialog extends StatefulWidget {
  const PaymentDialog({super.key});

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
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

  void _applyQuickDiscount(double percent, double subtotal) {
    setState(() {
      _isPercentMode = true;
      final value = percent;
      _discountController.text = value.toStringAsFixed(0);
      _discountAmount = subtotal * (value / 100.0);
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

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context, listen: false);

    final subtotal = cart.subtotal;
    final taxRate = cart.taxRate;
    // ใช้ส่วนลดจาก dialog นี้ในการคำนวณเฉพาะใน dialog
    final effectiveDiscount = _discountAmount.clamp(0.0, subtotal);
    final tax = subtotal * taxRate;
    final total = subtotal - effectiveDiscount + tax;

    final bool canConfirmPayment = _selectedMethod == PaymentMethod.cash ||
        (_selectedMethod == PaymentMethod.qr && _qrPaymentVerified);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'สรุปการชำระเงิน',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // สรุปยอด
                Card(
                  elevation: 0,
                  color: Colors.grey[100],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _buildSummaryRow('Subtotal', '฿${subtotal.toStringAsFixed(2)}'),
                        const SizedBox(height: 4),
                        _buildSummaryRow('ส่วนลด', '- ฿${effectiveDiscount.toStringAsFixed(2)}'),
                        const SizedBox(height: 4),
                        _buildSummaryRow(
                          'ภาษี (${(taxRate * 100).toStringAsFixed(0)}%)',
                          '฿${tax.toStringAsFixed(2)}',
                        ),
                        const Divider(height: 16, thickness: 1),
                        _buildSummaryRow(
                          'รวมสุทธิ',
                          '฿${total.toStringAsFixed(2)}',
                          isEmphasis: true,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ส่วนลด: ปุ่มลัด + input
                const Text(
                  'ส่วนลด',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final percent in [5, 10, 15, 20])
                      OutlinedButton(
                        onPressed: () => _applyQuickDiscount(percent.toDouble(), subtotal),
                        child: Text('ลด $percent%'),
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
                        DropdownMenuItem(
                          value: true,
                          child: Text('%'),
                        ),
                        DropdownMenuItem(
                          value: false,
                          child: Text('บาท'),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // วิธีชำระ
                const Text(
                  'วิธีชำระเงิน',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('เงินสด'),
                        selected: _selectedMethod == PaymentMethod.cash,
                        onSelected: (_) {
                          setState(() {
                            _selectedMethod = PaymentMethod.cash;
                            _qrPaymentVerified = false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('QR Code'),
                        selected: _selectedMethod == PaymentMethod.qr,
                        onSelected: (_) {
                          setState(() {
                            _selectedMethod = PaymentMethod.qr;
                            _qrPaymentVerified = false;
                          });
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                if (_selectedMethod == PaymentMethod.qr) ...[
                  const SizedBox(height: 8),
                  // แสดง QR code (อย่าลืมเพิ่ม asset จริงใน pubspec.yaml)
                  Center(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 280,
                          child: Image.asset(
                            'images/shop_qr.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Text(
                                'กรุณาเพิ่มรูป QR code ที่ assets/images/shop_qr.png',
                                textAlign: TextAlign.center,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!_qrPaymentVerified) ...[
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _qrPaymentVerified = true;
                              });
                            },
                            child: const Text('ชำระเสร็จสิ้น'),
                          ),
                        ] else ...[
                          const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                          ),
                          const SizedBox(height: 4),
                          const Text('ยืนยันการชำระด้วย QR แล้ว'),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // ปุ่มด้านล่าง
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop(false);
                        },
                        child: const Text('ยกเลิก'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: canConfirmPayment
                            ? () {
                                // อัปเดตส่วนลดเข้า CartProvider เพื่อให้ Summary & ใบเสร็จใช้ค่าตรงกัน
                                cart.setDiscount(effectiveDiscount);

                                Navigator.of(context).pop(true);
                              }
                            : null,
                        child: const Text('ยืนยันการชำระ'),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isEmphasis = false}) {
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
            color: isEmphasis ? const Color(0xFF1F6F5D) : null,
          ),
        ),
      ],
    );
  }
}

class ReceiptDialog extends StatelessWidget {
  const ReceiptDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context, listen: false);

    final subtotal = cart.subtotal;
    final discount = cart.discount;
    final taxRate = cart.taxRate;
    final tax = subtotal * taxRate;
    final total = cart.total;

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
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // ข้อมูลสรุป
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
                onPressed: () {
                  // TODO: เรียกฟังก์ชันพิมพ์ใบเสร็จจริงที่นี่
                  cart.clear(); // ล้างตะกร้าทั้งหมดเหมือนกดปุ่มล้าง
                  Navigator.of(context).pop(); // ปิด dialog ใบเสร็จ
                  Navigator.of(context).maybePop(); // กลับไปหน้าหลัก (ถ้ามี stack)
                },
                child: const Text('กลับหน้าหลัก'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, {bool isEmphasis = false}) {
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