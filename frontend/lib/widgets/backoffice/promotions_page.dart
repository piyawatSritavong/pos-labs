import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/backoffice_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class PromotionsManagementSection extends StatefulWidget {
  const PromotionsManagementSection({super.key});

  @override
  State<PromotionsManagementSection> createState() =>
      _PromotionsManagementSectionState();
}

class _PromotionsManagementSectionState
    extends State<PromotionsManagementSection> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getFilteredPromotions(
    PromotionsProvider promotionsProvider,
  ) {
    final list = promotionsProvider.promotions;
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return list;
    }

    return list.where((p) {
      final code = (p['code'] ?? '').toString().toLowerCase();
      final details = (p['details'] ?? '').toString().toLowerCase();
      final unit = (p['unit'] ?? '').toString().toLowerCase();
      return code.contains(query) ||
          details.contains(query) ||
          unit.contains(query);
    }).toList();
  }

  Future<void> _openCreatePromotionDialog(
    String token,
    PromotionsProvider promotionsProvider,
  ) async {
    final codeController = TextEditingController();
    final detailsController = TextEditingController();
    final unitController = TextEditingController();
    final amountController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('สร้างโปรโมชั่นใหม่'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    labelText: 'Code',
                    hintText: 'เช่น DISC10',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: detailsController,
                  decoration: const InputDecoration(labelText: 'รายละเอียด'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: unitController,
                  decoration: const InputDecoration(
                    labelText: 'ประเภทส่วนลด (unit)',
                    hintText: 'เช่น percent หรือ amount',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop(false);
              },
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () async {
                final code = codeController.text.trim();
                final details = detailsController.text.trim();
                final unit = unitController.text.trim();
                final amountText = amountController.text.trim();

                if (code.isEmpty ||
                    details.isEmpty ||
                    unit.isEmpty ||
                    amountText.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบถ้วน')),
                  );
                  return;
                }

                final amount = num.tryParse(amountText);
                if (amount == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Amount ต้องเป็นตัวเลข')),
                  );
                  return;
                }

                try {
                  await ApiService.createPromotion(
                    token: token,
                    code: code,
                    details: details,
                    unit: unit,
                    amount: amount,
                  );
                  if (!mounted) return;
                  Navigator.of(ctx).pop(true);
                } catch (e) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('สร้างโปรโมชั่นไม่สำเร็จ: $e')),
                  );
                }
              },
              child: const Text('บันทึก'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await promotionsProvider.fetchPromotions(token);
    }

    codeController.dispose();
    detailsController.dispose();
    unitController.dispose();
    amountController.dispose();
  }

  Future<void> _openEditPromotionDialog(
    String token,
    PromotionsProvider promotionsProvider,
    Map<String, dynamic> promotion,
  ) async {
    final code = promotion['code']?.toString() ?? '';
    final codeController = TextEditingController(text: code);
    final detailsController = TextEditingController(
      text: promotion['details']?.toString() ?? '',
    );
    final unitController = TextEditingController(
      text: promotion['unit']?.toString() ?? '',
    );
    final amountController = TextEditingController(
      text: promotion['amount']?.toString() ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('แก้ไขโปรโมชั่น'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeController,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Code'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: detailsController,
                  decoration: const InputDecoration(labelText: 'รายละเอียด'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: unitController,
                  decoration: const InputDecoration(
                    labelText: 'ประเภทส่วนลด (unit)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop(false);
              },
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () async {
                final details = detailsController.text.trim();
                final unit = unitController.text.trim();
                final amountText = amountController.text.trim();

                if (details.isEmpty || unit.isEmpty || amountText.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบถ้วน')),
                  );
                  return;
                }

                final amount = num.tryParse(amountText);
                if (amount == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Amount ต้องเป็นตัวเลข')),
                  );
                  return;
                }

                try {
                  await ApiService.updatePromotion(
                    token: token,
                    code: code,
                    details: details,
                    unit: unit,
                    amount: amount,
                  );
                  if (!mounted) return;
                  Navigator.of(ctx).pop(true);
                } catch (e) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('แก้ไขโปรโมชั่นไม่สำเร็จ: $e')),
                  );
                }
              },
              child: const Text('บันทึก'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await promotionsProvider.fetchPromotions(token);
    }

    codeController.dispose();
    detailsController.dispose();
    unitController.dispose();
    amountController.dispose();
  }

  Future<void> _confirmDeletePromotion(
    String token,
    PromotionsProvider promotionsProvider,
    String code,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('ยืนยันการลบ'),
          content: Text('ต้องการลบโปรโมชั่น $code ใช่หรือไม่?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop(false);
              },
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop(true);
              },
              child: const Text('ลบ'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      try {
        await ApiService.deletePromotion(token: token, code: code);
        if (!mounted) return;
        await promotionsProvider.fetchPromotions(token);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ลบโปรโมชั่นสำเร็จ')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ลบโปรโมชั่นไม่สำเร็จ: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final promotionsProvider = context.watch<PromotionsProvider>();
    final token = auth.token ?? '';

    final promotions = _getFilteredPromotions(promotionsProvider);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Action bar
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: token.isEmpty
                        ? null
                        : () {
                            _openCreatePromotionDialog(
                              token,
                              promotionsProvider,
                            );
                          },
                    icon: const Icon(Icons.local_offer),
                    label: const Text('สร้างโปรโมชั่นใหม่'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: token.isEmpty
                        ? null
                        : () {
                            promotionsProvider.fetchPromotions(token);
                          },
                    icon: const Icon(Icons.refresh),
                    label: const Text('รีเฟรช'),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'ค้นหาโปรโมชั่น (code, details)...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Main table
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
                    child: promotionsProvider.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : promotions.isEmpty
                        ? const Center(child: Text('ยังไม่มีโปรโมชั่น'))
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowHeight: 44,
                              dataRowMinHeight: 44,
                              dataRowMaxHeight: 56,
                              columnSpacing: 24,
                              columns: const [
                                DataColumn(label: Text('Code')),
                                DataColumn(label: Text('รายละเอียด')),
                                DataColumn(label: Text('ประเภท')),
                                DataColumn(label: Text('Amount')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: promotions.map((p) {
                                final code = p['code']?.toString() ?? '';
                                final details = p['details']?.toString() ?? '';
                                final unit = p['unit']?.toString() ?? '';
                                final amount = p['amount']?.toString() ?? '';
                                return DataRow(
                                  cells: [
                                    DataCell(Text(code)),
                                    DataCell(Text(details)),
                                    DataCell(Text(unit)),
                                    DataCell(Text(amount)),
                                    DataCell(
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit),
                                            tooltip: 'แก้ไขโปรโมชั่น',
                                            onPressed: token.isEmpty
                                                ? null
                                                : () {
                                                    _openEditPromotionDialog(
                                                      token,
                                                      promotionsProvider,
                                                      p,
                                                    );
                                                  },
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete),
                                            tooltip: 'ลบโปรโมชั่น',
                                            onPressed: token.isEmpty
                                                ? null
                                                : () {
                                                    _confirmDeletePromotion(
                                                      token,
                                                      promotionsProvider,
                                                      code,
                                                    );
                                                  },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
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
