import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:frontend/screens/backoffice_screen.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:http/http.dart' as http;

class PartsManagementSection extends StatelessWidget {
  const PartsManagementSection({super.key});

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
    final formKey = GlobalKey<FormState>();

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
                          labelText: 'รหัสสินค้า',
                          isDense: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'กรุณากรอกรหัสสินค้า';
                          }
                          return null;
                        },
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
                          labelText: 'หน่วย',
                          isDense: true,
                        ),
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
    final barcodeController = TextEditingController(
      text: part['barcode']?.toString() ?? '',
    );
    final unitController = TextEditingController(
      text: part['unit']?.toString() ?? '',
    );
    final priceValue = part['price'];
    final priceController = TextEditingController(
      text: priceValue is num
          ? priceValue.toStringAsFixed(2)
          : (priceValue?.toString() ?? ''),
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
                          labelText: 'หน่วย',
                          isDense: true,
                        ),
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

                            await partsProvider.fetchParts(token);

                            if (context.mounted) {
                              Navigator.of(dialogContext).pop(true);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('ลบสินค้าสำเร็จ')),
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
        constraints: const BoxConstraints(maxWidth: 1200),
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
                    onPressed: () {
                      if (token.isEmpty) return;
                      context.read<PartsProvider>().fetchParts(token);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('รีเฟรช'),
                  ),
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
                                    DataColumn(label: Text('ราคาขาย')),
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
                                    String priceText;
                                    if (priceValue is num) {
                                      priceText = priceValue.toStringAsFixed(2);
                                    } else {
                                      priceText = priceValue?.toString() ?? '';
                                    }

                                    return DataRow(
                                      cells: [
                                        DataCell(Text(code)),
                                        DataCell(Text(name)),
                                        DataCell(Text(receiptName)),
                                        DataCell(Text(barcode)),
                                        DataCell(Text(unit)),
                                        DataCell(Text('฿$priceText')),
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
            ],
          ),
        ),
      ),
    );
  }
}
