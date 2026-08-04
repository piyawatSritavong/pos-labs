import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/backoffice_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/app_dialog_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class BillsHistorySection extends StatefulWidget {
  const BillsHistorySection({super.key});

  @override
  State<BillsHistorySection> createState() => _BillsHistorySectionState();
}

class _BillsHistorySectionState extends State<BillsHistorySection> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _memberIdController = TextEditingController();
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
    _memberIdController.dispose();
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

    final memberId = _memberIdController.text.trim();

    await context.read<BillsProvider>().fetchBills(
      token,
      limit: 50,
      offset: 0,
      date: dateParam,
      memberId: memberId.isEmpty ? null : memberId,
      statuses: const ['completed', 'cancelled'],
      includeDetails: true,
      scope: 'branch',
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
    final method = _paymentLabel(bill['paymentMethod']?.toString() ?? '');
    final total = bill['totalAmount']?.toString() ?? '';
    // Operator: prefer the resolved display name (e.g. "Administrator").
    final operator = (bill['createdByName'] ?? bill['createdBy'] ?? '')
        .toString();
    String memberText = '';
    final member = bill['member'];
    if (member is Map<String, dynamic>) {
      final code = member['code']?.toString() ?? '';
      final name = member['name']?.toString() ?? '';
      if (code.isNotEmpty || name.isNotEmpty) {
        memberText =
            'Member: ${[code, name].where((e) => e.isNotEmpty).join(' ')}';
      }
    }

    if (dateTime.isEmpty &&
        method.isEmpty &&
        total.isEmpty &&
        memberText.isEmpty &&
        operator.isEmpty) {
      return '';
    }
    return [
      if (dateTime.isNotEmpty) dateTime,
      if (method.isNotEmpty) method,
      if (memberText.isNotEmpty) memberText,
      if (operator.isNotEmpty) 'พนักงาน: $operator',
      if (total.isNotEmpty) '฿$total',
    ].join('  •  ');
  }

  String _paymentLabel(String method) {
    switch (method.toLowerCase().trim()) {
      case 'cash':
        return 'เงินสด';
      case 'bank':
      case 'transfer':
      case 'qr':
      case 'qr_code':
        return 'โอน';
      case 'credit_term':
        return 'เงินเซ็น';
      case 'exchange':
        return 'แลกเปลี่ยน';
      case '':
        return '';
      default:
        return method;
    }
  }

  Widget _buildStatusBadge(String status) {
    final upper = status.toUpperCase();
    final Color bg;
    final Color border;
    final Color text;
    if (upper == 'COMPLETED') {
      bg = Colors.green.shade50;
      border = Colors.green;
      text = Colors.green.shade700;
    } else if (upper == 'CANCELLED') {
      bg = AppColors.danger.withValues(alpha: 0.08);
      border = AppColors.danger;
      text = AppColors.danger;
    } else {
      bg = Colors.grey.shade100;
      border = Colors.grey.shade400;
      text = Colors.grey.shade600;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        upper,
        style: TextStyle(
          color: text,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  double _resolveAmount(Map<String, dynamic> bill, List<String> keys) {
    for (final key in keys) {
      final value = bill[key];
      if (value != null) {
        return _toDouble(value);
      }
    }
    return 0.0;
  }

  List<Map<String, dynamic>> _extractDetails(Map<String, dynamic> bill) {
    final raw = bill['details'] ?? bill['items'];
    if (raw is! List) {
      return const [];
    }
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  double _resolveLineTotal(Map<String, dynamic> detail) {
    final direct = detail['lineTotal'] ?? detail['amount'] ?? detail['total'];
    if (direct is num) {
      return direct.toDouble();
    }
    final qty = double.tryParse(detail['qty']?.toString() ?? '') ?? 0;
    final price = double.tryParse(
      (detail['price'] ?? detail['unitPrice'])?.toString() ?? '',
    );
    return (price ?? 0) * qty;
  }

  Widget? _buildInlineDetails(Map<String, dynamic> bill) {
    final details = _extractDetails(bill);
    if (details.isEmpty) {
      return null;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: details.map((detail) {
          final name =
              detail['partName']?.toString() ??
              detail['name']?.toString() ??
              detail['partCode']?.toString() ??
              '-';
          final qty = detail['qty']?.toString() ?? '0';
          final lineTotal = _resolveLineTotal(detail);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('• $name x$qty = ฿${lineTotal.toStringAsFixed(2)}'),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAmountsSummary(Map<String, dynamic> bill) {
    final subtotal = _resolveAmount(bill, [
      'purchaseAmount',
      'purchase_amount',
      'subtotal',
    ]);
    final discount = _resolveAmount(bill, [
      'totalDiscount',
      'total_discount',
      'discount',
    ]);
    final total = _resolveAmount(bill, [
      'totalAmount',
      'total_amount',
      'total',
    ]);
    final afterDiscount = (subtotal - discount)
        .clamp(0.0, double.infinity)
        .toDouble();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _AmountBadge(
            label: 'ก่อนลด',
            value: '฿${subtotal.toStringAsFixed(2)}',
          ),
          _AmountBadge(
            label: 'ส่วนลด',
            value: '-฿${discount.toStringAsFixed(2)}',
            accent: true,
          ),
          _AmountBadge(
            label: 'หลังลด',
            value: '฿${afterDiscount.toStringAsFixed(2)}',
          ),
          _AmountBadge(
            label: 'รวมสุทธิ',
            value: '฿${total.toStringAsFixed(2)}',
            bold: true,
          ),
        ],
      ),
    );
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
      await AppDialogService.showError(
        context,
        error: Exception('missing_token'),
        fallback: 'กรุณาเข้าสู่ระบบอีกครั้ง',
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
      final subtotal = _resolveAmount(fullBill, [
        'purchaseAmount',
        'purchase_amount',
        'subtotal',
      ]);
      final discount = _resolveAmount(fullBill, [
        'totalDiscount',
        'total_discount',
        'discount',
      ]);
      final afterDiscount = (subtotal - discount)
          .clamp(0.0, double.infinity)
          .toDouble();
      final totalAmount = _resolveAmount(fullBill, [
        'totalAmount',
        'total_amount',
        'total',
      ]);
      final paymentMethod = _paymentLabel(
        fullBill['paymentMethod']?.toString() ?? '-',
      );

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
                  Text('ก่อนลด: ฿${subtotal.toStringAsFixed(2)}'),
                  const SizedBox(height: 4),
                  Text('ส่วนลด: -฿${discount.toStringAsFixed(2)}'),
                  const SizedBox(height: 4),
                  Text('หลังลด: ฿${afterDiscount.toStringAsFixed(2)}'),
                  const SizedBox(height: 4),
                  Text('รวมสุทธิ: ฿${totalAmount.toStringAsFixed(2)}'),
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
                    }),
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
      await AppDialogService.showError(
        context,
        error: e,
        fallback: 'โหลดรายละเอียดบิลไม่สำเร็จ',
      );
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
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _memberIdController,
                      decoration: const InputDecoration(
                        labelText: 'Filter Member ID',
                        prefixIcon: Icon(Icons.badge_outlined),
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
                              final status = b['status']?.toString() ?? '';

                              final subtitle = _buildSubtitle(b);

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  leading: const Icon(Icons.receipt_long),
                                  title: Row(
                                    children: [
                                      Text(
                                        billId.isEmpty
                                            ? 'ไม่พบ Bill ID'
                                            : billId,
                                      ),
                                      const SizedBox(width: 8),
                                      if (status.isNotEmpty)
                                        _buildStatusBadge(status),
                                    ],
                                  ),
                                  subtitle: Builder(
                                    builder: (context) {
                                      final inlineDetails = _buildInlineDetails(
                                        b,
                                      );
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (subtitle.isNotEmpty)
                                            Text(subtitle),
                                          _buildAmountsSummary(b),
                                          if (inlineDetails != null)
                                            inlineDetails,
                                        ],
                                      );
                                    },
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (value) async {
                                      switch (value) {
                                        case 'view':
                                          await _handleViewBillDetail(b);
                                          break;
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'view',
                                        child: Text('ดูรายละเอียดบิล'),
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

class _AmountBadge extends StatelessWidget {
  const _AmountBadge({
    required this.label,
    required this.value,
    this.bold = false,
    this.accent = false,
  });

  final String label;
  final String value;
  final bool bold;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent ? AppColors.accent : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: accent ? AppColors.accent : AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}
