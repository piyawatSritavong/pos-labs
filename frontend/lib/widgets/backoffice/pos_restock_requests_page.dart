// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_operations.dart';
import 'package:frontend/services/app_dialog_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class PosRestockRequestsPage extends StatefulWidget {
  const PosRestockRequestsPage({super.key});

  @override
  State<PosRestockRequestsPage> createState() => _PosRestockRequestsPageState();
}

class _PosRestockRequestsPageState extends State<PosRestockRequestsPage> {
  static const _statuses = <String>[
    '',
    'draft',
    'review',
    'approved',
    'completed',
    'cancelled',
  ];

  String _selectedStatus = 'review';
  bool _loading = false;
  bool _acting = false;
  List<Map<String, dynamic>> _requests = [];
  Map<String, dynamic>? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().token ?? '';
    setState(() {
      _loading = true;
    });
    try {
      final list = await ApiOperationsService.getTransfers(
        token: token,
        transferMode: 'pos_restock',
        status: _selectedStatus.isEmpty ? null : _selectedStatus,
        limit: 200,
      );
      if (!mounted) return;
      setState(() => _requests = list);
      if (list.isNotEmpty) {
        await _select(list.first['id']?.toString() ?? '');
      } else {
        setState(() => _selected = null);
      }
    } catch (e) {
      if (mounted) {
        final retry = await AppDialogService.showError(
          context,
          error: e,
          fallback: 'โหลดรายการเบิกสินค้าไม่สำเร็จ',
          allowRetry: true,
        );
        if (retry && mounted) await _load();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(String id) async {
    if (id.isEmpty) return;
    final token = context.read<AuthProvider>().token ?? '';
    try {
      final detail = await ApiOperationsService.getTransfer(
        token: token,
        id: id,
      );
      if (mounted) setState(() => _selected = detail);
    } catch (e) {
      if (mounted) {
        await AppDialogService.showError(
          context,
          error: e,
          fallback: 'โหลดรายละเอียดรายการไม่สำเร็จ',
          allowRetry: true,
        );
      }
    }
  }

  Future<void> _approve() async {
    final id = _selected?['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final token = context.read<AuthProvider>().token ?? '';
    setState(() {
      _acting = true;
    });
    try {
      final updated = await ApiOperationsService.approveRestockTransfer(
        token: token,
        id: id,
      );
      if (!mounted) return;
      setState(() => _selected = updated);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ยืนยันโอนเข้ารถสำเร็จ')));
    } catch (e) {
      if (mounted) {
        await AppDialogService.showError(
          context,
          error: e,
          fallback: 'ยืนยันการโอนเข้ารถไม่สำเร็จ',
        );
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _cancel() async {
    final id = _selected?['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final token = context.read<AuthProvider>().token ?? '';
    setState(() => _acting = true);
    try {
      final updated = await ApiOperationsService.cancelTransfer(
        token: token,
        id: id,
      );
      if (!mounted) return;
      setState(() => _selected = updated);
      await _load();
    } catch (e) {
      if (mounted) {
        await AppDialogService.showError(
          context,
          error: e,
          fallback: 'ยกเลิกรายการไม่สำเร็จ',
        );
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _print() async {
    final id = _selected?['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final token = context.read<AuthProvider>().token ?? '';
    try {
      await ApiOperationsService.logTransferPrint(token: token, id: id);
    } catch (_) {
      // Best-effort audit only.
    }
    html.window.print();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final status in _statuses)
              ChoiceChip(
                label: Text(status.isEmpty ? 'ทั้งหมด' : _statusLabel(status)),
                selected: _selectedStatus == status,
                onSelected: (_) {
                  setState(() => _selectedStatus = status);
                  _load();
                },
              ),
            IconButton(
              tooltip: 'รีเฟรช',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 360, child: _buildList()),
              const SizedBox(width: 16),
              Expanded(child: _buildDetail()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_requests.isEmpty) {
      return const Center(
        child: Text('ไม่มีใบเบิก', style: TextStyle(color: AppColors.muted)),
      );
    }
    return ListView.separated(
      itemCount: _requests.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final request = _requests[index];
        final id = request['id']?.toString() ?? '';
        final selected = _selected?['id'] == id;
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _select(id),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        id,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    _StatusBadge(status: request['status']?.toString() ?? ''),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'POS/รถ: ${request['toStoreId'] ?? '-'}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                Text(
                  'วันที่: ${_shortDate(request['createdAt'])}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                if (request['isStale'] == true) ...[
                  const SizedBox(height: 6),
                  Text(
                    request['staleReason']?.toString() ?? 'ใบค้าง',
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetail() {
    final request = _selected;
    if (request == null) {
      return const Center(
        child: Text(
          'เลือกใบเบิกทางซ้าย',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    final status = request['status']?.toString() ?? '';
    final canApprove = status == 'review';
    final canCancel = status == 'draft' || status == 'review';
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _print,
                icon: const Icon(Icons.print_outlined, size: 16),
                label: const Text('Print / Save PDF'),
              ),
              if (canCancel)
                OutlinedButton.icon(
                  onPressed: _acting ? null : _cancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Cancel'),
                ),
              if (canApprove)
                FilledButton.icon(
                  onPressed: _acting ? null : _approve,
                  icon: const Icon(Icons.verified_outlined, size: 16),
                  label: const Text('ยืนยันโอนเข้ารถ'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _RestockDocument(request: request),
        ],
      ),
    );
  }
}

class _RestockDocument extends StatelessWidget {
  const _RestockDocument({required this.request});

  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final items = (request['items'] as List? ?? [])
        .whereType<Map<String, dynamic>>();
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text(
              'ใบเบิกสินค้าเข้ารถ',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            runSpacing: 8,
            spacing: 32,
            children: [
              _docField('เลขที่ใบเบิก', request['id']),
              _docField('วันที่สร้าง', _shortDate(request['createdAt'])),
              _docField('วันที่ Submit', _shortDate(request['submittedAt'])),
              _docField('สถานะเอกสาร', _statusLabel(request['status'])),
              _docField('POS / รถ / สาขาปลายทาง', request['toStoreId']),
              _docField('สาขาต้นทาง: โกดัง/HQ', request['fromStoreId']),
              _docField('ผู้สร้างใบเบิก', request['createdBy']),
            ],
          ),
          const SizedBox(height: 20),
          Table(
            border: TableBorder.all(color: AppColors.border),
            columnWidths: const {
              0: FixedColumnWidth(44),
              1: FixedColumnWidth(90),
              2: FixedColumnWidth(120),
              4: FixedColumnWidth(90),
              5: FixedColumnWidth(70),
              6: FixedColumnWidth(110),
            },
            children: [
              _tableRow(const [
                'ลำดับ',
                'รหัสสินค้า',
                'Barcode',
                'ชื่อสินค้า',
                'จำนวน',
                'หน่วย',
                'หมายเหตุ',
              ], header: true),
              ...items.toList().asMap().entries.map((entry) {
                final item = entry.value;
                return _tableRow([
                  '${entry.key + 1}',
                  item['partCode']?.toString() ?? '',
                  item['barCode']?.toString() ?? '',
                  item['partNameTh']?.toString().isNotEmpty == true
                      ? item['partNameTh'].toString()
                      : item['partName']?.toString() ?? '',
                  item['requestedQty']?.toString() ?? '',
                  item['unit']?.toString() ?? '',
                  '',
                ]);
              }),
            ],
          ),
          const SizedBox(height: 34),
          Row(
            children: const [
              Expanded(child: _SignatureBox(label: 'ลงชื่อผู้เบิก')),
              SizedBox(width: 16),
              Expanded(child: _SignatureBox(label: 'ลงชื่อผู้ตรวจสอบ/HQ')),
              SizedBox(width: 16),
              Expanded(child: _SignatureBox(label: 'ลงชื่อผู้อนุมัติ')),
            ],
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerRight,
            child: Text('วันที่ ____ / ____ / ______'),
          ),
        ],
      ),
    );
  }
}

class _SignatureBox extends StatelessWidget {
  const _SignatureBox({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 34),
        Container(height: 1, color: AppColors.border),
        const SizedBox(height: 8),
        Text(label),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'draft' => Colors.blueGrey,
      'review' => Colors.deepOrange,
      'completed' => Colors.green,
      'cancelled' => Colors.grey,
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

Widget _docField(String label, dynamic value) {
  return SizedBox(
    width: 280,
    child: RichText(
      text: TextSpan(
        style: const TextStyle(color: AppColors.text, fontSize: 13),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: value?.toString() ?? '-'),
        ],
      ),
    ),
  );
}

TableRow _tableRow(List<String> cells, {bool header = false}) {
  return TableRow(
    decoration: BoxDecoration(color: header ? AppColors.bg : Colors.white),
    children: [
      for (final cell in cells)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            cell,
            style: TextStyle(
              fontWeight: header ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
    ],
  );
}

String _statusLabel(dynamic status) {
  return switch (status?.toString() ?? '') {
    'draft' => 'Draft',
    'review' => 'รอ HQ ตรวจ',
    'approved' => 'Approved',
    'completed' => 'Completed',
    'cancelled' => 'Cancelled',
    '' => '-',
    final value => value,
  };
}

String _shortDate(dynamic value) {
  final text = value?.toString() ?? '';
  return text.length >= 10 ? text.substring(0, 10) : text;
}
