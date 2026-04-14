import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class MembersManagementSection extends StatefulWidget {
  const MembersManagementSection({super.key});

  @override
  State<MembersManagementSection> createState() =>
      _MembersManagementSectionState();
}

class _MembersManagementSectionState extends State<MembersManagementSection> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMembers());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    final token = context.read<AuthProvider>().token;
    if (token == null || token.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final query = _searchController.text.trim();
      final members = await ApiService.getMembers(
        token: token,
        limit: 200,
        offset: 0,
        query: query.isEmpty ? null : query,
      );
      if (!mounted) return;
      setState(() => _members = members);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('โหลดสมาชิกไม่สำเร็จ: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openMemberForm({Map<String, dynamic>? member}) async {
    final isEdit = member != null;
    final id = member?['id']?.toString() ?? '';
    final nameController = TextEditingController(
      text: member?['name']?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: member?['phone']?.toString() ?? '',
    );
    final emailController = TextEditingController(
      text: member?['email']?.toString() ?? '',
    );
    final pointsController = TextEditingController(
      text: member?['points']?.toString() ?? '0',
    );
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? 'แก้ไขสมาชิก' : 'เพิ่มสมาชิก'),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isEdit)
                        TextFormField(
                          enabled: false,
                          initialValue: id,
                          decoration: const InputDecoration(
                            labelText: 'Member ID',
                            isDense: true,
                          ),
                        ),
                      if (isEdit) const SizedBox(height: 8),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'ชื่อสมาชิก',
                          isDense: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'กรุณากรอกชื่อสมาชิก';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'เบอร์โทร',
                          isDense: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'กรุณากรอกเบอร์โทร';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'อีเมล',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: pointsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'คะแนน',
                          isDense: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final p = int.tryParse(value.trim());
                          if (p == null || p < 0) {
                            return 'คะแนนต้องเป็นจำนวนเต็ม >= 0';
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
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          final token = context.read<AuthProvider>().token;
                          if (token == null || token.isEmpty) return;

                          setDialogState(() => isSaving = true);
                          try {
                            final points =
                                int.tryParse(pointsController.text.trim()) ?? 0;
                            if (isEdit) {
                              await ApiService.updateMember(
                                token: token,
                                memberId: id,
                                name: nameController.text.trim(),
                                phone: phoneController.text.trim(),
                                email: emailController.text.trim(),
                                points: points,
                              );
                            } else {
                              await ApiService.createMember(
                                token: token,
                                name: nameController.text.trim(),
                                phone: phoneController.text.trim(),
                                email: emailController.text.trim(),
                                points: points,
                              );
                            }

                            if (!mounted) return;
                            Navigator.of(dialogContext).pop();
                            await _loadMembers();
                          } catch (e) {
                            if (!mounted) return;
                            setDialogState(() => isSaving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('บันทึกสมาชิกไม่สำเร็จ: $e'),
                              ),
                            );
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

  Future<void> _deleteMember(Map<String, dynamic> member) async {
    final id = member['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final token = context.read<AuthProvider>().token;
    if (token == null || token.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('ลบสมาชิก'),
          content: Text('ต้องการลบสมาชิก $id ใช่ไหม?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ลบ'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await ApiService.deleteMember(token: token, memberId: id);
      if (!mounted) return;
      await _loadMembers();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ลบสมาชิกแล้ว')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ลบสมาชิกไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText: 'ค้นหาสมาชิก (ชื่อ/เบอร์โทร/รหัส)',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _loadMembers(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _loadMembers,
                    icon: const Icon(Icons.refresh),
                    label: const Text('โหลดข้อมูล'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _openMemberForm(),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('เพิ่มสมาชิก'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Card(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _members.isEmpty
                      ? const Center(child: Text('ยังไม่มีข้อมูลสมาชิก'))
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: DataTable(
                            columnSpacing: 20,
                            columns: const [
                              DataColumn(label: Text('ID')),
                              DataColumn(label: Text('Code')),
                              DataColumn(label: Text('ชื่อ')),
                              DataColumn(label: Text('เบอร์โทร')),
                              DataColumn(label: Text('อีเมล')),
                              DataColumn(label: Text('คะแนน')),
                              DataColumn(label: Text('จัดการ')),
                            ],
                            rows: _members.map((m) {
                              return DataRow(
                                cells: [
                                  DataCell(Text(m['id']?.toString() ?? '-')),
                                  DataCell(Text(m['code']?.toString() ?? '-')),
                                  DataCell(Text(m['name']?.toString() ?? '-')),
                                  DataCell(Text(m['phone']?.toString() ?? '-')),
                                  DataCell(Text(m['email']?.toString() ?? '-')),
                                  DataCell(
                                    Text(m['points']?.toString() ?? '0'),
                                  ),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'แก้ไข',
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            color: AppColors.primary,
                                          ),
                                          onPressed: () =>
                                              _openMemberForm(member: m),
                                        ),
                                        IconButton(
                                          tooltip: 'ลบ',
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: AppColors.danger,
                                          ),
                                          onPressed: () => _deleteMember(m),
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
            ],
          ),
        ),
      ),
    );
  }
}
