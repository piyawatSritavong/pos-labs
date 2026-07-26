import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_operations.dart';
import 'package:frontend/services/pos_mirror_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class PhysicalCountDialog extends StatefulWidget {
  const PhysicalCountDialog({
    super.key,
    required this.branchId,
    required this.storeId,
  });

  final String branchId;
  final String storeId;

  @override
  State<PhysicalCountDialog> createState() => _PhysicalCountDialogState();
}

class _PhysicalCountDialogState extends State<PhysicalCountDialog> {
  bool _isCreating = true;
  bool _isSaving = false;
  bool _isSubmitting = false;
  bool _submitted = false;
  String? _error;

  String? _countId;
  List<Map<String, dynamic>> _items = [];
  Map<String, TextEditingController> _controllers = {};

  Map<String, dynamic>? _varianceReport;
  Timer? _broadcastTimer;
  Future<void> Function()? _retryAction;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _createCount());
  }

  @override
  void dispose() {
    _broadcastTimer?.cancel();
    for (final c in _controllers.values) {
      c.removeListener(_scheduleBroadcast);
      c.dispose();
    }
    PosMirrorService.current?.notifyDialogState(null);
    super.dispose();
  }

  void _scheduleBroadcast() {
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer(const Duration(milliseconds: 300), _broadcastState);
  }

  void _broadcastState() {
    PosMirrorService.current?.notifyDialogState({
      'type': 'physical_count',
      'stage': _submitted
          ? 'variance'
          : (_isCreating ? 'creating' : 'counting'),
      'countId': _countId ?? '',
      'items': _items.map((item) {
        final code = item['partCode']?.toString() ?? '';
        final systemQty = _toDouble(item['systemQty'] ?? item['system_qty']);
        final counted =
            double.tryParse(_controllers[code]?.text.trim() ?? '') ?? systemQty;
        return {
          'partCode': code,
          'partName':
              item['partNameTh']?.toString() ??
              item['partName']?.toString() ??
              code,
          'systemQty': systemQty,
          'countedQty': counted,
        };
      }).toList(),
      if (_varianceReport != null) 'varianceReport': _varianceReport,
    });
  }

  Future<void> _createCount() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) {
      setState(() {
        _error = 'ไม่พบ token กรุณา login ใหม่';
        _isCreating = false;
      });
      return;
    }

    if (widget.branchId.isEmpty) {
      setState(() {
        _error = 'ไม่พบข้อมูลสาขา ไม่สามารถเริ่มนับสต็อกได้';
        _isCreating = false;
      });
      return;
    }

    setState(() {
      _isCreating = true;
      _error = null;
    });

    try {
      final result = await ApiOperationsService.createStockCount(
        token: token,
        branchId: widget.branchId,
        storeId: widget.storeId,
      );

      final id =
          result['id']?.toString() ?? result['countId']?.toString() ?? '';
      if (id.isEmpty) {
        throw Exception('ไม่ได้รับ count ID จาก backend');
      }

      final detail = await ApiOperationsService.getStockCount(
        token: token,
        id: id,
      );

      final rawItems = detail['items'];
      final items = rawItems is List
          ? rawItems.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];

      final controllers = <String, TextEditingController>{};
      for (final item in items) {
        final code = item['partCode']?.toString() ?? '';
        final systemQty = (item['systemQty'] ?? item['system_qty'] ?? 0)
            .toString();
        controllers[code] = TextEditingController(text: systemQty);
      }

      if (mounted) {
        for (final c in controllers.values) {
          c.addListener(_scheduleBroadcast);
        }
        setState(() {
          _countId = id;
          _items = items;
          _controllers = controllers;
          _isCreating = false;
          _retryAction = null;
        });
        _broadcastState();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e
              .toString()
              .replaceFirst('Exception: ', '')
              .replaceFirst('FormatException: ', '');
          _isCreating = false;
          _retryAction = _createCount;
        });
      }
    }
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  Future<void> _save() async {
    final token = context.read<AuthProvider>().token;
    if (token == null || _countId == null) return;

    setState(() {
      _isSaving = true;
      _error = null;
      _retryAction = null;
    });

    try {
      final changedItems = <Map<String, dynamic>>[];
      for (final item in _items) {
        final code = item['partCode']?.toString() ?? '';
        final controller = _controllers[code];
        if (controller == null) continue;
        final counted = int.tryParse(controller.text.trim());
        if (counted == null || counted < 0) {
          throw const FormatException(
            'จำนวนนับจริงต้องเป็นจำนวนเต็มตั้งแต่ 0 ขึ้นไป',
          );
        }
        final system = _toDouble(
          item['systemQty'] ?? item['system_qty'],
        ).toInt();
        if (counted != system) {
          changedItems.add({'partCode': code, 'countedQty': counted});
        }
      }

      if (changedItems.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ไม่มีรายการที่เปลี่ยนแปลง')),
          );
        }
        return;
      }

      await ApiOperationsService.updateStockCountItems(
        token: token,
        id: _countId!,
        items: changedItems,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('บันทึกรายการแล้ว')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e
              .toString()
              .replaceFirst('Exception: ', '')
              .replaceFirst('FormatException: ', '');
          _retryAction = _save;
        });
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _submit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการส่งนับสต็อก'),
        content: const Text(
          'เมื่อส่งแล้วจะไม่สามารถแก้ไขได้ ต้องการส่งยืนยันหรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('ส่งยืนยัน'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _performSubmit();
  }

  Future<void> _performSubmit() async {
    final token = context.read<AuthProvider>().token;
    if (token == null || _countId == null) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
      _retryAction = null;
    });

    var didSubmit = false;
    try {
      final allItems = <Map<String, dynamic>>[];
      for (final item in _items) {
        final code = item['partCode']?.toString() ?? '';
        final controller = _controllers[code];
        final rawCounted = controller?.text.trim() ?? '';
        final counted = int.tryParse(rawCounted);
        if (counted == null || counted < 0) {
          throw const FormatException(
            'จำนวนนับจริงต้องเป็นจำนวนเต็มตั้งแต่ 0 ขึ้นไป',
          );
        }
        allItems.add({'partCode': code, 'countedQty': counted});
      }

      await ApiOperationsService.submitStockCount(
        token: token,
        id: _countId!,
        items: allItems,
      );
      didSubmit = true;

      final variance = await ApiOperationsService.getStockVariance(
        token: token,
        countId: _countId!,
      );

      if (mounted) {
        setState(() {
          _varianceReport = variance;
          _submitted = true;
          _isSubmitting = false;
        });
        _broadcastState();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e
              .toString()
              .replaceFirst('Exception: ', '')
              .replaceFirst('FormatException: ', '');
          _isSubmitting = false;
          _submitted = didSubmit;
          _retryAction = didSubmit ? _loadVariance : _performSubmit;
        });
      }
    }
  }

  Future<void> _loadVariance() async {
    final token = context.read<AuthProvider>().token;
    if (token == null || _countId == null) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
      _retryAction = null;
    });
    try {
      final variance = await ApiOperationsService.getStockVariance(
        token: token,
        countId: _countId!,
      );
      if (!mounted) return;
      setState(() {
        _varianceReport = variance;
        _submitted = true;
        _isSubmitting = false;
      });
      _broadcastState();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _submitted = true;
        _isSubmitting = false;
        _retryAction = _loadVariance;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
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
            children: [
              Row(
                children: [
                  const Text(
                    'นับสต็อก',
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
                  child: _isCreating
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text('กำลังสร้างรอบนับสต็อก...'),
                            ],
                          ),
                        )
                      : _error != null
                      ? _buildError()
                      : _submitted
                      ? _buildVarianceReport()
                      : _buildItemList(),
                ),
              ),
              if (!_isCreating && !_submitted && _error == null) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_error != null)
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    OutlinedButton(
                      onPressed: (_isSaving || _isSubmitting) ? null : _save,
                      child: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('บันทึก'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: (_isSaving || _isSubmitting) ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('ส่งยืนยัน'),
                    ),
                  ],
                ),
              ],
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
          OutlinedButton(
            onPressed: _retryAction ?? _createCount,
            child: const Text('ลองใหม่'),
          ),
        ],
      ),
    );
  }

  Widget _buildItemList() {
    if (_items.isEmpty) {
      return const Center(child: Text('ไม่มีรายการสินค้าในรอบนับนี้'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: const [
              Expanded(
                flex: 4,
                child: Text(
                  'สินค้า',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: Text(
                  'จำนวนระบบ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: Text(
                  'นับจริง',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.separated(
            itemCount: _items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final item = _items[index];
              final code = item['partCode']?.toString() ?? '';
              final nameTh =
                  item['partNameTh']?.toString() ??
                  item['partName']?.toString() ??
                  code;
              final systemQty = _toDouble(
                item['systemQty'] ?? item['system_qty'],
              );
              final controller = _controllers[code];

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nameTh,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            code,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: Text(
                        systemQty.toStringAsFixed(
                          systemQty.truncateToDouble() == systemQty ? 0 : 2,
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: controller != null
                          ? TextField(
                              controller: controller,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                              ),
                            )
                          : const Text('-'),
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

  Widget _buildVarianceReport() {
    final varItems = _varianceReport?['items'];
    final items = varItems is List
        ? varItems.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    final withVariance = items.where((i) {
      final v = _toDouble(i['variance']);
      return v != 0;
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Colors.green,
              size: 24,
            ),
            const SizedBox(width: 8),
            const Text(
              'ส่งยืนยันสำเร็จ',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _StatChip(label: 'สินค้าทั้งหมด', value: '${items.length} รายการ'),
            const SizedBox(width: 8),
            _StatChip(
              label: 'มีความต่าง',
              value: '$withVariance รายการ',
              color: withVariance > 0 ? AppColors.danger : Colors.green,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: const [
                Expanded(
                  flex: 3,
                  child: Text(
                    'สินค้า',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: Text(
                    'ระบบ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: Text(
                    'นับจริง',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: Text(
                    'ต่าง',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final item = items[index];
                final code = item['partCode']?.toString() ?? '';
                final name =
                    item['partNameTh']?.toString() ??
                    item['partName']?.toString() ??
                    code;
                final system = _toDouble(item['systemQty']);
                final counted = _toDouble(item['countedQty']);
                final variance = _toDouble(item['variance']);
                final hasVariance = variance != 0;

                Color bgColor = AppColors.surface;
                Color varColor = AppColors.text;
                if (variance < 0) {
                  bgColor = AppColors.danger.withValues(alpha: 0.07);
                  varColor = AppColors.danger;
                } else if (variance > 0) {
                  bgColor = Colors.green.withValues(alpha: 0.07);
                  varColor = Colors.green;
                }

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hasVariance
                          ? (variance < 0
                                ? AppColors.danger.withValues(alpha: 0.3)
                                : Colors.green.withValues(alpha: 0.3))
                          : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              code,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 70,
                        child: Text(
                          system.toStringAsFixed(
                            system.truncateToDouble() == system ? 0 : 2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 70,
                        child: Text(
                          counted.toStringAsFixed(
                            counted.truncateToDouble() == counted ? 0 : 2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 70,
                        child: Text(
                          (variance >= 0 ? '+' : '') +
                              variance.toStringAsFixed(
                                variance.truncateToDouble() == variance ? 0 : 2,
                              ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: varColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ] else
          const Expanded(child: Center(child: Text('ไม่มีรายการความต่าง'))),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ปิด'),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color ?? AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}
