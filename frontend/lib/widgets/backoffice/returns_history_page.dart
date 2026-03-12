import 'package:flutter/material.dart';
import 'package:frontend/services/return_note_storage.dart';
import 'package:frontend/theme/app_theme.dart';

class ReturnsHistorySection extends StatefulWidget {
  const ReturnsHistorySection({super.key});

  @override
  State<ReturnsHistorySection> createState() => _ReturnsHistorySectionState();
}

class _ReturnsHistorySectionState extends State<ReturnsHistorySection> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _notes = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _notes = ReturnNoteStorage.loadNotes();
    });
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
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('โหลดข้อมูล'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: filtered.isEmpty
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
                            note['purchaseTotal'],
                          );
                          final returnTotal = _toDouble(
                            note['returnCreditTotal'],
                          );
                          final netTotal = _toDouble(note['netTotal']);
                          final mode =
                              note['settlementMode']?.toString() ?? 'none';
                          final lines = (note['lines'] is List)
                              ? (note['lines'] as List).length
                              : 0;

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
                                    Text('วิธีปิดรายการ: $mode'),
                                    Text('รายการคืน: $lines รายการ'),
                                  ],
                                ),
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
