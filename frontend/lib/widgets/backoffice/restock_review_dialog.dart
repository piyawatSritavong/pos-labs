import 'package:flutter/material.dart';
import 'package:frontend/services/api_operations.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/qty_stepper.dart';
import 'package:frontend/utils/pos_error_message.dart';

/// HQ checking a restock against the paper slip the van staff wrote by hand.
///
/// While both systems run side by side the two disagree often enough that the
/// reviewer needs to correct the quantity to what is actually going out — and
/// say why. The requested amount stays on screen next to the corrected one,
/// because the discrepancy is the thing being documented.
///
/// Returns the updated transfer when something was saved, otherwise null.
Future<Map<String, dynamic>?> showRestockReviewDialog(
  BuildContext context, {
  required String token,
  required Map<String, dynamic> request,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RestockReviewDialog(token: token, request: request),
  );
}

class _RestockReviewDialog extends StatefulWidget {
  const _RestockReviewDialog({required this.token, required this.request});

  final String token;
  final Map<String, dynamic> request;

  @override
  State<_RestockReviewDialog> createState() => _RestockReviewDialogState();
}

class _ReviewLine {
  _ReviewLine({
    required this.partCode,
    required this.name,
    required this.unit,
    required this.requestedQty,
    required this.approvedQty,
    required String remarks,
  }) : remarksController = TextEditingController(text: remarks);

  final String partCode;
  final String name;
  final String unit;
  final int requestedQty;
  int approvedQty;
  final TextEditingController remarksController;

  bool get changed => approvedQty != requestedQty;

  void dispose() => remarksController.dispose();
}

class _RestockReviewDialogState extends State<_RestockReviewDialog> {
  late final List<_ReviewLine> _lines;
  late final TextEditingController _notesController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(
      text: widget.request['notes']?.toString() ?? '',
    );
    _lines = (widget.request['items'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final requested = (item['requestedQty'] as num?)?.toInt() ?? 0;
          return _ReviewLine(
            partCode: item['partCode']?.toString() ?? '',
            name: item['partNameTh']?.toString().isNotEmpty == true
                ? item['partNameTh'].toString()
                : item['partName']?.toString() ?? '',
            unit: item['unit']?.toString() ?? '',
            requestedQty: requested,
            // A line nobody has corrected yet starts at what was asked for.
            approvedQty: (item['approvedQty'] as num?)?.toInt() ?? requested,
            remarks: item['remarks']?.toString() ?? '',
          );
        })
        .toList();
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    _notesController.dispose();
    super.dispose();
  }

  int get _changedCount => _lines.where((line) => line.changed).length;

  Future<void> _save() async {
    // A corrected line without a reason is the case this screen exists to
    // prevent: a month later nobody remembers why the numbers differ.
    final missingReason = _lines.firstWhere(
      (line) => line.changed && line.remarksController.text.trim().isEmpty,
      orElse: () => _ReviewLine(
        partCode: '',
        name: '',
        unit: '',
        requestedQty: 0,
        approvedQty: 0,
        remarks: '',
      ),
    );
    if (missingReason.partCode.isNotEmpty) {
      setState(
        () => _error =
            'กรุณาระบุหมายเหตุของ ${missingReason.name.isEmpty ? missingReason.partCode : missingReason.name} '
            'เพราะจำนวนไม่ตรงกับที่ขอเบิก',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ApiOperationsService.reviewRestockItems(
        token: widget.token,
        id: widget.request['id']?.toString() ?? '',
        items: [
          for (final line in _lines)
            {
              'partCode': line.partCode,
              'approvedQty': line.approvedQty,
              'remarks': line.remarksController.text.trim(),
            },
        ],
        notes: _notesController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = posErrorMessage(e);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('แก้ไขจำนวนตอนตรวจสอบ'),
      content: SizedBox(
        width: 720,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ใบเบิก ${widget.request['id'] ?? ''} · '
              'POS ${widget.request['targetPosId'] ?? '-'} · '
              '${_lines.length} รายการ',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 4),
            const Text(
              'จำนวนที่แก้จะถูกใช้เป็นยอดที่ตัดออกจากคลังจริง '
              'ส่วนจำนวนที่ขอเบิกเดิมยังเก็บไว้ในเอกสาร',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Scrollbar(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _lines.length,
                  separatorBuilder: (_, _) => const Divider(height: 12),
                  itemBuilder: (_, index) {
                    final line = _lines[index];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.name.isEmpty ? line.partCode : line.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${line.partCode} · ขอเบิก ${line.requestedQty} ${line.unit}',
                                style: TextStyle(
                                  color: line.changed
                                      ? AppColors.danger
                                      : AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        QtyStepper(
                          key: ValueKey('review-${line.partCode}'),
                          value: line.approvedQty,
                          compact: true,
                          onChanged: (v) =>
                              setState(() => line.approvedQty = v),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 4,
                          child: TextField(
                            controller: line.remarksController,
                            decoration: InputDecoration(
                              isDense: true,
                              border: const OutlineInputBorder(),
                              labelText: line.changed
                                  ? 'หมายเหตุ (ต้องระบุ)'
                                  : 'หมายเหตุ',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'หมายเหตุของทั้งใบ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _changedCount == 0
                      ? 'บันทึกหมายเหตุ'
                      : 'บันทึกการแก้ $_changedCount รายการ',
                ),
        ),
      ],
    );
  }
}
