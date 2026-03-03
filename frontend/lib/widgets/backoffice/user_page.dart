
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/providers/auth_provider.dart';

class UsersManagementSection extends StatefulWidget {
  const UsersManagementSection({super.key});

  @override
  State<UsersManagementSection> createState() => _UsersManagementSectionState();
}

class _UsersManagementSectionState extends State<UsersManagementSection> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  List<Map<String, dynamic>> _users = [];
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredUsers {
    if (_searchTerm.isEmpty) {
      return _users;
    }
    final term = _searchTerm.toLowerCase();
    return _users.where((u) {
      final username = (u['username'] ?? '').toString().toLowerCase();
      final name = (u['name'] ?? '').toString().toLowerCase();
      return username.contains(term) || name.contains(term);
    }).toList();
  }

  Future<void> _loadUsers() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;

    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบโทเคน กรุณาเข้าสู่ระบบใหม่')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final users = await ApiService.getUsers(token: token, limit: 200, offset: 0);
      if (!mounted) return;
      setState(() {
        _users = users;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('โหลดรายชื่อผู้ใช้ไม่สำเร็จ: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openUserForm({Map<String, dynamic>? user}) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;

    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบโทเคน กรุณาเข้าสู่ระบบใหม่')),
      );
      return;
    }

    final isEdit = user != null;

    final usernameController =
        TextEditingController(text: user != null ? '${user['username'] ?? ''}' : '');
    final nameController =
        TextEditingController(text: user != null ? '${user['name'] ?? ''}' : '');
    final roleIdController = TextEditingController(
      text: user != null
          ? '${user['roleId'] ?? user['role'] ?? ''}'
          : '',
    );
    final passwordController = TextEditingController();

    bool isActive = user == null
        ? true
        : (user['isActive'] is bool
            ? user['isActive'] as bool
            : (user['isActive']?.toString() == 'true'));
    bool isSuperuser = user == null
        ? false
        : (user['isSuperuser'] is bool
            ? user['isSuperuser'] as bool
            : (user['isSuperuser']?.toString() == 'true'));

    final shouldSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? 'แก้ไขผู้ใช้' : 'เพิ่มพนักงานใหม่'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'ชื่อ - นามสกุล',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: roleIdController,
                      decoration: const InputDecoration(
                        labelText: 'Role ID',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      decoration: InputDecoration(
                        labelText: isEdit ? 'รหัสผ่านใหม่ (ถ้าต้องการเปลี่ยน)' : 'รหัสผ่านเริ่มต้น',
                        border: const OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: isActive,
                      onChanged: (value) {
                        setDialogState(() {
                          isActive = value;
                        });
                      },
                      title: const Text('เปิดใช้งาน (Active)'),
                    ),
                    SwitchListTile(
                      value: isSuperuser,
                      onChanged: (value) {
                        setDialogState(() {
                          isSuperuser = value;
                        });
                      },
                      title: const Text('Superuser'),
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
                ElevatedButton(
                  onPressed: () {
                    if (usernameController.text.trim().isEmpty ||
                        nameController.text.trim().isEmpty ||
                        roleIdController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('กรุณากรอก Username, ชื่อ และ Role ให้ครบ'),
                        ),
                      );
                      return;
                    }

                    if (!isEdit && passwordController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('กรุณากำหนดรหัสผ่านเริ่มต้น'),
                        ),
                      );
                      return;
                    }

                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('บันทึก'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldSave != true) {
      usernameController.dispose();
      nameController.dispose();
      roleIdController.dispose();
      passwordController.dispose();
      return;
    }

    try {
      if (isEdit) {
        final userId = '${user?['id'] ?? user?['userId'] ?? ''}';
        if (userId.isEmpty) {
          throw Exception('ไม่พบรหัสผู้ใช้ (id/userId)');
        }

        await ApiService.updateUser(
          token: token,
          userId: userId,
          username: usernameController.text.trim(),
          roleId: roleIdController.text.trim(),
          name: nameController.text.trim(),
          password:
              passwordController.text.isEmpty ? null : passwordController.text,
          isActive: isActive,
          isSuperuser: isSuperuser,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('แก้ไขผู้ใช้สำเร็จ')),
        );
      } else {
        await ApiService.createUser(
          token: token,
          username: usernameController.text.trim(),
          roleId: roleIdController.text.trim(),
          name: nameController.text.trim(),
          password: passwordController.text,
          isActive: isActive,
          isSuperuser: isSuperuser,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('สร้างผู้ใช้ใหม่สำเร็จ')),
        );
      }

      await _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('บันทึกข้อมูลผู้ใช้ไม่สำเร็จ: $e')),
      );
    } finally {
      usernameController.dispose();
      nameController.dispose();
      roleIdController.dispose();
      passwordController.dispose();
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> user) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;

    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบโทเคน กรุณาเข้าสู่ระบบใหม่')),
      );
      return;
    }

    final passwordController = TextEditingController();

    final shouldReset = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('ตั้งรหัสผ่านใหม่'),
          content: TextField(
            controller: passwordController,
            decoration: const InputDecoration(
              labelText: 'รหัสผ่านใหม่',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () {
                if (passwordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('กรุณากำหนดรหัสผ่านใหม่'),
                    ),
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('บันทึก'),
            ),
          ],
        );
      },
    );

    if (shouldReset != true) {
      passwordController.dispose();
      return;
    }

    try {
      final userId = '${user['id'] ?? user['userId'] ?? ''}';
      if (userId.isEmpty) {
        throw Exception('ไม่พบรหัสผู้ใช้ (id/userId)');
      }

      final username = '${user['username'] ?? ''}';
      final roleId = '${user['roleId'] ?? user['role'] ?? ''}';
      final name = '${user['name'] ?? ''}';

      if (username.isEmpty || roleId.isEmpty || name.isEmpty) {
        throw Exception('ข้อมูลผู้ใช้ไม่ครบ (username/roleId/name)');
      }

      await ApiService.updateUser(
        token: token,
        userId: userId,
        username: username,
        roleId: roleId,
        name: name,
        password: passwordController.text,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ตั้งรหัสผ่านใหม่สำเร็จ')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ตั้งรหัสผ่านใหม่ไม่สำเร็จ: $e')),
      );
    } finally {
      passwordController.dispose();
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;

    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบโทเคน กรุณาเข้าสู่ระบบใหม่')),
      );
      return;
    }

    final username = '${user['username'] ?? ''}';

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('ยืนยันการลบผู้ใช้'),
          content:
              Text('คุณต้องการลบผู้ใช้ "$username" จริงหรือไม่? ไม่สามารถย้อนกลับได้'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ลบผู้ใช้'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    try {
      final userId = '${user['id'] ?? user['userId'] ?? ''}';
      if (userId.isEmpty) {
        throw Exception('ไม่พบรหัสผู้ใช้ (id/userId)');
      }

      await ApiService.deleteUser(token: token, userId: userId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ลบผู้ใช้สำเร็จ')),
      );

      await _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ลบผู้ใช้ไม่สำเร็จ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    onPressed: () => _openUserForm(),
                    icon: const Icon(Icons.person_add),
                    label: const Text('เพิ่มพนักงานใหม่'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _loadUsers,
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
                        hintText: 'ค้นหาผู้ใช้ (username, name)...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchTerm = value.trim();
                        });
                      },
                      onSubmitted: (value) {
                        setState(() {
                          _searchTerm = value.trim();
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_isLoading)
                          const LinearProgressIndicator(minHeight: 3),
                        if (_isLoading) const SizedBox(height: 8),
                        Expanded(
                          child: _buildTable(),
                        ),
                      ],
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

  Widget _buildTable() {
    if (_isLoading && _users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final users = _filteredUsers;

    if (users.isEmpty) {
      return const Center(child: Text('ไม่พบผู้ใช้'));
    }

    return SingleChildScrollView(
      child: DataTable(
        headingRowHeight: 44,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 56,
        columnSpacing: 24,
        columns: const [
          DataColumn(label: Text('Username')),
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Role')),
          DataColumn(label: Text('Active')),
          DataColumn(label: Text('Superuser')),
          DataColumn(label: Text('Actions')),
        ],
        rows: users.map((u) {
          final username = '${u['username'] ?? ''}';
          final name = '${u['name'] ?? ''}';
          final role = '${u['roleId'] ?? u['role'] ?? ''}';
          final isActive = u['isActive'] == true ||
              u['isActive']?.toString().toLowerCase() == 'true';
          final isSuperuser = u['isSuperuser'] == true ||
              u['isSuperuser']?.toString().toLowerCase() == 'true';

          return DataRow(
            cells: [
              DataCell(Text(username.isEmpty ? '-' : username)),
              DataCell(Text(name.isEmpty ? '-' : name)),
              DataCell(Text(role.isEmpty ? '-' : role)),
              DataCell(
                Icon(
                  isActive ? Icons.check_circle : Icons.cancel,
                  color: isActive ? Colors.green : Colors.grey,
                ),
              ),
              DataCell(
                Icon(
                  isSuperuser ? Icons.check_circle : Icons.cancel,
                  color: isSuperuser ? Colors.deepPurple : Colors.grey,
                ),
              ),
              DataCell(
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'แก้ไขผู้ใช้',
                      onPressed: () => _openUserForm(user: u),
                    ),
                    IconButton(
                      icon: const Icon(Icons.lock_reset),
                      tooltip: 'ตั้งรหัสผ่านใหม่',
                      onPressed: () => _resetPassword(u),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      tooltip: 'ลบผู้ใช้',
                      onPressed: () => _deleteUser(u),
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
