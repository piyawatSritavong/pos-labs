import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frontend/config/feature_flags.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/services/api_operations.dart';
import 'package:frontend/services/pos_mirror_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class DailyCloseDialog extends StatefulWidget {
  const DailyCloseDialog({
    super.key,
    required this.branchId,
    required this.posId,
  });

  final String branchId;
  final String posId;

  @override
  State<DailyCloseDialog> createState() => _DailyCloseDialogState();
}

class _DailyCloseDialogState extends State<DailyCloseDialog> {
  bool _isLoadingSummary = true;
  bool _isClosing = false;
  bool _closed = false;
  String? _error;

  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _closeResult;

  final _notesController = TextEditingController();
  final _fuelController = TextEditingController();
  final _foodController = TextEditingController();
  final _transferController = TextEditingController();
  final _specialController = TextEditingController();
  final _tailDiscountController = TextEditingController();
  final _finalSummaryController = TextEditingController();
  final _specialNoteController = TextEditingController();
  Timer? _broadcastTimer;

  @override
  void initState() {
    super.initState();
    _notesController.addListener(_scheduleBroadcast);
    for (final controller in _expenseControllers) {
      controller.addListener(_scheduleBroadcast);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSummary());
  }

  @override
  void dispose() {
    _broadcastTimer?.cancel();
    _notesController.removeListener(_scheduleBroadcast);
    _notesController.dispose();
    for (final controller in _expenseControllers) {
      controller.removeListener(_scheduleBroadcast);
      controller.dispose();
    }
    PosMirrorService.current?.notifyDialogState(null);
    super.dispose();
  }

  List<TextEditingController> get _expenseControllers => [
    _fuelController,
    _foodController,
    _transferController,
    _specialController,
    _tailDiscountController,
    _finalSummaryController,
    _specialNoteController,
  ];

  void _scheduleBroadcast() {
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer(const Duration(milliseconds: 300), _broadcastState);
  }

  void _broadcastState() {
    final summary = _summary ?? _closeResult ?? {};
    PosMirrorService.current?.notifyDialogState({
      'type': 'daily_close',
      'stage': _closed ? 'closed' : (_isLoadingSummary ? 'loading' : 'summary'),
      'alreadyClosed': summary['alreadyClosed'] == true,
      'notes': _notesController.text.trim(),
      'fuelAmount': _parseOptionalAmount(_fuelController.text),
      'foodAmount': _parseOptionalAmount(_foodController.text),
      'transferAmount': _parseOptionalAmount(_transferController.text),
      'specialAmount': _parseOptionalAmount(_specialController.text),
      'tailDiscountAmount': _parseOptionalAmount(_tailDiscountController.text),
      'finalSummaryAmount': _parseOptionalAmount(_finalSummaryController.text),
      'specialNote': _specialNoteController.text.trim(),
      'summary': {
        'totalSales': _toDouble(summary['totalSales']),
        'totalCash': _toDouble(summary['totalCash']),
        'totalTransfer': _toDouble(summary['totalTransfer']),
        'totalCreditTerm': _toDouble(summary['totalCreditTerm']),
        'totalBills': summary['totalBills'] ?? 0,
        'totalReturns': _toDouble(summary['totalReturns']),
        'netAmount': _toDouble(summary['netAmount']),
      },
    });
  }

  Future<void> _loadSummary() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) {
      setState(() {
        _error = 'ไม่พบ token กรุณา login ใหม่';
        _isLoadingSummary = false;
      });
      return;
    }

    if (widget.branchId.isEmpty || widget.posId.isEmpty) {
      setState(() {
        _error = 'ไม่พบข้อมูลสาขา/POS ไม่สามารถดึงสรุปยอดได้';
        _isLoadingSummary = false;
      });
      return;
    }

    setState(() {
      _isLoadingSummary = true;
      _error = null;
    });

    try {
      final summary = await ApiOperationsService.getDailyCloseSummary(
        token: token,
        branchId: widget.branchId,
        posId: widget.posId,
      );
      if (mounted) {
        setState(() {
          _summary = summary;
          _isLoadingSummary = false;
        });
        _broadcastState();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoadingSummary = false;
        });
      }
    }
  }

  Future<void> _doClose() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันปิดยอดวันนี้'),
        content: const Text('ต้องการปิดยอดประจำวันนี้หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('ปิดยอด'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _isClosing = true;
      _error = null;
    });

    try {
      final result = await ApiOperationsService.createDailyClose(
        token: token,
        branchId: widget.branchId,
        posId: widget.posId,
        notes: _notesController.text.trim(),
        fuelAmount: _parseOptionalAmount(_fuelController.text),
        foodAmount: _parseOptionalAmount(_foodController.text),
        transferAmount: _parseOptionalAmount(_transferController.text),
        specialAmount: _parseOptionalAmount(_specialController.text),
        tailDiscountAmount: _parseOptionalAmount(_tailDiscountController.text),
        finalSummaryAmount: _parseOptionalAmount(_finalSummaryController.text),
        specialNote: _specialNoteController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _closeResult = result;
          _closed = true;
          _isClosing = false;
        });
        _broadcastState();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isClosing = false;
        });
      }
    }
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  double? _parseOptionalAmount(String raw) {
    final cleaned = raw.replaceAll(',', '').trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.radius),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.soft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text(
                    'ปิดยอดประจำวัน',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'ปิด',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _isLoadingSummary
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null && !_closed
                      ? _buildError()
                      : _closed
                      ? _buildSuccess()
                      : _buildSummaryForm(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 48),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.danger),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _loadSummary, child: const Text('ลองใหม่')),
        ],
      ),
    );
  }

  Widget _buildSummaryForm() {
    final summary = _summary ?? {};
    final alreadyClosed = summary['alreadyClosed'] == true;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (alreadyClosed)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.4),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.accent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ปิดยอดแล้ววันนี้',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _buildSummaryTable(summary),
          if (!alreadyClosed) ...[
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'หมายเหตุ (ไม่บังคับ)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            // "ข้อมูลเพิ่มเติม / ค่าใช้จ่าย" section hidden by request.
            // _buildExpenseSection(),
            ElevatedButton(
              onPressed: _isClosing ? null : _doClose,
              child: _isClosing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('ปิดยอด'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryTable(Map<String, dynamic> summary) {
    final rows = [
      _SummaryRow(
        'ยอดขายรวม',
        '฿${_toDouble(summary['totalSales']).toStringAsFixed(2)}',
        bold: true,
      ),
      _SummaryRow(
        'เงินสด',
        '฿${_toDouble(summary['totalCash']).toStringAsFixed(2)}',
      ),
      _SummaryRow(
        'โอนเงิน/QR',
        '฿${_toDouble(summary['totalTransfer']).toStringAsFixed(2)}',
      ),
      // "เงินเซ็น" (credit term) is hidden when the credit system is disabled.
      if (kEnableCreditTerm)
        _SummaryRow(
          'เงินเซ็น',
          '฿${_toDouble(summary['totalCreditTerm']).toStringAsFixed(2)}',
        ),
      _SummaryRow('จำนวนบิล', '${(summary['totalBills'] ?? 0)} ใบ'),
      _SummaryRow(
        'ยอดคืนสินค้า',
        '฿${_toDouble(summary['totalReturns']).toStringAsFixed(2)}',
        color: AppColors.danger,
      ),
      _SummaryRow(
        'ยอดสุทธิ',
        '฿${_toDouble(summary['netAmount']).toStringAsFixed(2)}',
        bold: true,
        color: AppColors.primary,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: rows
            .map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      r.label,
                      style: TextStyle(
                        color: r.bold ? AppColors.text : AppColors.muted,
                        fontWeight: r.bold ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    Text(
                      r.value,
                      style: TextStyle(
                        color:
                            r.color ??
                            (r.bold ? AppColors.text : AppColors.text),
                        fontWeight: r.bold ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildExpenseSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ข้อมูลเพิ่มเติม / ค่าใช้จ่าย',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _amountField(_fuelController, 'น้ำมัน', 'เช่น 2000'),
              _amountField(_foodController, 'อาหาร', 'เช่น 150'),
              _amountField(_transferController, 'ยอดโอน', 'เช่น 9900'),
              _amountField(_specialController, 'รายการพิเศษ', 'เช่น 180'),
              _amountField(_tailDiscountController, 'ลดปลาย', 'เช่น 18'),
              _amountField(_finalSummaryController, 'สรุปยอด', 'เช่น 18492'),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _specialNoteController,
            decoration: const InputDecoration(
              labelText: 'หมายเหตุรายการพิเศษ (ไม่บังคับ)',
              hintText: 'เช่น บูท 1x20 = 20\nรวม 180',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: 4,
          ),
        ],
      ),
    );
  }

  Widget _amountField(
    TextEditingController controller,
    String label,
    String hint,
  ) {
    return SizedBox(
      width: 200,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: '$label (ไม่บังคับ)',
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
          prefixText: '฿ ',
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      ),
    );
  }

  Widget _buildSuccess() {
    final result = _closeResult ?? {};
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green, size: 28),
              SizedBox(width: 8),
              Text(
                'ปิดยอดสำเร็จ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSummaryTable(result),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ปิด'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await context.read<AuthProvider>().logout();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (r) => false,
              );
            },
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('ออกจากระบบเพื่อสลับกะ'),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow {
  const _SummaryRow(this.label, this.value, {this.bold = false, this.color});
  final String label;
  final String value;
  final bool bold;
  final Color? color;
}
