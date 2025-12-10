import 'package:flutter/material.dart';

class StockDialog extends StatelessWidget {
  const StockDialog({super.key});

  @override
  Widget build(BuildContext context) {
    // Mock data - สินค้าที่ใกล้หมด
    final mockLowStockItems = [
      {
        'code': 'PNT-001',
        'name': 'ปูนฉาบมาตรฐาน',
        'currentStock': 5,
        'minStock': 10,
        'unit': 'ถุง',
      },
      {
        'code': 'PNT-004',
        'name': 'ปูนซีเมนต์ขาว',
        'currentStock': 8,
        'minStock': 15,
        'unit': 'ถุง',
      },
      {
        'code': 'PNT-007',
        'name': 'ทรายละเอียด',
        'currentStock': 3,
        'minStock': 20,
        'unit': 'ถุง',
      },
      {
        'code': 'PNT-010',
        'name': 'กาวซีเมนต์',
        'currentStock': 2,
        'minStock': 5,
        'unit': 'กระป๋อง',
      },
    ];

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.6,
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1F6F5D),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'สินค้าใกล้หมด',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Stock items list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: mockLowStockItems.length,
                itemBuilder: (context, index) {
                  final item = mockLowStockItems[index];
                  final currentStock = item['currentStock'] as int;
                  final minStock = item['minStock'] as int;
                  final isCritical = currentStock < minStock * 0.3;
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: isCritical 
                              ? Colors.red[100] 
                              : Colors.orange[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.warning,
                          color: isCritical ? Colors.red : Colors.orange,
                        ),
                      ),
                      title: Text(
                        item['name'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('รหัส: ${item['code']}'),
                          Text(
                            'สต็อกปัจจุบัน: ${item['currentStock']} ${item['unit']}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isCritical ? Colors.red : Colors.orange[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            'สต็อกขั้นต่ำ: ${item['minStock']} ${item['unit']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isCritical ? Colors.red : Colors.orange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isCritical ? 'วิกฤต' : 'ต่ำ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Action button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F6F5D),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('เปิดหน้าจัดการสต็อก')),
                    );
                  },
                  child: const Text(
                    'จัดการสต็อก',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

