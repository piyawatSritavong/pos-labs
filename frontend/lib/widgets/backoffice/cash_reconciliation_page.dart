import 'package:flutter/material.dart';
import 'package:frontend/services/api_operations.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:frontend/providers/auth_provider.dart';

class CashReconciliationPage extends StatefulWidget {
  const CashReconciliationPage({super.key});

  @override
  State<CashReconciliationPage> createState() => _CashReconciliationPageState();
}

class _CashReconciliationPageState extends State<CashReconciliationPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _pendingCloses = [];
  List<Map<String, dynamic>> _reconciliations = [];
  bool _loadingPending = false;
  bool _loadingHistory = false;
  String? _error;

  Map<String, dynamic>? _selectedClose;
  final _actualAmountController = TextEditingController();
  final _notesController = TextEditingController();
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAll());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _actualAmountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _fetchAll() async {
    _fetchPending();
    _fetchHistory();
  }

  Future<void> _fetchPending() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    setState(() {
      _loadingPending = true;
      _error = null;
    });
    try {
      final all = await ApiOperationsService.getDailyCloses(
        token: token,
        limit: 200,
      );
      final closes = all
          .where((c) => (c['status'] as String?) == 'pending_reconciliation')
          .toList();
      if (mounted) setState(() => _pendingCloses = closes);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loadingPending = false);
    }
  }

  Future<void> _fetchHistory() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    setState(() => _loadingHistory = true);
    try {
      final recons = await ApiOperationsService.getCashReconciliations(
        token: token,
        limit: 100,
      );
      if (mounted) setState(() => _reconciliations = recons);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _submitReconciliation() async {
    if (_selectedClose == null) return;
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    final actualStr = _actualAmountController.text.trim();
    final actualAmount = double.tryParse(actualStr);
    if (actualAmount == null) {
      setState(() => _submitError = 'กรุณากรอกจำนวนเงินที่ถูกต้อง');
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await ApiOperationsService.createCashReconciliation(
        token: token,
        dailyCloseId: _selectedClose!['id'] as String,
        actualAmount: actualAmount,
        notes: _notesController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _selectedClose = null;
          _actualAmountController.clear();
          _notesController.clear();
        });
        _fetchAll();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ยืนยันการรับเงินสำเร็จ')));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _submitError = e.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.muted,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'รอการยืนยัน'),
            Tab(text: 'ประวัติการยืนยัน'),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [_buildPendingTab(), _buildHistoryTab()],
          ),
        ),
      ],
    );
  }

  Widget _buildPendingTab() {
    if (_loadingPending) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pendingCloses.isEmpty) {
      return const Center(
        child: Text(
          'ไม่มีรายการรอยืนยัน',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: list of pending closes
        SizedBox(
          width: 360,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _pendingCloses.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final close = _pendingCloses[i];
              final isSelected = _selectedClose?['id'] == close['id'];
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() {
                    _selectedClose = close;
                    _actualAmountController.text = _expectedAmount(
                      close,
                    ).toStringAsFixed(2);
                    _notesController.clear();
                    _submitError = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.08)
                        : AppColors.surface,
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'สาขา: ${close['branchId'] ?? close['branch_id'] ?? '-'}  POS: ${close['posId'] ?? close['pos_id'] ?? '-'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'วันที่: ${close['closeDate'] ?? close['close_date'] ?? '-'}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ยอดส่งโกดัง: ฿${_fmt(_expectedAmount(close))}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Right: confirm form
        Expanded(
          child: _selectedClose == null
              ? const Center(
                  child: Text(
                    'เลือกรายการทางซ้ายเพื่อยืนยันการรับเงิน',
                    style: TextStyle(color: AppColors.muted),
                  ),
                )
              : _buildConfirmForm(),
        ),
      ],
    );
  }

  Widget _buildConfirmForm() {
    final close = _selectedClose!;
    final expected = _expectedAmount(close);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ยืนยันการรับเงิน',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _infoRow('สาขา', '${close['branchId'] ?? close['branch_id'] ?? '-'}'),
          _infoRow('POS', '${close['posId'] ?? close['pos_id'] ?? '-'}'),
          _infoRow(
            'วันที่',
            '${close['closeDate'] ?? close['close_date'] ?? '-'}',
          ),
          _infoRow(
            'ยอดขายรวม',
            '฿${_fmt(close['totalSales'] ?? close['total_sales'])}',
          ),
          _infoRow(
            'เงินสด',
            '฿${_fmt(close['totalCash'] ?? close['total_cash'])}',
          ),
          _infoRow(
            'โอนเงิน',
            '฿${_fmt(close['totalTransfer'] ?? close['total_transfer'])}',
          ),
          _infoRow(
            'เงินเซ็น',
            '฿${_fmt(close['totalCreditTerm'] ?? close['total_credit_term'])}',
          ),
          _infoRow(
            'ยอดคืนสินค้า',
            '฿${_fmt(close['totalReturns'] ?? close['total_returns'])}',
          ),
          const Divider(height: 18),
          _optionalInfoRow(
            'น้ำมัน',
            close['fuelAmount'] ?? close['fuel_amount'],
          ),
          _optionalInfoRow(
            'อาหาร',
            close['foodAmount'] ?? close['food_amount'],
          ),
          _optionalInfoRow(
            'ยอดโอนที่แจ้ง',
            close['transferAmount'] ?? close['transfer_amount'],
          ),
          _optionalInfoRow(
            'รายการพิเศษ',
            close['specialAmount'] ?? close['special_amount'],
          ),
          _optionalInfoRow(
            'ลดปลาย',
            close['tailDiscountAmount'] ?? close['tail_discount_amount'],
          ),
          _optionalInfoRow(
            'สรุปยอด',
            close['finalSummaryAmount'] ?? close['final_summary_amount'],
          ),
          if ((close['specialNote'] ?? close['special_note'] ?? '')
              .toString()
              .trim()
              .isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'หมายเหตุรายการพิเศษ:\n${close['specialNote'] ?? close['special_note']}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          const Divider(height: 24),
          _infoRow(
            'ยอดที่ต้องรับ (expected)',
            '฿${_fmt(expected)}',
            bold: true,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _actualAmountController,
            decoration: const InputDecoration(
              labelText: 'ยอดที่รับจริง *',
              border: OutlineInputBorder(),
              prefixText: '฿ ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'หมายเหตุ',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 8),
            Text(
              _submitError!,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _submitReconciliation,
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('ยืนยันรับเงิน'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_reconciliations.isEmpty) {
      return const Center(
        child: Text(
          'ยังไม่มีประวัติการยืนยัน',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _reconciliations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = _reconciliations[i];
        final expected =
            double.tryParse(
              (r['expectedAmount'] ?? r['expected_amount'] ?? '0').toString(),
            ) ??
            0;
        final actual =
            double.tryParse(
              (r['actualAmount'] ?? r['actual_amount'] ?? '0').toString(),
            ) ??
            0;
        final diff = actual - expected;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'สาขา: ${r['branchId'] ?? r['branch_id'] ?? '-'}  POS: ${r['posId'] ?? r['pos_id'] ?? '-'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'วันที่: ${r['closeDate'] ?? r['close_date'] ?? '-'}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Expected: ฿${_fmt(expected)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    'Actual: ฿${_fmt(actual)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    diff >= 0 ? '+฿${_fmt(diff)}' : '-฿${_fmt(diff.abs())}',
                    style: TextStyle(
                      color: diff >= 0 ? Colors.green : AppColors.danger,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionalInfoRow(String label, dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return _infoRow(label, '฿${_fmt(value)}');
  }

  double _expectedAmount(Map<String, dynamic> close) {
    final finalSummary =
        close['finalSummaryAmount'] ?? close['final_summary_amount'];
    if (finalSummary != null && finalSummary.toString().trim().isNotEmpty) {
      final parsed = double.tryParse(finalSummary.toString());
      if (parsed != null) return parsed;
    }
    return double.tryParse(
          (close['netAmount'] ?? close['net_amount'] ?? '0').toString(),
        ) ??
        0.0;
  }

  String _fmt(dynamic v) {
    if (v == null) return '0.00';
    final d = double.tryParse(v.toString()) ?? 0.0;
    return d.toStringAsFixed(2);
  }
}
