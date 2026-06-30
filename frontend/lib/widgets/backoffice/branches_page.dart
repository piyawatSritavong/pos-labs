import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/theme/app_theme.dart';

class BranchesManagementSection extends StatefulWidget {
  const BranchesManagementSection({super.key});

  @override
  State<BranchesManagementSection> createState() =>
      _BranchesManagementSectionState();
}

class _BranchesManagementSectionState extends State<BranchesManagementSection> {
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _branches = [];

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // โหลดสาขาทันทีเมื่อเปิดหน้า
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchBranches();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchBranches() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) {
      setState(() {
        _error = 'ไม่พบ token กรุณาเข้าสู่ระบบใหม่';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await ApiService.getBranches(
        token: token,
        limit: 100,
        offset: 0,
      );

      // ถ้ามี keyword ค้นหา ให้ filter ฝั่ง client
      final keyword = _searchController.text.trim().toLowerCase();
      List<Map<String, dynamic>> filtered = data;
      if (keyword.isNotEmpty) {
        filtered = data.where((b) {
          final id = (b['branchId'] ?? '').toString().toLowerCase();
          final name = (b['branchName'] ?? '').toString().toLowerCase();
          final nameTh = (b['branchNameTh'] ?? '').toString().toLowerCase();
          return id.contains(keyword) ||
              name.contains(keyword) ||
              nameTh.contains(keyword);
        }).toList();
      }

      if (!mounted) return;
      setState(() {
        _branches = filtered;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Suggest the next branch id (max existing numeric + 1, zero-padded to the
  // existing width, e.g. 00000 → 00001). Editable in the form; uniqueness is
  // enforced by the validator.
  String _nextBranchId() {
    var maxNum = -1;
    var width = 5;
    for (final b in _branches) {
      final id = (b['branchId'] ?? b['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      if (id.length > width) width = id.length;
      final n = int.tryParse(id);
      if (n != null && n > maxNum) maxNum = n;
    }
    return (maxNum + 1).toString().padLeft(width, '0');
  }

  Future<void> _openBranchForm({Map<String, dynamic>? branch}) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบ token กรุณาเข้าสู่ระบบใหม่')),
      );
      return;
    }

    final isEdit = branch != null;

    final branchIdController = TextEditingController(
      text: isEdit ? (branch['branchId']?.toString() ?? '') : _nextBranchId(),
    );
    final branchNameController = TextEditingController(
      text: branch?['branchName']?.toString() ?? '',
    );
    final branchNameThController = TextEditingController(
      text: branch?['branchNameTh']?.toString() ?? '',
    );
    final branchAddressController = TextEditingController(
      text: branch?['branchAddress']?.toString() ?? '',
    );
    final branchAddressThController = TextEditingController(
      text: branch?['branchAddressTh']?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: branch?['phone']?.toString() ?? '',
    );
    final emailController = TextEditingController(
      text: branch?['email']?.toString() ?? '',
    );

    bool isActive = (branch?['isActive'] as bool?) ?? true;

    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEdit ? 'แก้ไขสาขา' : 'สร้างสาขาใหม่'),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: branchIdController,
                      decoration: const InputDecoration(
                        labelText: 'Branch ID',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      readOnly: isEdit, // ไม่ให้แก้ branchId ตอนแก้ไข
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'กรุณากรอก Branch ID';
                        if (!isEdit &&
                            _branches.any((b) =>
                                (b['branchId'] ?? b['id'] ?? '')
                                    .toString()
                                    .trim() ==
                                v)) {
                          return 'Branch ID นี้มีอยู่แล้ว';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: branchNameController,
                      decoration: const InputDecoration(
                        labelText: 'Branch Name (EN)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'กรุณากรอกชื่อสาขา (EN)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: branchNameThController,
                      decoration: const InputDecoration(
                        labelText: 'Branch Name (TH)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: branchAddressController,
                      decoration: const InputDecoration(
                        labelText: 'Address (EN)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: branchAddressThController,
                      decoration: const InputDecoration(
                        labelText: 'ที่อยู่ (TH)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      title: const Text('Active'),
                      contentPadding: EdgeInsets.zero,
                      value: isActive,
                      onChanged: (v) {
                        isActive = v;
                        // ต้องใช้ setState ของ Dialog
                        (context as Element).markNeedsBuild();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                try {
                  if (isEdit) {
                    await ApiService.updateBranch(
                      token: token,
                      branchId: branchIdController.text.trim(),
                      branchName: branchNameController.text.trim(),
                      branchNameTh: branchNameThController.text.trim(),
                      address: branchAddressController.text.trim(),
                      addressTh: branchAddressThController.text.trim(),
                      phone: phoneController.text.trim(),
                      email: emailController.text.trim(),
                      isActive: isActive,
                    );
                  } else {
                    await ApiService.createBranch(
                      token: token,
                      branchId: branchIdController.text.trim(),
                      branchName: branchNameController.text.trim(),
                      branchNameTh: branchNameThController.text.trim(),
                      address: branchAddressController.text.trim(),
                      addressTh: branchAddressThController.text.trim(),
                      phone: phoneController.text.trim(),
                      email: emailController.text.trim(),
                      isActive: isActive,
                    );
                  }

                  if (!mounted) return;
                  Navigator.of(context).pop(true);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
                  );
                }
              },
              child: Text(isEdit ? 'บันทึก' : 'สร้าง'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await _fetchBranches();
    }
  }

  Future<void> _confirmDeleteBranch(Map<String, dynamic> branch) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบ token กรุณาเข้าสู่ระบบใหม่')),
      );
      return;
    }

    final branchId = branch['branchId']?.toString() ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('ยืนยันการลบสาขา'),
          content: Text('คุณต้องการลบสาขา "$branchId" ใช่หรือไม่?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('ลบ'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      await ApiService.deleteBranch(token: token, branchId: branchId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ลบสาขา $branchId สำเร็จ')));
      await _fetchBranches();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ลบสาขาไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: double.infinity),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // แถวบน: ปุ่ม + Search
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      _openBranchForm();
                    },
                    icon: const Icon(Icons.add_business),
                    label: const Text('เพิ่มสาขาใหม่'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _fetchBranches,
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
                        hintText: 'ค้นหา Branch ID / Name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) {
                        _fetchBranches();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ส่วนหลัก: Card + DataTable
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
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                        ? Center(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          )
                        : _branches.isEmpty
                        ? const Center(child: Text('ยังไม่มีข้อมูลสาขา'))
                        : SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowHeight: 44,
                                dataRowMinHeight: 44,
                                dataRowMaxHeight: 56,
                                columnSpacing: 24,
                                columns: const [
                                  DataColumn(label: Text('Branch ID')),
                                  DataColumn(label: Text('Name (EN)')),
                                  DataColumn(label: Text('Name (TH)')),
                                  DataColumn(label: Text('Phone')),
                                  DataColumn(label: Text('Active')),
                                  DataColumn(label: Text('Actions')),
                                ],
                                rows: _branches.map((b) {
                                  final branchId =
                                      (b['branchId'] ?? b['id'] ?? '')
                                          .toString();
                                  final nameEn = (b['branchName'] ?? '')
                                      .toString();
                                  final nameTh = (b['branchNameTh'] ?? '')
                                      .toString();
                                  final phone = (b['phone'] ?? '').toString();
                                  final isActive =
                                      (b['isActive'] as bool?) ?? true;

                                  return DataRow(
                                    cells: [
                                      DataCell(Text(branchId)),
                                      DataCell(Text(nameEn)),
                                      DataCell(Text(nameTh)),
                                      DataCell(Text(phone)),
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
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.edit),
                                              tooltip: 'แก้ไขสาขา',
                                              onPressed: () {
                                                _openBranchForm(branch: b);
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete),
                                              tooltip: 'ลบสาขา',
                                              onPressed: () {
                                                _confirmDeleteBranch(b);
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
            ],
          ),
        ),
      ),
    );
  }
}
