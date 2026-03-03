import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/backoffice_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class BillsHistorySection extends StatefulWidget {
  const BillsHistorySection({super.key});

  @override
  State<BillsHistorySection> createState() => _BillsHistorySectionState();
}

class _BillsHistorySectionState extends State<BillsHistorySection> {
  final TextEditingController _searchController = TextEditingController();
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    // โหลดบิลทันทีเมื่อเปิดหน้า ถ้ามี token
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchBills();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchBills() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) return;

    // ถ้าเลือกวันที่ ให้ส่ง date ในรูปแบบ yyyy-MM-dd ไปที่ Provider
    String? dateParam;
    if (_selectedDate != null) {
      final d = _selectedDate!;
      dateParam =
          '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }

    await context.read<BillsProvider>().fetchBills(
      token,
      limit: 50,
      offset: 0,
      date: dateParam,
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 1, 1, 1);
    final lastDate = DateTime(now.year + 1, 12, 31);

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      await _fetchBills();
    }
  }

  String _buildSubtitle(Map<String, dynamic> bill) {
    final dateTime = bill['dateTime']?.toString() ?? '';
    final method = bill['paymentMethod']?.toString() ?? '';
    final total = bill['totalAmount']?.toString() ?? '';

    if (dateTime.isEmpty && method.isEmpty && total.isEmpty) {
      return '';
    }
    return [
      if (dateTime.isNotEmpty) dateTime,
      if (method.isNotEmpty) method,
      if (total.isNotEmpty) '฿$total',
    ].join('  •  ');
  }

  String? _extractBillId(Map<String, dynamic> bill) {
    final billId = bill['billId']?.toString() ?? bill['id']?.toString() ?? '';
    if (billId.isEmpty) {
      return null;
    }
    return billId;
  }

  Future<void> _handleViewBillDetail(Map<String, dynamic> bill) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('หมดเซสชัน กรุณาเข้าสู่ระบบใหม่')),
      );
      return;
    }

    final billId = _extractBillId(bill);
    if (billId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ไม่พบหมายเลขบิล')));
      return;
    }

    try {
      final fullBill = await ApiService.getBill(token: token, billId: billId);
      if (!mounted) return;

      final status = fullBill['status']?.toString() ?? '-';
      final dateTime =
          fullBill['dateTime']?.toString() ??
          fullBill['createdAt']?.toString() ??
          '-';
      final totalAmount = fullBill['totalAmount']?.toString() ?? '-';
      final paymentMethod = fullBill['paymentMethod']?.toString() ?? '-';

      List<dynamic> items = [];
      if (fullBill['items'] is List) {
        items = fullBill['items'] as List;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('รายละเอียดบิล $billId'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('สถานะ: $status'),
                  const SizedBox(height: 4),
                  Text('วันที่/เวลา: $dateTime'),
                  const SizedBox(height: 4),
                  Text('ยอดรวม: ฿$totalAmount'),
                  const SizedBox(height: 4),
                  Text('วิธีชำระเงิน: $paymentMethod'),
                  const SizedBox(height: 12),
                  if (items.isNotEmpty) ...[
                    const Text(
                      'รายการสินค้า',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    ...items.take(10).map((item) {
                      if (item is Map<String, dynamic>) {
                        final name =
                            item['partName']?.toString() ??
                            item['partCode']?.toString() ??
                            '';
                        final qty = item['qty']?.toString() ?? '1';
                        final amount =
                            item['amount']?.toString() ??
                            item['total']?.toString() ??
                            '';
                        return Text('• $name x$qty  = ฿$amount');
                      }
                      return const SizedBox.shrink();
                    }).toList(),
                    if (items.length > 10)
                      const Padding(
                        padding: EdgeInsets.only(top: 4.0),
                        child: Text('... แสดงเฉพาะ 10 รายการแรก'),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('ปิด'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ไม่สามารถดึงข้อมูลบิลได้: $e')));
    }
  }

  Future<void> _handleCancelBill(Map<String, dynamic> bill) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('หมดเซสชัน กรุณาเข้าสู่ระบบใหม่')),
      );
      return;
    }

    final billId = _extractBillId(bill);
    if (billId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ไม่พบหมายเลขบิล')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('ยกเลิกบิล'),
          content: Text('ต้องการยกเลิกบิล $billId ใช่ไหม?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ไม่'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ยืนยัน'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await ApiService.cancelBill(token: token, billId: billId);
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ยกเลิกบิล $billId สำเร็จ')));

      await _fetchBills();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ไม่สามารถยกเลิกบิลได้: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final billsProvider = context.watch<BillsProvider>();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // แถวตัวกรอง / การค้นหา / โหลดข้อมูล
              Row(
                children: [
                  // ช่องค้นหา (ตอนนี้ใช้สำหรับ trigger reload, filter ฝั่ง client ค่อยทำเพิ่มได้)
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText: 'ค้นหาตาม Bill ID หรือคำค้นอื่น ๆ',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) {
                        _fetchBills();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // ปุ่มเลือกวันที่
                  IconButton(
                    tooltip: 'เลือกวันที่',
                    onPressed: _pickDate,
                    icon: const Icon(Icons.date_range),
                  ),
                  const SizedBox(width: 8),
                  // ปุ่มโหลดข้อมูลใหม่
                  OutlinedButton.icon(
                    onPressed: _fetchBills,
                    icon: const Icon(Icons.refresh),
                    label: const Text('โหลดข้อมูล'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // การ์ดหลักแสดงรายการบิล
              Expanded(
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.all(16.0),
                    child: billsProvider.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : billsProvider.bills.isEmpty
                        ? const Center(child: Text('ยังไม่มีประวัติบิล'))
                        : ListView.builder(
                            itemCount: billsProvider.bills.length,
                            itemBuilder: (context, index) {
                              final b = billsProvider.bills[index];
                              final billId =
                                  b['billId']?.toString() ??
                                  b['id']?.toString() ??
                                  '';

                              final subtitle = _buildSubtitle(b);

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  leading: const Icon(Icons.receipt_long),
                                  title: Text(
                                    billId.isEmpty ? 'ไม่พบ Bill ID' : billId,
                                  ),
                                  subtitle: subtitle.isEmpty
                                      ? null
                                      : Text(subtitle),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (value) async {
                                      switch (value) {
                                        case 'view':
                                          await _handleViewBillDetail(b);
                                          break;
                                        case 'cancel':
                                          await _handleCancelBill(b);
                                          break;
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'view',
                                        child: Text('ดูรายละเอียดบิล'),
                                      ),
                                      PopupMenuItem(
                                        value: 'cancel',
                                        child: Text('ยกเลิกบิล'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
