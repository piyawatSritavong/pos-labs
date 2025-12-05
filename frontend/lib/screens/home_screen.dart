import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    // Mock values
    const subtotal = 1200.00;
    const discount = 0.00;
    const taxRate = 0.07;
    final tax = subtotal * taxRate;
    final total = subtotal - discount + tax;

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
                        child: const Icon(Icons.shopping_bag, color: Color(0xFF1F6F5D)),
                      ),
                      const SizedBox(width: 8),
                      const Text('POS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onSubmitted: (q) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ค้นหา: $q')));
                      },
                    ),
                  ),
                ),

                // Right: Account menu (logout)
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.account_circle, color: Colors.white, size: 32),
                      itemBuilder: (context) => <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          enabled: false,
                          child: Text('สวัสดี ${auth.name ?? 'ผู้ใช้'}'),
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
                        if (value == 'logout') auth.logout();
                      },
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
          Expanded(
            flex: 7,
            child: Container(
              color: const Color(0xFFEBEBDB),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  // Container(
                  //   padding: const EdgeInsets.all(16),
                  //   decoration: BoxDecoration(
                  //     color: Colors.white,
                  //     border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
                  //   ),
                  //   child: const Text('รายการสินค้า', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F6F5D))),
                  // ),

                  // Single mock item
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(8),
                      children: [
                        Card(
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
                            title: const Text('ปูนฉาบมาตรฐาน (Mock)', style: TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: const Text('รหัส: PNT-001 • ฿1,200.00'),
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F6F5D)),
                              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('เพิ่มเข้าสู่ตะกร้า (mock)'))),
                              child: const Text('เพิ่ม', style: TextStyle(color: Colors.white)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Barcode input at bottom (autofocus) - centered, 50% width
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
                              prefixIcon: const Icon(Icons.qr_code_scanner, color: Color(0xFF1F6F5D)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onSubmitted: (value) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('สแกน: $value')));
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right: cart summary (30%)
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Container(
                  //   padding: const EdgeInsets.all(16),
                  //   decoration: BoxDecoration(color: const Color(0xFFEBEBDB), border: Border(bottom: BorderSide(color: Colors.grey[300]!))),
                  //   child: const Text('สรุปยอด', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F6F5D))),
                  // ),

                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [Text('Subtotal'), Text('฿1,200.00')]),
                          const SizedBox(height: 8),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [Text('ส่วนลด'), Text('- ฿0.00')]),
                          const SizedBox(height: 8),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('ภาษี (7%)'), Text('฿${( (1200.0 * 0.07) ).toStringAsFixed(2)}')]),
                          const Divider(height: 24, thickness: 1),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('รวมสุทธิ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text('฿${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F6F5D)))]),
                        ],
                      ),
                    ),
                  ),

                  // Top quick-action buttons: ล้าง and พักบิล
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
                              // ล้าง mock action
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ล้างตะกร้า (mock)')));
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
                              // พักบิล mock action
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('พักบิล (mock)')));
                            },
                            child: const Text('พักบิล'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Confirm button (bottom)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey[300]!))),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F6F5D), padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: () async {
                        final result = await showDialog<String>(
                          context: context,
                          builder: (context) => Dialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Three centered buttons in a row
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      ElevatedButton(
                                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1F6F5D), side: const BorderSide(color: Color(0xFF1F6F5D))),
                                        onPressed: () => Navigator.of(context).pop('pay'),
                                        child: const Text('ชำระเงิน'),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1F6F5D), side: const BorderSide(color: Color(0xFF1F6F5D))),
                                        onPressed: () => Navigator.of(context).pop('discount'),
                                        child: const Text('ส่วนลด'),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1F6F5D), side: const BorderSide(color: Color(0xFF1F6F5D))),
                                        onPressed: () => Navigator.of(context).pop('quick'),
                                        child: const Text('ขายด่วน'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // Full-width cancel button below
                                  SizedBox(
                                    width: 290,
                                    child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1F6F5D), side: const BorderSide(color: Color(0xFF1F6F5D))),
                                      onPressed: () => Navigator.of(context).pop(null),
                                      child: const Text('ยกเลิก'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );

                        if (result == 'pay') {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ไปยังหน้าชำระเงิน (mock)')));
                        } else if (result == 'quick') {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ขายด่วนเรียบร้อย (mock)')));
                        } else if (result == 'discount') {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('เปิดหน้าตั้งค่าส่วนลด (mock)')));
                        }
                      },
                      child: const Text('ยืนยัน', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
