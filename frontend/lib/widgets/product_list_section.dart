import 'package:flutter/material.dart';
import 'package:frontend/models/product.dart';
import 'package:frontend/providers/cart_provider.dart';
import 'package:provider/provider.dart';

class ProductListSection extends StatelessWidget {
  const ProductListSection({super.key});

  // ตอนนี้ mock list เดียวก่อน
  List<Product> get mockProducts => const [
        Product(
          id: 'p1',
          name: 'ปูนฉาบมาตรฐาน (Mock)',
          price: 1200.00,
          code: 'PNT-001',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context, listen: false);

    return Container(
      color: const Color(0xFFEBEBDB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: mockProducts.length,
              itemBuilder: (context, index) {
                final product = mockProducts[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEBEBDB),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.build,
                        color: Color(0xFF1F6F5D),
                      ),
                    ),
                    title: Text(
                      product.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('รหัส: ${product.code} • ฿${product.price}'),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1F6F5D),
                      ),
                      onPressed: () {
                        cart.addProduct(product);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('เพิ่ม ${product.name} เข้าตะกร้า'),
                          ),
                        );
                      },
                      child: const Text(
                        'เพิ่ม',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Barcode input at bottom (คง logic เดิม แต่ตอนสแกนเสร็จอาจไปหา product จาก code แล้ว add)
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFFEBEBDB),
            child: SafeArea(
              top: false,
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'สแกนบาร์โค้ดที่นี่ (ออโต้โฟกัส)',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(
                        Icons.qr_code_scanner,
                        color: Color(0xFF1F6F5D),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 14,
                      ),
                    ),
                    onSubmitted: (value) {
                      // อนาคต: หา product จาก barcode แล้ว cart.addProduct(product)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('สแกน: $value (ยัง mock อยู่)')),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}