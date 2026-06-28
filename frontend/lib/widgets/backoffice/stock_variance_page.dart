import 'package:flutter/material.dart';
import 'package:frontend/services/api_operations.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:frontend/providers/auth_provider.dart';

class StockVariancePage extends StatefulWidget {
  const StockVariancePage({super.key});

  @override
  State<StockVariancePage> createState() => _StockVariancePageState();
}

class _StockVariancePageState extends State<StockVariancePage> {
  List<Map<String, dynamic>> _submittedCounts = [];
  String? _selectedCountId;
  Map<String, dynamic>? _report;
  bool _loadingCounts = false;
  bool _loadingReport = false;
  String? _error;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchCounts());
  }

  Future<void> _fetchCounts() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    setState(() {
      _loadingCounts = true;
      _error = null;
    });
    try {
      final all = await ApiOperationsService.getStockCounts(
        token: token,
        status: 'submitted',
        limit: 200,
      );
      if (mounted) setState(() => _submittedCounts = all);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loadingCounts = false);
    }
  }

  Future<void> _fetchReport(String countId) async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    setState(() {
      _loadingReport = true;
      _error = null;
      _report = null;
    });
    try {
      final report = await ApiOperationsService.getStockVariance(
        token: token,
        countId: countId,
      );
      if (mounted) setState(() => _report = report);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loadingReport = false);
    }
  }

  List<Map<String, dynamic>> get _countsForSelectedDate {
    final dateStr =
        '${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    return _submittedCounts.where((c) {
      final raw =
          (c['createdAt'] ?? c['created_at'] ?? '').toString();
      return raw.startsWith(dateStr);
    }).toList();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _selectedCountId = null;
        _report = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopBar(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(_error!,
                style: const TextStyle(
                    color: AppColors.danger, fontSize: 13)),
          ),
        Expanded(child: _buildSplitLayout()),
      ],
    );
  }

  Widget _buildTopBar() {
    final dateLabel =
        '${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Text('ตรวจสอบสต๊อก',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(dateLabel),
          ),
          const Spacer(),
          if (_loadingCounts)
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'รีเฟรช',
              onPressed: _fetchCounts,
            ),
        ],
      ),
    );
  }

  Widget _buildSplitLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left panel: list of reports for selected date
        SizedBox(
          width: 280,
          child: _buildReportList(),
        ),
        const VerticalDivider(width: 1),
        // Right panel: detail
        Expanded(child: _buildDetail()),
      ],
    );
  }

  Widget _buildReportList() {
    final counts = _countsForSelectedDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Text(
            'รอบนับ (${counts.length} รอบ)',
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        if (_loadingCounts)
          const Expanded(
              child: Center(child: CircularProgressIndicator()))
        else if (counts.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                'ไม่มีรอบนับในวันนี้',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: counts.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, i) {
                final c = counts[i];
                final id = c['id']?.toString() ?? '';
                final branch =
                    (c['branchId'] ?? c['branch_id'] ?? '').toString();
                final raw =
                    (c['createdAt'] ?? c['created_at'] ?? '').toString();
                final timeStr = raw.length >= 16
                    ? raw.substring(11, 16)
                    : '';
                final isSelected = _selectedCountId == id;
                return InkWell(
                  onTap: () {
                    setState(() => _selectedCountId = id);
                    _fetchReport(id);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.08)
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'สาขา: $branch',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.text,
                          ),
                        ),
                        if (timeStr.isNotEmpty)
                          Text(
                            'เวลา: $timeStr น.',
                            style: const TextStyle(
                                color: AppColors.muted, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildDetail() {
    if (_selectedCountId == null) {
      return const Center(
        child: Text('เลือกรอบนับสต๊อกเพื่อดูรายงาน',
            style: TextStyle(color: AppColors.muted)),
      );
    }
    if (_loadingReport) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_report == null) {
      return const Center(
          child: Text('ไม่พบข้อมูล',
              style: TextStyle(color: AppColors.muted)));
    }
    final items = (_report!['items'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final withVariance = items.where((it) {
      final v = it['variance'];
      return v != null && (v as num) != 0;
    }).length;
    final totalVariance = items.fold<int>(0, (sum, it) {
      final v = it['variance'];
      if (v == null) return sum;
      return sum + (v as num).toInt();
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary chips
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _chip('สาขา',
                  '${_report!['branchId'] ?? _report!['branch_id'] ?? '-'}'),
              _chip('Store',
                  '${_report!['storeId'] ?? _report!['store_id'] ?? '-'}'),
              _chip('รายการทั้งหมด', '${items.length}'),
              _chip('มีส่วนต่าง', '$withVariance',
                  color: withVariance > 0
                      ? AppColors.danger
                      : Colors.green),
              _chip(
                'ผลต่างรวม',
                totalVariance >= 0 ? '+$totalVariance' : '$totalVariance',
                color: totalVariance < 0
                    ? AppColors.danger
                    : totalVariance > 0
                        ? Colors.orange
                        : Colors.green,
              ),
            ],
          ),
        ),
        // Table header
        Container(
          color: AppColors.surface,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: const Row(
            children: [
              _HeaderCell('รหัสสินค้า', flex: 2),
              _HeaderCell('ชื่อสินค้า', flex: 4),
              _HeaderCell('ยอดระบบ',
                  flex: 2, align: TextAlign.right),
              _HeaderCell('นับจริง',
                  flex: 2, align: TextAlign.right),
              _HeaderCell('ส่วนต่าง',
                  flex: 2, align: TextAlign.right),
            ],
          ),
        ),
        const Divider(height: 1),
        // Table body
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text('ไม่มีรายการ',
                      style: TextStyle(color: AppColors.muted)))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final variance =
                        (item['variance'] as num?)?.toInt() ?? 0;
                    Color? rowColor;
                    if (variance < 0) {
                      rowColor =
                          AppColors.danger.withValues(alpha: 0.07);
                    } else if (variance > 0) {
                      rowColor =
                          Colors.green.withValues(alpha: 0.07);
                    }
                    return Container(
                      color: rowColor,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          _DataCell(
                              item['partCode'] ??
                                  item['part_code'] ??
                                  '',
                              flex: 2),
                          _DataCell(
                              item['partName'] ??
                                  item['part_name'] ??
                                  '',
                              flex: 4),
                          _DataCell(
                              '${item['systemQty'] ?? item['system_qty'] ?? 0}',
                              flex: 2,
                              align: TextAlign.right),
                          _DataCell(
                              '${item['countedQty'] ?? item['counted_qty'] ?? 0}',
                              flex: 2,
                              align: TextAlign.right),
                          Expanded(
                            flex: 2,
                            child: Text(
                              variance == 0
                                  ? '0'
                                  : variance > 0
                                      ? '+$variance'
                                      : '$variance',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: variance < 0
                                    ? AppColors.danger
                                    : variance > 0
                                        ? Colors.green
                                        : AppColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _chip(String label, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? AppColors.primary).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: color ?? AppColors.primary,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text,
      {required this.flex, this.align = TextAlign.left});
  final String text;
  final int flex;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: align,
        style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: AppColors.muted),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell(this.text,
      {required this.flex, this.align = TextAlign.left});
  final String text;
  final int flex;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(text,
          textAlign: align,
          style: const TextStyle(fontSize: 13)),
    );
  }
}
