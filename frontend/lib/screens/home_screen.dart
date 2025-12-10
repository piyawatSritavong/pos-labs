import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/widgets/bill_dialog.dart';
import 'package:frontend/widgets/cart_dialog.dart';
import 'package:frontend/widgets/cart_summary_section.dart';
import 'package:frontend/widgets/product_list_section.dart';
import 'package:frontend/widgets/stock_dialog.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    print('[HOME] auth tset: ${auth.name}');

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        elevation: 2,
        backgroundColor: const Color(0xFF1F6F5D),
        flexibleSpace: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Left: Logo
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.shopping_bag,
                          color: Color(0xFF1F6F5D),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'POS',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // Middle: Search bar
                Expanded(
                  flex: 6,
                  child: Center(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'ค้นหาสินค้า...',
                        hintStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.grey,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (q) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('ค้นหา: $q')));
                      },
                    ),
                  ),
                ),

                // Right: Cart, Bill, Stock, and Account menu
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Cart icon
                        IconButton(
                          icon: const Icon(Icons.shopping_cart, color: Colors.white, size: 28),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => const CartDialog(),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        // Bill icon
                        IconButton(
                          icon: const Icon(Icons.receipt, color: Colors.white, size: 28),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => const BillDialog(),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        // Stock icon
                        IconButton(
                          icon: const Icon(Icons.inventory, color: Colors.white, size: 28),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => const StockDialog(),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        // Account menu
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.account_circle, color: Colors.white, size: 32),
                          itemBuilder: (context) => <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              enabled: false,
                              child: Text('สวัสดี ${auth.name ?? 'ผู้ใช้'}'),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem<String>(
                              value: 'setting',
                              child: Row(
                                children: const [
                                  Icon(Icons.settings, size: 20),
                                  SizedBox(width: 8),
                                  Text('Setting'),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem<String>(
                              value: 'logout',
                              child: Row(
                                children: const [
                                  Icon(Icons.logout, size: 20),
                                  SizedBox(width: 8),
                                  Text('ออกจากระบบ'),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            if (value == 'setting') {
                              final roleId = auth.roleId ?? 'ไม่มี roleId';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Role: $roleId')),
                              );
                            } else if (value == 'logout') {
                              auth.logout();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      backgroundColor: const Color(0xFFEBEBDB),
      body: Row(
        children: [
          // Left: product list (70%)
          Expanded(flex: 7, child: ProductListSection()),

          // Right: cart summary (30%)
          Expanded(flex: 3, child: CartSummarySection()),
        ],
      ),
    );
  }
}
