// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
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
  late final bool _canViewIncome;

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  bool _includeBillItems = false;
  bool _isExportingBills = false;
  bool _isExportingParts = false;
  bool _isExportingInventory = false;
  bool _isLoadingIncome = false;
  Map<String, dynamic>? _incomeReport;
  String? _incomeError;

  @override
  void initState() {
    super.initState();
    _canViewIncome = context.read<AuthProvider>().isSuperAdmin;
    _tabController = TabController(length: _canViewIncome ? 4 : 3, vsync: this);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export bills ไม่สำเร็จ: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export parts ไม่สำเร็จ: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export inventory ไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _isExportingInventory = false);
    }
  }

  Future<void> _loadIncome() async {
    final token = context.read<AuthProvider>().token;
    if (token == null || token.isEmpty) return;
    setState(() {
      _isLoadingIncome = true;
      _incomeError = null;
    });
    try {
      final report = await ApiService.getIncomeReport(
        token: token,
        dateFrom: _formatDate(_startDate),
        dateTo: _formatDate(_endDate),
      );
      if (mounted) setState(() => _incomeReport = report);
    } catch (e) {
      if (mounted) setState(() => _incomeError = e.toString());
    } finally {
      if (mounted) setState(() => _isLoadingIncome = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
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
                tabs: [
                  const Tab(
                    icon: Icon(Icons.receipt_long_outlined),
                    text: 'Bills',
                  ),
                  const Tab(
                    icon: Icon(Icons.inventory_2_outlined),
                    text: 'Parts',
                  ),
                  const Tab(
                    icon: Icon(Icons.warehouse_outlined),
                    text: 'Inventory',
                  ),
                  if (_canViewIncome)
                    const Tab(
                      icon: Icon(Icons.insights_outlined),
                      text: 'รายได้',
                    ),
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
                    if (_canViewIncome) _buildIncomeTab(),
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

  double _amount(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _money(dynamic value) => '฿${_amount(value).toStringAsFixed(2)}';

  Widget _buildIncomeTab() {
    final report = _incomeReport;
    final summary = report?['summary'] is Map
        ? Map<String, dynamic>.from(report!['summary'] as Map)
        : <String, dynamic>{};
    final accounts = report?['accounts'] is List
        ? (report!['accounts'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];
    final expenses = report?['expenseDetails'] is List
        ? (report!['expenseDetails'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDateRangeBox(),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _isLoadingIncome ? null : _loadIncome,
            icon: _isLoadingIncome
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
            label: const Text('โหลดรายงานรายได้'),
          ),
          if (_incomeError != null) ...[
            const SizedBox(height: 12),
            Text(
              _incomeError!,
              style: const TextStyle(color: AppColors.danger),
            ),
          ],
          if (report != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _IncomeMetric('รายได้', _money(summary['revenue'])),
                _IncomeMetric('ยอดคืน', _money(summary['returns'])),
                _IncomeMetric('รายได้สุทธิ', _money(summary['netRevenue'])),
                _IncomeMetric('ต้นทุนสุทธิ', _money(summary['netCost'])),
                _IncomeMetric('กำไรขั้นต้น', _money(summary['grossProfit'])),
                _IncomeMetric('ค่าใช้จ่าย', _money(summary['expenses'])),
                _IncomeMetric(
                  _amount(summary['netProfit']) < 0
                      ? 'ขาดทุนสุทธิ'
                      : 'กำไรสุทธิ',
                  _money(summary['netProfit']),
                  danger: _amount(summary['netProfit']) < 0,
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'แยกตามบัญชีผู้ใช้',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('บัญชี')),
                  DataColumn(label: Text('รายได้')),
                  DataColumn(label: Text('คืน')),
                  DataColumn(label: Text('รายได้สุทธิ')),
                  DataColumn(label: Text('ต้นทุนสุทธิ')),
                  DataColumn(label: Text('กำไรขั้นต้น')),
                  DataColumn(label: Text('ค่าใช้จ่าย')),
                  DataColumn(label: Text('กำไร/ขาดทุน')),
                ],
                rows: accounts
                    .map(
                      (a) => DataRow(
                        cells: [
                          DataCell(
                            Text('${a['username'] ?? '-'}\n${a['name'] ?? ''}'),
                          ),
                          DataCell(Text(_money(a['revenue']))),
                          DataCell(Text(_money(a['returns']))),
                          DataCell(Text(_money(a['netRevenue']))),
                          DataCell(Text(_money(a['netCost']))),
                          DataCell(Text(_money(a['grossProfit']))),
                          DataCell(Text(_money(a['expenses']))),
                          DataCell(Text(_money(a['netProfit']))),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'ข้อมูลเพิ่มเติม / ค่าใช้จ่ายจากการปิดยอด',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (expenses.isEmpty)
              const Text('ไม่มีข้อมูลในช่วงวันที่เลือก')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('วันที่')),
                    DataColumn(label: Text('บัญชี')),
                    DataColumn(label: Text('สาขา/POS')),
                    DataColumn(label: Text('น้ำมัน')),
                    DataColumn(label: Text('อาหาร')),
                    DataColumn(label: Text('รายการพิเศษ')),
                    DataColumn(label: Text('ลดปลาย')),
                    DataColumn(label: Text('รวมค่าใช้จ่าย')),
                    DataColumn(label: Text('ยอดโอน')),
                    DataColumn(label: Text('ยอดสรุป')),
                    DataColumn(label: Text('หมายเหตุ')),
                  ],
                  rows: expenses
                      .map(
                        (e) => DataRow(
                          cells: [
                            DataCell(Text(e['closeDate']?.toString() ?? '-')),
                            DataCell(Text(e['username']?.toString() ?? '-')),
                            DataCell(Text('${e['branchId']}/${e['posId']}')),
                            DataCell(Text(_money(e['fuelAmount']))),
                            DataCell(Text(_money(e['foodAmount']))),
                            DataCell(Text(_money(e['specialAmount']))),
                            DataCell(Text(_money(e['tailDiscountAmount']))),
                            DataCell(Text(_money(e['totalExpense']))),
                            DataCell(Text(_money(e['transferAmount']))),
                            DataCell(Text(_money(e['finalSummaryAmount']))),
                            DataCell(
                              Text(
                                [e['notes'], e['specialNote']]
                                    .where(
                                      (v) =>
                                          v != null &&
                                          v.toString().trim().isNotEmpty,
                                    )
                                    .join(' • '),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _IncomeMetric extends StatelessWidget {
  const _IncomeMetric(this.label, this.value, {this.danger = false});

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: danger ? AppColors.danger : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: danger ? AppColors.danger : null,
            ),
          ),
        ],
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
