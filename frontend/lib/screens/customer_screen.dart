import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/providers/bill_provider.dart';
import 'package:provider/provider.dart';

class CustomerScreen extends StatefulWidget {
  const CustomerScreen({super.key});

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  html.BroadcastChannel? _bc;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _bc = html.BroadcastChannel('pos_mirror');
      _bc!.addEventListener('message', _onMirrorMessage);
      // ขอ fullscreen หลังหน้าถูก render เสร็จ (Web only) เพื่อให้แสดงเต็มจอ 2
      // user gesture จากปุ่มในหน้าหลักจะส่งต่อมาให้ popup นี้ใช้สิทธิ์ขอ fullscreen ได้
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestFullscreen());
    }
  }

  void _requestFullscreen() {
    try {
      html.document.documentElement?.requestFullscreen();
    } catch (_) {
      // permission denied / not in user gesture context — แสดง windowed mode ปกติ
    }
  }

  void _onMirrorMessage(html.Event event) {
    final me = event as html.MessageEvent;
    try {
      final data = jsonDecode(me.data as String) as Map<String, dynamic>;
      if (mounted) context.read<BillProvider>().updateFromMirrorState(data);
    } catch (_) {}
  }

  @override
  void dispose() {
    _bc?.close();
    _bc = null;
    super.dispose();
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  List<_CustomerLineItem> _mapItems(List<Map<String, dynamic>> rawItems) {
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

      return _CustomerLineItem(
        name:
            item['nameTh']?.toString() ??
            item['name']?.toString() ??
            item['description']?.toString() ??
            'สินค้า',
        code: partCode ?? '-',
        qty: qty,
        price: resolvedPrice,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bill = context.watch<BillProvider>();
    final items = _mapItems(bill.items);
    final subtotal = bill.subtotal;
    final discount = bill.discount;
    final amountAfterDiscount = bill.amountAfterDiscount;
    final taxRate = bill.taxRate;
    final tax = bill.tax;
    final total = bill.total;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'ยินดีต้อนรับ',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'กรุณาตรวจสอบรายการสินค้า และยอดชำระ',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
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
                          // Header แสดงจำนวนสินค้าในตะกร้า
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'รายการสินค้า',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${items.length} รายการ',
                                style: const TextStyle(color: AppColors.muted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // ส่วนแสดงรายการสินค้า + สรุปยอด (scroll ได้)
                          Expanded(
                            child: items.isEmpty
                                ? const Center(
                                    child: Text(
                                      'ยินดีให้บริการครับ/ค่ะ\nเมื่อพนักงานเพิ่มรายการสินค้า รายการจะปรากฏที่นี่',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: AppColors.muted),
                                    ),
                                  )
                                : SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // รายการสินค้าแต่ละบรรทัด (เหมือน CartSummarySection)
                                        ...items.map((it) {
                                          final lineTotal = (it.price * it.qty)
                                              .toStringAsFixed(2);
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  flex: 5,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        it.name,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        it.code,
                                                        style: const TextStyle(
                                                          color:
                                                              AppColors.muted,
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
                                                      fontWeight:
                                                          FontWeight.w600,
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
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                        const SizedBox(height: 12),
                                        Divider(
                                          height: 1,
                                          color: AppColors.border.withValues(
                                            alpha: 0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        // สรุปยอดเหมือนเดิม
                                        _buildSummaryRow(
                                          'ก่อนลด',
                                          '฿${subtotal.toStringAsFixed(2)}',
                                        ),
                                        const SizedBox(height: 8),
                                        _buildSummaryRow(
                                          'ส่วนลด',
                                          '- ฿${discount.toStringAsFixed(2)}',
                                        ),
                                        const SizedBox(height: 8),
                                        _buildSummaryRow(
                                          'หลังหักส่วนลด',
                                          '฿${amountAfterDiscount.toStringAsFixed(2)}',
                                        ),
                                        const SizedBox(height: 8),
                                        _buildSummaryRow(
                                          'ภาษี (${(taxRate * 100).toStringAsFixed(0)}%)',
                                          '฿${tax.toStringAsFixed(2)}',
                                        ),
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                            horizontal: 14,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.05,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              AppSizes.radius,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
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
                          const SizedBox(height: 12),
                          const Text(
                            'ยอดและรายการนี้เป็นแบบอ่านอย่างเดียว\nการเปลี่ยนแปลงทำได้จากหน้าจอพนักงานเท่านั้น',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (bill.isAwaitingCashPayment)
            _CashPaymentOverlay(amount: bill.awaitingCashAmount),
          if (bill.isAwaitingQrPayment) _QrScanOverlay(amount: total),
          if (bill.showThankYouOverlay) const _ThankYouOverlay(),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
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

class _CustomerLineItem {
  _CustomerLineItem({
    required this.name,
    required this.code,
    required this.qty,
    required this.price,
  });

  final String name;
  final String code;
  final int qty;
  final double price;
}

class _CashPaymentOverlay extends StatefulWidget {
  const _CashPaymentOverlay({required this.amount});

  final double amount;

  @override
  State<_CashPaymentOverlay> createState() => _CashPaymentOverlayState();
}

class _CashPaymentOverlayState extends State<_CashPaymentOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _colorAnimation = ColorTween(
      begin: Colors.white.withOpacity(0.6),
      end: Colors.green.withOpacity(0.6),
    ).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _colorAnimation,
        builder: (context, _) {
          return Container(
            color: _colorAnimation.value,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppSizes.radius),
                  boxShadow: AppShadows.soft,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'กรุณาชำระเงิน',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'กรุณาชำระเงินตามยอด ฿${widget.amount.toStringAsFixed(2)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'โปรดแจ้งพนักงานเมื่อชำระเงินเรียบร้อย',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ThankYouOverlay extends StatelessWidget {
  const _ThankYouOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSizes.radius),
              boxShadow: AppShadows.soft,
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ขอบคุณที่ใช้บริการของเรา',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'ขอให้มีวันที่ดี แล้วพบกันใหม่ในครั้งถัดไป',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QrScanOverlay extends StatelessWidget {
  const _QrScanOverlay({required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.4),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSizes.radius),
              boxShadow: AppShadows.soft,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'สแกนเพื่อชำระเงิน',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'กรุณาสแกน QR Code เพื่อชำระเงินตามยอด ฿${amount.toStringAsFixed(2)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 260,
                  width: 260,
                  child: Image.asset(
                    'images/shop_qr.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Text(
                          'กรุณาเพิ่มรูป QR code ที่ images/shop_qr.png',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'โปรดแจ้งพนักงานเมื่อสแกนและชำระเงินเรียบร้อย',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
