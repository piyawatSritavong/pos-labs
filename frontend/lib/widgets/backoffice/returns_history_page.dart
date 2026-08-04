import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/app_dialog_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class ReturnsHistorySection extends StatefulWidget {
  const ReturnsHistorySection({super.key});

  @override
  State<ReturnsHistorySection> createState() => _ReturnsHistorySectionState();
}

class _ReturnsHistorySectionState extends State<ReturnsHistorySection> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _notes = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final token = context.read<AuthProvider>().token;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      await AppDialogService.showError(
        context,
        error: Exception('missing_token'),
        fallback: 'กรุณาเข้าสู่ระบบอีกครั้ง',
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final notes = await ApiService.getReturnNotes(
        token: token,
        limit: 200,
        offset: 0,
        scope: 'branch',
        includeDetails: true,
      );
      if (!mounted) return;
      setState(() {
        _notes = notes;
      });
    } catch (e) {
      if (!mounted) return;
      final retry = await AppDialogService.showError(
        context,
        error: e,
        fallback: 'โหลดประวัติคืนสินค้าไม่สำเร็จ',
        allowRetry: true,
      );
      if (retry && mounted) await _reload();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$y-$m-$d $hh:$mm';
    } catch (_) {
      return raw;
    }
  }

  String _settlementLabel(String raw) {
    switch (raw) {
      case 'cash_refund':
        return 'คืนเงินสด';
      case 'customer_credit':
        return 'เก็บเป็นเครดิตลูกค้า';
      case 'exchange':
        return 'แลกเปลี่ยนสินค้า';
      default:
        return raw.isEmpty ? '-' : raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final term = _searchController.text.trim().toLowerCase();
    final filtered = _notes.where((note) {
      if (term.isEmpty) return true;
      final id = note['id']?.toString().toLowerCase() ?? '';
      final ref = note['referenceBillId']?.toString().toLowerCase() ?? '';
      return id.contains(term) || ref.contains(term);
    }).toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'ค้นหา Credit Note หรือเลขบิลอ้างอิง',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('โหลดข้อมูล'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                    ? const Center(child: Text('ยังไม่มีประวัติคืนของ'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: filtered.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final note = filtered[index];
                          final id = note['id']?.toString() ?? '-';
                          final ref =
                              note['referenceBillId']?.toString() ?? '-';
                          final createdAt = _formatDate(
                            note['createdAt']?.toString(),
                          );
                          final purchaseTotal = _toDouble(
                            note['purchaseAmount'],
                          );
                          final returnTotal = _toDouble(note['refundAmount']);
                          final netTotal = _toDouble(note['netAmount']);
                          final mode = note['settlementMode']?.toString() ?? '';
                          final lines = (note['details'] is List)
                              ? (note['details'] as List)
                                    .whereType<Map<String, dynamic>>()
                                    .toList()
                              : const <Map<String, dynamic>>[];

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.bg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      id,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'อ้างอิง $ref',
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      createdAt,
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 6,
                                  children: [
                                    Text(
                                      'ยอดซื้อใหม่: ฿${purchaseTotal.toStringAsFixed(2)}',
                                    ),
                                    Text(
                                      'ยอดคืน: -฿${returnTotal.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: AppColors.danger,
                                      ),
                                    ),
                                    Text(
                                      'สุทธิ: ${netTotal < 0 ? '-฿' : '฿'}${netTotal.abs().toStringAsFixed(2)}',
                                    ),
                                    Text(
                                      'วิธีปิดรายการ: ${_settlementLabel(mode)}',
                                    ),
                                    Text('รายการคืน: ${lines.length} รายการ'),
                                  ],
                                ),
                                if (lines.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: AppColors.border,
                                      ),
                                    ),
                                    child: Column(
                                      children: lines.map((line) {
                                        final name =
                                            line['name']?.toString() ??
                                            line['partCode']?.toString() ??
                                            'สินค้า';
                                        final qty = _toDouble(
                                          line['qty'],
                                        ).toInt();
                                        final lineTotal = _toDouble(
                                          line['lineTotal'],
                                        );
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(child: Text(name)),
                                              SizedBox(
                                                width: 60,
                                                child: Text(
                                                  'x$qty',
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                              SizedBox(
                                                width: 120,
                                                child: Text(
                                                  '฿${lineTotal.toStringAsFixed(2)}',
                                                  textAlign: TextAlign.right,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
