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
                // ตรงนี้คุณสามารถใช้ cart.itemsList, cart.total ฯลฯ ไปส่งต่อหน้า Payment ได้
                // โค้ด Dialog เดิมของคุณยังใช้ได้เหมือนเดิม
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