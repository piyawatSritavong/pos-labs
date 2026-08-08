import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:frontend/screens/backoffice_screen.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/utils/store_summary.dart';
import 'package:frontend/widgets/backoffice/parts_import_dialog.dart';
import 'package:frontend/widgets/backoffice/purchase_orders_page.dart';
import 'package:http/http.dart' as http;

class PartsManagementSection extends StatefulWidget {
  const PartsManagementSection({super.key});

  @override
  State<PartsManagementSection> createState() => _PartsManagementSectionState();
}

class _PartsManagementSectionState extends State<PartsManagementSection> {
  String? _validateNonNegativePrice(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'กรุณากรอกราคา';
    }
    final parsed = double.tryParse(value.replaceAll(',', ''));
    if (parsed == null) return 'กรุณากรอกเป็นตัวเลข';
    if (parsed < 0) return 'ราคาต้องมากกว่าหรือเท่ากับ 0';
    return null;
  }

  @override
  void initState() {
    super.initState();
    // Auto-load the first page when the Parts screen opens. Previously the page
    // only fetched on manual refresh/search, so it usually appeared empty.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final token = context.read<AuthProvider>().token ?? '';
      if (token.isNotEmpty) {
        context.read<PartsProvider>().fetchParts(token);
      }
    });
  }

  Future<void> _showCreatePartDialog(
    BuildContext context,
    String token,
    PartsProvider partsProvider,
  ) async {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final barcodeController = TextEditingController();
    final unitController = TextEditingController();
    final priceController = TextEditingController();
    final costController = TextEditingController(text: '0.00');
    final minPriceController = TextEditingController();
    final shelfController = TextEditingController();
    final qtyController = TextEditingController();
    const selectedStoreId = 'main';
    final formKey = GlobalKey<FormState>();

    // รหัสสินค้า + บาร์โค้ดสร้างให้อัตโนมัติ (แก้ไขได้ก่อนบันทึก)
    try {
      final generated = await ApiService.generatePartCode(token);
      codeController.text = generated['code']?.toString() ?? '';
      barcodeController.text = generated['barCode']?.toString() ?? '';
    } catch (_) {
      // สร้างไม่ได้ก็ปล่อยว่าง — backend จะ gen ให้ตอนบันทึกอยู่ดี
    }
    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;

        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('เพิ่มสินค้าใหม่'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: codeController,
                        decoration: const InputDecoration(
                          labelText: 'รหัสสินค้า (สร้างอัตโนมัติ)',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'ชื่อสินค้า',
                          isDense: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'กรุณากรอกชื่อสินค้า';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: barcodeController,
                        decoration: const InputDecoration(
                          labelText: 'Barcode (สร้างอัตโนมัติ แก้ไขได้)',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: unitController,
                        decoration: const InputDecoration(
                          labelText: 'หน่วย (ไม่กรอก = ชิ้น)',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('รับสินค้าเข้าที่: คลังหลัก'),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: shelfController,
                        decoration: const InputDecoration(
                          labelText: 'ชั้นวาง (เช่น A-01)',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'จำนวนเริ่มต้น',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: costController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'ต้นทุน',
                          isDense: true,
                        ),
                        validator: _validateNonNegativePrice,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'ราคาขาย',
                          isDense: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'กรุณากรอกราคาขาย';
                          }
                          final parsed = double.tryParse(
                            value.replaceAll(',', ''),
                          );
                          if (parsed == null) {
                            return 'กรุณากรอกราคาขายเป็นตัวเลข';
                          }
                          if (parsed < 0) {
                            return 'ราคาขายต้องมากกว่าหรือเท่ากับ 0';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: minPriceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'ราคาลดได้ (ราคาขายขั้นต่ำ)',
                          hintText: 'ไม่กรอก = 90% ของราคาขายจริง',
                          isDense: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          return _validateNonNegativePrice(value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }
                          setState(() {
                            isSaving = true;
                          });

                          try {
                            final price = double.parse(
                              priceController.text.replaceAll(',', ''),
                            );
                            final cost = double.parse(
                              costController.text.replaceAll(',', ''),
                            );
                            final minPriceText = minPriceController.text
                                .replaceAll(',', '')
                                .trim();
                            final minPrice = minPriceText.isEmpty
                                ? price * 0.90
                                : double.parse(minPriceText);
                            if (minPrice > price) {
                              throw Exception(
                                'ราคาลดได้ต้องไม่สูงกว่าราคาขายจริง',
                              );
                            }

                            final uri = Uri.parse(
                              '${ApiService.baseUrl}/parts',
                            );
                            final response = await http.post(
                              uri,
                              headers: {
                                'Content-Type': 'application/json',
                                'Authorization': 'Bearer $token',
                              },
                              body: jsonEncode({
                                'code': codeController.text.trim(),
                                'name': nameController.text.trim(),
                                'barcode': barcodeController.text.trim(),
                                'unit': unitController.text.trim(),
                                'price': price,
                                'cost': cost,
                                'minPrice': minPrice,
                                'storeId': selectedStoreId,
                                'shelf': shelfController.text.trim(),
                                'qty':
                                    int.tryParse(qtyController.text.trim()) ??
                                    0,
                              }),
                            );

                            if (response.statusCode != 200 &&
                                response.statusCode != 201) {
                              throw Exception(
                                'สร้างสินค้าไม่สำเร็จ: '
                                '${response.statusCode} ${response.body}',
                              );
                            }

                            await partsProvider.fetchParts(token);

                            if (context.mounted) {
                              Navigator.of(dialogContext).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('เพิ่มสินค้าใหม่สำเร็จ'),
                                ),
                              );
                            }
                          } catch (e) {
                            setState(() {
                              isSaving = false;
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
                              );
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('บันทึก'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditPartDialog(
    BuildContext context,
    String token,
    PartsProvider partsProvider,
    Map<String, dynamic> part,
  ) async {
    final code = part['code']?.toString() ?? '';
    final nameController = TextEditingController(
      text: part['name']?.toString() ?? '',
    );
    // Backend ส่ง barcode มาเป็น camelCase `barCode`
    final barcodeController = TextEditingController(
      text: (part['barCode'] ?? part['barcode'])?.toString() ?? '',
    );
    // Backend ส่ง unit มาเป็น object {id, label, labelTh} — แก้ไขที่ตัว id
    // (เช่น pcs) ไม่ใช่ทั้งก้อน map
    final unitValue = part['unit'];
    final unitController = TextEditingController(
      text: unitValue is Map
          ? (unitValue['id']?.toString() ?? '')
          : (unitValue?.toString() ?? ''),
    );
    final priceValue = part['price'];
    final priceController = TextEditingController(
      text: priceValue is num
          ? priceValue.toStringAsFixed(2)
          : (priceValue?.toString() ?? ''),
    );
    final costValue = part['cost'];
    final costController = TextEditingController(
      text: costValue is num
          ? costValue.toStringAsFixed(2)
          : (costValue?.toString() ?? '0.00'),
    );
    final minPriceValue = part['minPrice'] ?? part['min_price'];
    final minPriceController = TextEditingController(
      text: minPriceValue is num
          ? minPriceValue.toStringAsFixed(2)
          : (minPriceValue?.toString() ?? ''),
    );
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;

        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: Text('แก้ไขสินค้า ($code)'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        enabled: false,
                        initialValue: code,
                        decoration: const InputDecoration(
                          labelText: 'รหัสสินค้า',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'ชื่อสินค้า',
                          isDense: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'กรุณากรอกชื่อสินค้า';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: barcodeController,
                        decoration: const InputDecoration(
                          labelText: 'Barcode',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: unitController,
                        decoration: const InputDecoration(
                          labelText: 'หน่วย (ไม่กรอก = ชิ้น)',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: costController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'ต้นทุน',
                          isDense: true,
                        ),
                        validator: _validateNonNegativePrice,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'ราคาขาย',
                          isDense: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'กรุณากรอกราคาขาย';
                          }
                          final parsed = double.tryParse(
                            value.replaceAll(',', ''),
                          );
                          if (parsed == null) {
                            return 'กรุณากรอกราคาขายเป็นตัวเลข';
                          }
                          if (parsed < 0) {
                            return 'ราคาขายต้องมากกว่าหรือเท่ากับ 0';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: minPriceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'ราคาลดได้ (ราคาขายขั้นต่ำ)',
                          isDense: true,
                        ),
                        validator: _validateNonNegativePrice,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }
                          setState(() {
                            isSaving = true;
                          });

                          try {
                            final price = double.parse(
                              priceController.text.replaceAll(',', ''),
                            );
                            final cost = double.parse(
                              costController.text.replaceAll(',', ''),
                            );
                            final minPrice = double.parse(
                              minPriceController.text.replaceAll(',', ''),
                            );
                            if (minPrice > price) {
                              throw Exception(
                                'ราคาลดได้ต้องไม่สูงกว่าราคาขายจริง',
                              );
                            }

                            final uri = Uri.parse(
                              '${ApiService.baseUrl}/parts/$code',
                            );
                            final response = await http.put(
                              uri,
                              headers: {
                                'Content-Type': 'application/json',
                                'Authorization': 'Bearer $token',
                              },
                              body: jsonEncode({
                                'name': nameController.text.trim(),
                                'barcode': barcodeController.text.trim(),
                                'unit': unitController.text.trim(),
                                'price': price,
                                'cost': cost,
                                'minPrice': minPrice,
                              }),
                            );

                            if (response.statusCode != 200) {
                              throw Exception(
                                'แก้ไขสินค้าไม่สำเร็จ: '
                                '${response.statusCode} ${response.body}',
                              );
                            }

                            await partsProvider.fetchParts(token);

                            if (context.mounted) {
                              Navigator.of(dialogContext).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('แก้ไขสินค้าสำเร็จ'),
                                ),
                              );
                            }
                          } catch (e) {
                            setState(() {
                              isSaving = false;
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
                              );
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('บันทึก'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeletePart(
    BuildContext context,
    String token,
    PartsProvider partsProvider,
    String code,
  ) async {
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        bool isDeleting = false;

        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('ยืนยันการลบสินค้า'),
              content: Text('คุณต้องการลบสินค้ารหัส "$code" ใช่หรือไม่?'),
              actions: [
                TextButton(
                  onPressed: isDeleting
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop(false);
                        },
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: isDeleting
                      ? null
                      : () async {
                          setState(() {
                            isDeleting = true;
                          });

                          try {
                            final uri = Uri.parse(
                              '${ApiService.baseUrl}/parts/$code',
                            );
                            final response = await http.delete(
                              uri,
                              headers: {
                                'Content-Type': 'application/json',
                                'Authorization': 'Bearer $token',
                              },
                            );

                            if (response.statusCode != 200 &&
                                response.statusCode != 204) {
                              throw Exception(
                                'ลบสินค้าไม่สำเร็จ: '
                                '${response.statusCode} ${response.body}',
                              );
                            }
                            var archived = false;
                            if (response.body.isNotEmpty) {
                              final decoded = jsonDecode(response.body);
                              archived =
                                  decoded is Map<String, dynamic> &&
                                  decoded['mode'] == 'archived';
                            }

                            await partsProvider.fetchParts(token);

                            if (context.mounted) {
                              Navigator.of(dialogContext).pop(true);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    archived
                                        ? 'นำสินค้าออกแล้ว โดยเก็บประวัติรายการเดิมไว้'
                                        : 'ลบสินค้าสำเร็จ',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            setState(() {
                              isDeleting = false;
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
                              );
                            }
                          }
                        },
                  child: isDeleting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('ลบ'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final partsProvider = context.watch<PartsProvider>();
    final token = auth.token ?? '';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: double.infinity),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Actions row
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      if (token.isEmpty) return;
                      _showCreatePartDialog(context, token, partsProvider);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มสินค้าใหม่'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: token.isEmpty
                        ? null
                        : () async {
                            // Captured before the awaits — the closure's own
                            // context is gone once the dialog has closed.
                            final messenger = ScaffoldMessenger.of(context);
                            final imported = await showPartsImportDialog(
                              context,
                              token,
                            );
                            if (!mounted || imported == null) return;
                            await partsProvider.fetchParts(token);
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(content: Text(imported.message)),
                            );
                          },
                    icon: const Icon(Icons.upload_file),
                    label: const Text('เพิ่มด้วยไฟล์'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: token.isEmpty
                        ? null
                        : () async {
                            final saved = await showCreatePurchaseOrderDialog(
                              context,
                            );
                            if (!mounted || !saved) return;
                            await partsProvider.fetchParts(token);
                          },
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('สร้างใบสั่งซื้อสินค้าเข้า'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      if (token.isEmpty) return;
                      context.read<PartsProvider>().fetchParts(token);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('รีเฟรช'),
                  ),
                  const SizedBox(width: 16),
                  const Chip(label: Text('คลังหลัก')),
                  const Spacer(),
                  SizedBox(
                    width: 320,
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'ค้นหาสินค้า (ชื่อ, code, barcode)...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (value) {
                        if (token.isEmpty) return;
                        final query = value.trim();
                        if (query.isEmpty) {
                          context.read<PartsProvider>().fetchParts(token);
                        } else {
                          context.read<PartsProvider>().search(
                            token,
                            query: query,
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Main card with table, expanded to fill height
              Expanded(
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.all(16.0),
                    child: partsProvider.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : partsProvider.parts.isEmpty
                        ? const Center(child: Text('ยังไม่มีข้อมูลสินค้า'))
                        : Scrollbar(
                            child: SingleChildScrollView(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingRowHeight: 44,
                                  dataRowMinHeight: 44,
                                  dataRowMaxHeight: 56,
                                  columnSpacing: 24,
                                  columns: const [
                                    DataColumn(label: Text('รหัสสินค้า')),
                                    DataColumn(label: Text('ชื่อสินค้า')),
                                    DataColumn(label: Text('ชื่อบนใบเสร็จ')),
                                    DataColumn(label: Text('Barcode')),
                                    DataColumn(label: Text('หน่วย')),
                                    DataColumn(label: Text('คลัง')),
                                    DataColumn(label: Text('ต้นทุน')),
                                    DataColumn(label: Text('ราคาขายจริง')),
                                    DataColumn(label: Text('ราคาลดได้')),
                                    DataColumn(label: Text('Actions')),
                                  ],
                                  rows: partsProvider.parts.map((p) {
                                    final code = p['code']?.toString() ?? '';
                                    // Prefer Thai name when available; backend returns both `name` and `nameTh`.
                                    final name =
                                        (p['nameTh']?.toString().isNotEmpty ==
                                                    true
                                                ? p['nameTh']
                                                : p['name'])
                                            ?.toString() ??
                                        '';
                                    final receiptName =
                                        p['receiptName']?.toString() ?? '';
                                    // Backend returns camelCase `barCode` (not `barcode`).
                                    final barcode =
                                        p['barCode']?.toString() ?? '';
                                    // Backend returns `unit` as an object {id, label, labelTh}.
                                    // Render the Thai label first, then English, then id.
                                    final unitMap = p['unit'];
                                    final unit = (unitMap is Map)
                                        ? ((unitMap['labelTh']
                                                              ?.toString()
                                                              .isNotEmpty ==
                                                          true
                                                      ? unitMap['labelTh']
                                                      : (unitMap['label']
                                                                    ?.toString()
                                                                    .isNotEmpty ==
                                                                true
                                                            ? unitMap['label']
                                                            : unitMap['id']))
                                                  ?.toString() ??
                                              '')
                                        : (unitMap?.toString() ?? '');
                                    final priceValue = p['price'];
                                    String money(dynamic value) => value is num
                                        ? value.toStringAsFixed(2)
                                        : (value?.toString() ?? '');
                                    final priceText = money(priceValue);
                                    final costText = money(p['cost']);
                                    final minPriceText = money(
                                      p['minPrice'] ?? p['min_price'],
                                    );
                                    final storeText = formatPartStoreSummary(
                                      p['addresses'] as List?,
                                    );

                                    return DataRow(
                                      cells: [
                                        DataCell(Text(code)),
                                        DataCell(Text(name)),
                                        DataCell(Text(receiptName)),
                                        DataCell(Text(barcode)),
                                        DataCell(Text(unit)),
                                        DataCell(
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 220,
                                            ),
                                            child: Text(
                                              storeText,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 2,
                                            ),
                                          ),
                                        ),
                                        DataCell(Text('฿$costText')),
                                        DataCell(Text('฿$priceText')),
                                        DataCell(Text('฿$minPriceText')),
                                        DataCell(
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit),
                                                tooltip: 'แก้ไขสินค้า',
                                                onPressed: () {
                                                  if (token.isEmpty) return;
                                                  _showEditPartDialog(
                                                    context,
                                                    token,
                                                    partsProvider,
                                                    p,
                                                  );
                                                },
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete),
                                                tooltip: 'ลบสินค้า',
                                                onPressed: () {
                                                  if (token.isEmpty) return;
                                                  _confirmDeletePart(
                                                    context,
                                                    token,
                                                    partsProvider,
                                                    code,
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Server-side pagination: page-size filter + page-jump dropdown.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('แสดงหน้าละ'),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: partsProvider.pageSize,
                    items: const [20, 50, 100]
                        .map(
                          (s) => DropdownMenuItem(value: s, child: Text('$s')),
                        )
                        .toList(),
                    onChanged: partsProvider.isLoading
                        ? null
                        : (v) {
                            if (v != null) {
                              context.read<PartsProvider>().setPageSize(
                                token,
                                v,
                              );
                            }
                          },
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'ก่อนหน้า',
                    onPressed:
                        (partsProvider.isLoading || partsProvider.offset <= 0)
                        ? null
                        : () => context.read<PartsProvider>().prevPage(token),
                  ),
                  const Text('หน้า'),
                  const SizedBox(width: 6),
                  DropdownButton<int>(
                    value: partsProvider.currentPage.clamp(
                      1,
                      partsProvider.pageCount < 1 ? 1 : partsProvider.pageCount,
                    ),
                    items: [
                      for (
                        var p = 1;
                        p <=
                            (partsProvider.pageCount < 1
                                ? 1
                                : partsProvider.pageCount);
                        p++
                      )
                        DropdownMenuItem(value: p, child: Text('$p')),
                    ],
                    onChanged: partsProvider.isLoading
                        ? null
                        : (v) {
                            if (v != null) {
                              context.read<PartsProvider>().goToPage(token, v);
                            }
                          },
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '/ ${partsProvider.pageCount}  (${partsProvider.total} รายการ)',
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'ถัดไป',
                    onPressed:
                        (partsProvider.isLoading || !partsProvider.hasMore)
                        ? null
                        : () => context.read<PartsProvider>().nextPage(token),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
