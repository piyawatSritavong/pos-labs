import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_operations.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class VehicleInventoryPage extends StatefulWidget {
  const VehicleInventoryPage({super.key});
  @override
  State<VehicleInventoryPage> createState() => _VehicleInventoryPageState();
}

class _VehicleInventoryPageState extends State<VehicleInventoryPage> {
  List<Map<String, dynamic>> _positions = [];
  String? _posId;
  late DateTime _from;
  late DateTime _to;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _report;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, now.day);
    _to = _from;
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    final token = context.read<AuthProvider>().token ?? '';
    try {
      final all = await ApiService.getPosDevices(token: token);
      _positions = all
          .where(
            (p) =>
                p['isActive'] != false &&
                p['vehicleStoreId']?.toString() != 'main',
          )
          .toList();
      _posId = _positions.isEmpty
          ? null
          : _positions.first['posId']?.toString();
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _load() async {
    if (_posId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final token = context.read<AuthProvider>().token ?? '';
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await ApiOperationsService.getVehicleInventory(
        token: token,
        posId: _posId!,
        dateFrom: _date(_from),
        dateTo: _date(_to),
      );
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(bool from) async {
    final initial = from ? _from : _to;
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value == null) return;
    setState(() {
      if (from) {
        _from = value;
        if (_to.isBefore(_from)) _to = value;
      } else {
        _to = value;
      }
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = (_report?['items'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final summary = _report?['summary'] as Map<String, dynamic>? ?? {};
    final table = SingleChildScrollView(
      child: DataTable(
        columns: const [
          DataColumn(label: Text('รหัสสินค้า')),
          DataColumn(label: Text('ชื่อสินค้า')),
          DataColumn(label: Text('Barcode')),
          DataColumn(label: Text('คงเหลือ')),
          DataColumn(label: Text('เบิกเข้า')),
          DataColumn(label: Text('ขายสุทธิ')),
          DataColumn(label: Text('ราคาขาย')),
          DataColumn(label: Text('มูลค่าคงเหลือ')),
        ],
        rows: items
            .map(
              (item) => DataRow(
                cells: [
                  DataCell(Text(item['partCode']?.toString() ?? '')),
                  DataCell(
                    Text(
                      (item['partNameTh'] ?? item['partName'] ?? '').toString(),
                    ),
                  ),
                  DataCell(Text(item['barCode']?.toString() ?? '')),
                  DataCell(Text(item['currentQty']?.toString() ?? '0')),
                  DataCell(Text(item['receivedQty']?.toString() ?? '0')),
                  DataCell(Text(item['netSoldQty']?.toString() ?? '0')),
                  DataCell(Text(_money(item['price']))),
                  DataCell(Text(_money(item['currentSaleValue']))),
                ],
              ),
            )
            .toList(),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                initialValue:
                    _positions.any((p) => p['posId']?.toString() == _posId)
                    ? _posId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'รถ / POS',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _positions
                    .map(
                      (p) => DropdownMenuItem(
                        value: p['posId']?.toString(),
                        child: Text(
                          '${p['posName'] ?? p['posId']} (${p['posId']})',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() => _posId = value);
                  _load();
                },
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _pick(true),
              icon: const Icon(Icons.calendar_today),
              label: Text('จาก ${_date(_from)}'),
            ),
            OutlinedButton.icon(
              onPressed: () => _pick(false),
              icon: const Icon(Icons.event),
              label: Text('ถึง ${_date(_to)}'),
            ),
            IconButton(
              onPressed: _load,
              tooltip: 'รีเฟรช',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SummaryCard(
              'คงเหลือปัจจุบัน',
              '${summary['currentQty'] ?? 0} ชิ้น',
            ),
            _SummaryCard(
              'เบิกเข้าช่วงที่เลือก',
              '${summary['receivedQty'] ?? 0} ชิ้น',
            ),
            _SummaryCard(
              'ขายสุทธิหลังหักคืน',
              '${summary['netSoldQty'] ?? 0} ชิ้น',
            ),
            _SummaryCard(
              'มูลค่าสต๊อกราคาขาย',
              _money(summary['currentSaleValue']),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Card(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                ? const Center(child: Text('ไม่พบรายการสต๊อกรถ'))
                : table,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 230,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    ),
  );
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _money(dynamic value) =>
    '฿${(double.tryParse(value?.toString() ?? '') ?? 0).toStringAsFixed(2)}';
