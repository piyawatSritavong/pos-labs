import 'package:flutter/material.dart';
import 'package:frontend/models/product.dart';
import 'package:frontend/providers/cart_provider.dart';
import 'package:provider/provider.dart';

class ProductListSection extends StatefulWidget {
  const ProductListSection({super.key});

  @override
  State<ProductListSection> createState() => _ProductListSectionState();
}

class _ProductListSectionState extends State<ProductListSection> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  List<Product> get _mockProducts => const [
    Product(
      id: 'p1',
      name: 'ปูนฉาบมาตรฐาน (Mock)',
      price: 1200.00,
      code: 'PNT-001',
    ),
    Product(
      id: 'p2',
      name: 'ปูนฉาบกันซึม (Mock)',
      price: 1500.00,
      code: 'PNT-002',
    ),
    Product(
      id: 'p3',
      name: 'ปูนตราผึ้ง (Mock)',
      price: 800.00,
      code: 'PNT-102',
    ),
  ];

  List<Product> get _filteredProducts {
    if (_searchText.isEmpty) return _mockProducts;

    final q = _searchText.toLowerCase();
    return _mockProducts.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.code.toLowerCase().contains(q);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
              itemCount: _filteredProducts.length,
              itemBuilder: (context, index) {
                final product = _filteredProducts[index];
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
                      child: const Icon(Icons.build, color: Color(0xFF1F6F5D)),
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
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    // 👉 พิมแล้วให้ search อัตโนมัติ
                    onChanged: (value) {
                      setState(() {
                        _searchText = value;
                      });
                    },

                    // 👉 ถ้ากด Enter (สแกนบาร์โค้ดส่วนใหญ่จะยิง Enter ให้อัตโนมัติ)
                    //    แล้วเจอสินค้าตัวเดียว → เพิ่มเข้าตะกร้าให้เลย
                    onSubmitted: (value) {
                      setState(() {
                        _searchText = value;
                      });

                      final matches = _filteredProducts;
                      if (matches.length == 1) {
                        final product = matches.first;
                        cart.addProduct(product);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('เพิ่ม ${product.name} เข้าตะกร้า'),
                          ),
                        );
                        // เคลียร์ช่อง + เคลียร์ filter
                        _searchController.clear();
                        setState(() {
                          _searchText = '';
                        });
                      } else if (matches.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('ไม่พบสินค้าสำหรับ "$value"')),
                        );
                      } else {
                        // ถ้ามากกว่า 1 ตัว ก็ปล่อยให้ user เลือกจาก list ด้านบน
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'พบ ${matches.length} รายการ เลือกจากด้านบน',
                            ),
                          ),
                        );
                      }
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
