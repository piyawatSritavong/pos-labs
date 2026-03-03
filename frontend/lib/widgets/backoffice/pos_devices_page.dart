import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/backoffice_screen.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/services/api_service.dart';
import 'package:provider/provider.dart';

class PosManagementSection extends StatefulWidget {
  const PosManagementSection({super.key});

  @override
  State<PosManagementSection> createState() => _PosManagementSectionState();
}

class _PosManagementSectionState extends State<PosManagementSection> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filteredDevices(PosDevicesProvider provider) {
    final devices = provider.devices;
    if (_searchQuery.isEmpty) return devices;

    final q = _searchQuery.toLowerCase();
    return devices.where((d) {
      final posId = (d['posId'] ?? '').toString().toLowerCase();
      final posName = (d['posName'] ?? '').toString().toLowerCase();
      final branchId = (d['branchId'] ?? '').toString().toLowerCase();
      return posId.contains(q) || posName.contains(q) || branchId.contains(q);
    }).toList();
  }

  Future<void> _showCreatePosDialog(
    String token,
    PosDevicesProvider provider,
  ) async {
    final posIdController = TextEditingController();
    final branchIdController = TextEditingController();
    final posNameController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('สร้าง POS ใหม่'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: posIdController,
                  decoration: const InputDecoration(
                    labelText: 'POS ID',
                    hintText: 'เช่น POS001',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: posNameController,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อ POS',
                    hintText: 'เช่น เคาน์เตอร์หน้าร้าน',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: branchIdController,
                  decoration: const InputDecoration(
                    labelText: 'Branch ID',
                    hintText: 'เช่น 00000',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('ยกเลิก'),
            ),
            TextButton(
              onPressed: () async {
                final posId = posIdController.text.trim();
                final posName = posNameController.text.trim();
                final branchId = branchIdController.text.trim();

                if (posId.isEmpty || posName.isEmpty || branchId.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'กรุณากรอก POS ID, ชื่อ POS และ Branch ID ให้ครบ',
                      ),
                    ),
                  );
                  return;
                }

                try {
                  await ApiService.createPos(
                    token: token,
                    posId: posId,
                    branchId: branchId,
                    posName: posName,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('สร้าง POS "$posId" สำเร็จ')),
                  );
                  Navigator.of(dialogContext).pop(true);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('สร้าง POS ไม่สำเร็จ: $e')),
                  );
                }
              },
              child: const Text('บันทึก'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await provider.fetchDevices(token);
    }
  }

  Future<void> _togglePosActive(
    String token,
    String posId,
    PosDevicesProvider provider,
  ) async {
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบโทเคน กรุณาเข้าสู่ระบบใหม่')),
      );
      return;
    }
    try {
      await ApiService.togglePosActivate(token: token, posId: posId);
      if (!mounted) return;
      await provider.fetchDevices(token);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('อัปเดตสถานะ POS $posId เรียบร้อย')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ไม่สามารถอัปเดตสถานะ POS ได้: $e')),
      );
    }
  }

  Future<void> _showPosSecretDialog(String token, String posId) async {
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบโทเคน กรุณาเข้าสู่ระบบใหม่')),
      );
      return;
    }
    try {
      final secretData = await ApiService.getPosSecret(
        token: token,
        posId: posId,
      );
      final secret =
          (secretData['secret'] ??
                  secretData['posSecret'] ??
                  secretData['data'] ??
                  secretData.toString())
              .toString();

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('POS Secret ($posId)'),
            content: SelectableText(secret),
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    final refreshed = await ApiService.refreshPosSecret(
                      token: token,
                      posId: posId,
                    );
                    final newSecret =
                        (refreshed['secret'] ??
                                refreshed['posSecret'] ??
                                refreshed['data'] ??
                                refreshed.toString())
                            .toString();
                    if (!mounted) return;
                    Navigator.of(dialogContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('รีเฟรช secret ใหม่แล้ว: $newSecret'),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('รีเฟรช secret ไม่สำเร็จ: $e')),
                    );
                  }
                },
                child: const Text('รีเฟรช secret'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('ปิด'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ไม่สามารถดึง POS secret ได้: $e')),
      );
    }
  }

  Future<void> _confirmDeletePos(
    String token,
    String posId,
    PosDevicesProvider provider,
  ) async {
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบโทเคน กรุณาเข้าสู่ระบบใหม่')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('ยืนยันการลบ POS'),
          content: Text('คุณต้องการลบ POS $posId ใช่หรือไม่?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ยกเลิก'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ลบ'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      await ApiService.deletePos(token: token, posId: posId);
      if (!mounted) return;
      await provider.fetchDevices(token);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ลบ POS $posId เรียบร้อย')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ไม่สามารถลบ POS ได้: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final posProvider = context.watch<PosDevicesProvider>();
    final token = auth.token ?? '';

    final devices = _filteredDevices(posProvider);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: token.isEmpty
                        ? null
                        : () => _showCreatePosDialog(token, posProvider),
                    icon: const Icon(Icons.point_of_sale),
                    label: const Text('สร้าง POS ใหม่'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      if (token.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('ไม่พบโทเคน กรุณาเข้าสู่ระบบใหม่'),
                          ),
                        );
                        return;
                      }
                      posProvider.fetchDevices(token);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('รีเฟรช'),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'ค้นหา POS (ID, ชื่อ, สาขา)...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
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
                    child: posProvider.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowHeight: 44,
                              dataRowMinHeight: 44,
                              dataRowMaxHeight: 56,
                              columnSpacing: 24,
                              columns: const [
                                DataColumn(label: Text('POS ID')),
                                DataColumn(label: Text('ชื่อ POS')),
                                DataColumn(label: Text('สาขา')),
                                DataColumn(label: Text('Active')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: devices.isEmpty
                                  ? const [
                                      DataRow(
                                        cells: [
                                          DataCell(Text('-')),
                                          DataCell(Text('ยังไม่มีข้อมูล POS')),
                                          DataCell(Text('-')),
                                          DataCell(Text('-')),
                                          DataCell(Text('-')),
                                        ],
                                      ),
                                    ]
                                  : devices.map((d) {
                                      final posId =
                                          d['posId']?.toString() ?? '';
                                      final posName =
                                          d['posName']?.toString() ?? '';
                                      final branchId =
                                          d['branchId']?.toString() ?? '';
                                      final isActive = d['isActive'] == true;
                                      return DataRow(
                                        cells: [
                                          DataCell(Text(posId)),
                                          DataCell(Text(posName)),
                                          DataCell(Text(branchId)),
                                          DataCell(
                                            Icon(
                                              isActive
                                                  ? Icons.check_circle
                                                  : Icons.cancel,
                                              color: isActive
                                                  ? Colors.green
                                                  : Colors.grey,
                                            ),
                                          ),
                                          DataCell(
                                            Row(
                                              children: [
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.power_settings_new,
                                                  ),
                                                  tooltip: 'เปิด/ปิดใช้งาน',
                                                  onPressed: () =>
                                                      _togglePosActive(
                                                        token,
                                                        posId,
                                                        posProvider,
                                                      ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.vpn_key,
                                                  ),
                                                  tooltip: 'ดู/รีเซ็ต secret',
                                                  onPressed: () =>
                                                      _showPosSecretDialog(
                                                        token,
                                                        posId,
                                                      ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.delete,
                                                  ),
                                                  tooltip: 'ลบ POS',
                                                  onPressed: () =>
                                                      _confirmDeletePos(
                                                        token,
                                                        posId,
                                                        posProvider,
                                                      ),
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
            ],
          ),
        ),
      ),
    );
  }
}
