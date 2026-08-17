import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_operations.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/backoffice/restock_review_dialog.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
  String? _error;
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
      _error = null;
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
      if (mounted) setState(() => _error = e.toString());
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
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _approve() async {
    final id = _selected?['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final token = context.read<AuthProvider>().token ?? '';
    setState(() {
      _acting = true;
      _error = null;
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
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _reviewItems() async {
    final request = _selected;
    if (request == null) return;
    final token = context.read<AuthProvider>().token ?? '';
    final updated = await showRestockReviewDialog(
      context,
      token: token,
      request: request,
    );
    if (!mounted || updated == null) return;
    setState(() => _selected = updated);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('บันทึกการตรวจสอบแล้ว')));
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
      if (mounted) setState(() => _error = e.toString());
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
    await _printRestockPdf(_selected!);
  }

  Future<void> _openDailySummary() async {
    final request = _selected;
    if (request == null) return;
    final posId = request['targetPosId']?.toString() ?? '';
    if (posId.isEmpty) {
      setState(() => _error = 'เอกสารนี้ไม่มี POS ปลายทาง');
      return;
    }
    final rawDate = request['completedAt'] ?? request['createdAt'];
    final parsed =
        DateTime.tryParse(rawDate?.toString() ?? '')?.toLocal() ??
        DateTime.now();
    final date =
        '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
    final token = context.read<AuthProvider>().token ?? '';
    setState(() => _acting = true);
    try {
      final summary = await ApiOperationsService.getVehicleDailySummary(
        token: token,
        posId: posId,
        date: date,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _DailyRestockSummary(summary: summary),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _acting = false);
    }
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
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.danger),
            ),
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
              if (status == 'completed')
                OutlinedButton.icon(
                  onPressed: _acting ? null : _openDailySummary,
                  icon: const Icon(Icons.summarize_outlined, size: 16),
                  label: const Text('สรุปใบเบิกทั้งวัน'),
                ),
              if (canApprove)
                OutlinedButton.icon(
                  onPressed: _acting ? null : _reviewItems,
                  icon: const Icon(Icons.edit_note, size: 16),
                  label: const Text('แก้ไขจำนวน / หมายเหตุ'),
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
              _docField('POS / รถปลายทาง', request['targetPosId']),
              _docField('ต้นทาง', 'คลังหลัก'),
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
              4: FixedColumnWidth(70),
              5: FixedColumnWidth(70),
              6: FixedColumnWidth(100),
              7: FixedColumnWidth(110),
            },
            children: [
              _tableRow(const [
                'ลำดับ',
                'รหัสสินค้า',
                'Barcode',
                'ชื่อสินค้า',
                'จำนวน',
                'หน่วย',
                'ราคาขาย',
                'รวม',
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
                  _issuedQtyLabel(item),
                  item['unit']?.toString() ?? '',
                  _money(item['salePrice']),
                  _money(item['lineTotal']),
                  item['remarks']?.toString() ?? '',
                ]);
              }),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'ยอดรวมราคาขาย ${_money(request['totalSaleValue'])}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
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

class _DailyRestockSummary extends StatelessWidget {
  const _DailyRestockSummary({required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final documents = (summary['documents'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final pos = summary['pos'] as Map<String, dynamic>? ?? {};
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 850),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'สรุปใบเบิกสินค้าเข้ารถประจำวัน',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _printDailyRestockPdf(summary),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('พิมพ์ / บันทึก PDF'),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                'วันที่ ${summary['date'] ?? ''}   รถ ${pos['posName'] ?? pos['posId'] ?? ''} (${pos['posId'] ?? ''})',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    for (final document in documents) ...[
                      Text(
                        'เลขที่ ${document['id'] ?? ''} • อนุมัติ ${_shortDate(document['completedAt'])}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Table(
                        border: TableBorder.all(color: AppColors.border),
                        columnWidths: const {
                          0: FixedColumnWidth(110),
                          2: FixedColumnWidth(70),
                          3: FixedColumnWidth(100),
                          4: FixedColumnWidth(110),
                        },
                        children: [
                          _tableRow(const [
                            'รหัสสินค้า',
                            'ชื่อสินค้า',
                            'จำนวน',
                            'ราคาขาย',
                            'ยอดรวม',
                          ], header: true),
                          for (final item
                              in (document['items'] as List? ?? [])
                                  .whereType<Map<String, dynamic>>())
                            _tableRow([
                              item['partCode']?.toString() ?? '',
                              (item['partNameTh'] ?? item['partName'] ?? '')
                                  .toString(),
                              item['requestedQty']?.toString() ?? '0',
                              _money(item['salePrice']),
                              _money(item['lineTotal']),
                            ]),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'รวมใบนี้ ${_money(document['totalSaleValue'])}',
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'ยอดรวมทั้งวัน ${_money(summary['grandTotalSaleValue'])}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    const Row(
                      children: [
                        Expanded(
                          child: _SignatureBox(label: 'ลงชื่อพนักงานผู้รับ'),
                        ),
                        SizedBox(width: 48),
                        Expanded(
                          child: _SignatureBox(label: 'ลงชื่อ Admin / HQ'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

/// The quantity that actually goes out: what HQ approved during review, or the
/// request when nobody changed it. Both are shown when they differ — a slip
/// that hides the correction is the problem this feature exists to fix.
String _issuedQtyLabel(Map<String, dynamic> item) {
  final requested = (item['requestedQty'] as num?)?.toInt() ?? 0;
  final approved = (item['approvedQty'] as num?)?.toInt();
  if (approved == null || approved == requested) return '$requested';
  return '$approved (ขอ $requested)';
}

String _money(dynamic value) =>
    '฿${(double.tryParse(value?.toString() ?? '') ?? 0).toStringAsFixed(2)}';

Future<pw.Font> _loadThaiPdfFont() async =>
    pw.Font.ttf(await rootBundle.load('assets/fonts/Sarabun-Regular.ttf'));

Future<void> _printRestockPdf(Map<String, dynamic> request) async {
  final font = await _loadThaiPdfFont();
  final document = pw.Document(
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
  final items = (request['items'] as List? ?? [])
      .whereType<Map<String, dynamic>>()
      .toList();
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => [
        pw.Center(
          child: pw.Text(
            'ใบเบิกสินค้าเข้ารถ',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 18),
        pw.Wrap(
          spacing: 26,
          runSpacing: 8,
          children: [
            pw.Text('เลขที่ใบเบิก: ${request['id'] ?? ''}'),
            pw.Text(
              'วันที่: ${_shortDate(request['completedAt'] ?? request['createdAt'])}',
            ),
            pw.Text('POS / รถ: ${request['targetPosId'] ?? ''}'),
            pw.Text('ต้นทาง: คลังหลัก'),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: const [
            '#',
            'รหัสสินค้า',
            'Barcode',
            'ชื่อสินค้า',
            'จำนวน',
            'ราคาขาย',
            'รวม',
            'หมายเหตุ',
          ],
          data: [
            for (var index = 0; index < items.length; index++)
              [
                '${index + 1}',
                items[index]['partCode'] ?? '',
                items[index]['barCode'] ?? '',
                items[index]['partNameTh'] ?? items[index]['partName'] ?? '',
                _issuedQtyLabel(items[index]),
                _money(items[index]['salePrice']),
                _money(items[index]['lineTotal']),
                items[index]['remarks'] ?? '',
              ],
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignment: pw.Alignment.centerLeft,
        ),
        pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'ยอดรวมราคาขาย ${_money(request['totalSaleValue'])}',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 48),
        _pdfSignatures(const [
          'ลงชื่อผู้เบิก',
          'ลงชื่อผู้ตรวจสอบ/HQ',
          'ลงชื่อผู้อนุมัติ',
        ]),
      ],
    ),
  );
  await Printing.layoutPdf(
    name: 'vehicle-restock-${request['id'] ?? 'document'}.pdf',
    onLayout: (_) => document.save(),
  );
}

Future<void> _printDailyRestockPdf(Map<String, dynamic> summary) async {
  final font = await _loadThaiPdfFont();
  final document = pw.Document(
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
  final documents = (summary['documents'] as List? ?? [])
      .whereType<Map<String, dynamic>>()
      .toList();
  final pos = summary['pos'] as Map<String, dynamic>? ?? {};
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => [
        pw.Center(
          child: pw.Text(
            'สรุปใบเบิกสินค้าเข้ารถประจำวัน',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'วันที่ ${summary['date'] ?? ''}   รถ ${pos['posName'] ?? pos['posId'] ?? ''} (${pos['posId'] ?? ''})',
        ),
        pw.SizedBox(height: 18),
        for (final restock in documents) ...[
          pw.Text(
            'เลขที่ ${restock['id'] ?? ''} • อนุมัติ ${_shortDate(restock['completedAt'])}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: const [
              'รหัสสินค้า',
              'ชื่อสินค้า',
              'จำนวน',
              'ราคาขาย',
              'ยอดรวม',
            ],
            data: [
              for (final item
                  in (restock['items'] as List? ?? [])
                      .whereType<Map<String, dynamic>>())
                [
                  item['partCode'] ?? '',
                  item['partNameTh'] ?? item['partName'] ?? '',
                  item['requestedQty'] ?? 0,
                  _money(item['salePrice']),
                  _money(item['lineTotal']),
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('รวมใบนี้ ${_money(restock['totalSaleValue'])}'),
          ),
          pw.SizedBox(height: 16),
        ],
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'ยอดรวมทั้งวัน ${_money(summary['grandTotalSaleValue'])}',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 52),
        _pdfSignatures(const ['ลงชื่อพนักงานผู้รับ', 'ลงชื่อ Admin / HQ']),
      ],
    ),
  );
  await Printing.layoutPdf(
    name:
        'vehicle-restock-${summary['date'] ?? 'daily'}-${pos['posId'] ?? ''}.pdf',
    onLayout: (_) => document.save(),
  );
}

pw.Widget _pdfSignatures(List<String> labels) => pw.Row(
  children: [
    for (var index = 0; index < labels.length; index++) ...[
      if (index > 0) pw.SizedBox(width: 18),
      pw.Expanded(
        child: pw.Column(
          children: [
            pw.Container(height: 1, color: PdfColors.grey600),
            pw.SizedBox(height: 6),
            pw.Text(labels[index]),
          ],
        ),
      ),
    ],
  ],
);
