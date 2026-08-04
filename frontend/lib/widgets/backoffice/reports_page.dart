// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/app_dialog_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class ReportsExportSection extends StatefulWidget {
  const ReportsExportSection({super.key});

  @override
  State<ReportsExportSection> createState() => _ReportsExportSectionState();
}

class _ReportsExportSectionState extends State<ReportsExportSection>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  bool _includeBillItems = false;
  bool _isExportingBills = false;
  bool _isExportingParts = false;
  bool _isExportingInventory = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
        if (_endDate.isBefore(_startDate)) _startDate = _endDate;
      });
    }
  }

  void _downloadCsv(List<int> bytes, String filename) {
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..style.display = 'none'
      ..download = filename;
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _exportBills() async {
    final token = context.read<AuthProvider>().token;
    if (token == null || token.isEmpty) return;

    setState(() => _isExportingBills = true);
    try {
      final from = _formatDate(_startDate);
      final to = _formatDate(_endDate);
      final bytes = await ApiService.exportBillsReportCsv(
        token: token,
        dateFrom: from,
        dateTo: to,
        includeItems: _includeBillItems,
      );
      final label = from == to ? from : '${from}_to_$to';
      final filename = _includeBillItems
          ? 'bills_${label}_items.csv'
          : 'bills_$label.csv';
      _downloadCsv(bytes, filename);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ดาวน์โหลด $filename แล้ว')));
    } catch (e) {
      if (!mounted) return;
      await AppDialogService.showError(
        context,
        error: e,
        fallback: 'ส่งออกรายงานบิลไม่สำเร็จ',
      );
    } finally {
      if (mounted) setState(() => _isExportingBills = false);
    }
  }

  Future<void> _exportParts() async {
    final token = context.read<AuthProvider>().token;
    if (token == null || token.isEmpty) return;

    setState(() => _isExportingParts = true);
    try {
      final bytes = await ApiService.exportPartsReportCsv(token: token);
      _downloadCsv(bytes, 'parts_${DateTime.now().millisecondsSinceEpoch}.csv');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ดาวน์โหลด parts report แล้ว')),
      );
    } catch (e) {
      if (!mounted) return;
      await AppDialogService.showError(
        context,
        error: e,
        fallback: 'ส่งออกรายงานสินค้าไม่สำเร็จ',
      );
    } finally {
      if (mounted) setState(() => _isExportingParts = false);
    }
  }

  Future<void> _exportInventory() async {
    final token = context.read<AuthProvider>().token;
    if (token == null || token.isEmpty) return;

    setState(() => _isExportingInventory = true);
    try {
      final bytes = await ApiService.exportInventoryReportCsv(token: token);
      _downloadCsv(
        bytes,
        'inventory_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ดาวน์โหลด inventory report แล้ว')),
      );
    } catch (e) {
      if (!mounted) return;
      await AppDialogService.showError(
        context,
        error: e,
        fallback: 'ส่งออกรายงานคลังสินค้าไม่สำเร็จ',
      );
    } finally {
      if (mounted) setState(() => _isExportingInventory = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Export Reports',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'ดาวน์โหลดข้อมูลจากระบบเป็นไฟล์ CSV',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Bills'),
                  Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Parts'),
                  Tab(icon: Icon(Icons.warehouse_outlined), text: 'Inventory'),
                ],
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.muted,
                indicatorColor: AppColors.primary,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildBillsTab(),
                    _buildPartsTab(),
                    _buildInventoryTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateRangeBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.date_range, size: 16, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('จาก', style: TextStyle(color: AppColors.muted)),
                OutlinedButton(
                  onPressed: _pickStartDate,
                  child: Text(_formatDate(_startDate)),
                ),
                const Text('ถึง', style: TextStyle(color: AppColors.muted)),
                OutlinedButton(
                  onPressed: _pickEndDate,
                  child: Text(_formatDate(_endDate)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillsTab() {
    return SingleChildScrollView(
      child: _TabCard(
        icon: Icons.receipt_long_outlined,
        title: 'Bills Report',
        description:
            'รายงานบิลขาย / ใบเสร็จรับเงิน ตามช่วงวันที่ (หลายวัน/หลายเดือน)',
        fields: const [
          'billId',
          'branchId',
          'status',
          'totalAmount',
          'paymentMethod',
          'createdAt',
          '(+ รายการสินค้าในบิล ถ้าเปิดตัวเลือก)',
        ],
        actions: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateRangeBox(),
            const SizedBox(height: 10),
            SwitchListTile(
              value: _includeBillItems,
              onChanged: (v) => setState(() => _includeBillItems = v),
              title: const Text('รวมรายการสินค้าในบิล'),
              subtitle: const Text('เปิด = export bills with items'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isExportingBills ? null : _exportBills,
                icon: _isExportingBills
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download),
                label: const Text('ดาวน์โหลด Bills CSV'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartsTab() {
    return SingleChildScrollView(
      child: _TabCard(
        icon: Icons.inventory_2_outlined,
        title: 'Parts / Products Report',
        description:
            'รายการสินค้าทั้งหมดในระบบ (master data) พร้อมราคาและหมวดหมู่',
        fields: const [
          'partCode',
          'nameTh',
          'nameEn',
          'category',
          'unitPrice',
          'isActive',
        ],
        actions: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isExportingParts ? null : _exportParts,
            icon: _isExportingParts
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download),
            label: const Text('ดาวน์โหลด Parts CSV'),
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryTab() {
    return SingleChildScrollView(
      child: _TabCard(
        icon: Icons.warehouse_outlined,
        title: 'Inventory Report',
        description: 'ยอดสินค้าคงคลังแยกตามสาขาและที่เก็บ ณ ปัจจุบัน',
        fields: const [
          'partCode',
          'partName',
          'branchId',
          'addressCode',
          'quantity',
        ],
        actions: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isExportingInventory ? null : _exportInventory,
            icon: _isExportingInventory
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download),
            label: const Text('ดาวน์โหลด Inventory CSV'),
          ),
        ),
      ),
    );
  }
}

class _TabCard extends StatelessWidget {
  const _TabCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.fields,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<String> fields;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 28),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(description, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            const Text(
              'ข้อมูลที่ export:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: fields
                  .map(
                    (f) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        f,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
            actions,
          ],
        ),
      ),
    );
  }
}
