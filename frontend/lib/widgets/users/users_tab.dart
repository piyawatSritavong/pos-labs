import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/users_provider.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/users/create_user_dialog.dart';
import 'package:provider/provider.dart';
import 'package:frontend/services/app_dialog_service.dart';

class UsersTab extends StatefulWidget {
  const UsersTab({super.key, this.data});

  final List<Map<String, dynamic>>? data;

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUsersIfNeeded();
    });
  }

  Future<void> _loadUsersIfNeeded() async {
    final auth = context.read<AuthProvider>();
    final usersProvider = context.read<UsersProvider>();
    final token = auth.token;
    if (token == null) return;

    // โหลดข้อมูลจาก API ถ้า provider ว่าง
    if (usersProvider.users.isEmpty) {
      await usersProvider.loadUsers(token: token);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getUsersFromProvider(
    UsersProvider usersProvider,
  ) {
    // ใช้ UsersProvider เป็นหลัก เพื่อให้ UI อัพเดทเมื่อมีการเพิ่ม/ลบ
    if (usersProvider.users.isNotEmpty) {
      return usersProvider.users;
    }

    // Fallback to widget.data if provider is empty
    if (widget.data != null && widget.data!.isNotEmpty) {
      return widget.data!;
    }
    return [];
  }

  List<Map<String, dynamic>> _getFilteredUsers(UsersProvider usersProvider) {
    final users = _getUsersFromProvider(usersProvider);
    if (_searchQuery.isEmpty) return users;
    return users.where((user) {
      final name = (user['name']?.toString() ?? '').toLowerCase();
      final username = (user['username']?.toString() ?? '').toLowerCase();
      return name.contains(_searchQuery) || username.contains(_searchQuery);
    }).toList();
  }

  Future<void> _handleAddUser() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const CreateUserDialog(),
    );

    // Dialog returns true when user was created successfully
    // UsersProvider already refreshes the list after creating
    if (result == true && mounted) {
      setState(() {}); // Trigger rebuild to show new user
    }
  }

  Future<void> _handleUpdate(Map<String, dynamic> user) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditUserDialog(user: user),
    );

    if (result != null && mounted) {
      final auth = context.read<AuthProvider>();
      final usersProvider = context.read<UsersProvider>();
      final token = auth.token;
      if (token == null) return;

      try {
        await usersProvider.updateUser(
          token: token,
          userId: user['id']?.toString() ?? '',
          username: result['username'] ?? '',
          roleId: result['roleId'] ?? '',
          name: result['name'] ?? '',
          password: result['password'],
          isActive: result['isActive'],
        );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('อัพเดทผู้ใช้สำเร็จ')));
        }
      } catch (e) {
        if (mounted) {
          await AppDialogService.showError(
            context,
            error: e,
            fallback: 'อัปเดตผู้ใช้ไม่สำเร็จ',
          );
        }
      }
    }
  }

  Future<void> _handleDelete(Map<String, dynamic> user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ต้องการลบผู้ใช้ "${user['name']}" หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final auth = context.read<AuthProvider>();
      final usersProvider = context.read<UsersProvider>();
      final token = auth.token;
      if (token == null) return;

      try {
        await usersProvider.deleteUser(
          token: token,
          userId: user['id']?.toString() ?? '',
        );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('ลบผู้ใช้สำเร็จ')));
        }
      } catch (e) {
        if (mounted) {
          await AppDialogService.showError(
            context,
            error: e,
            fallback: 'ลบผู้ใช้ไม่สำเร็จ',
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UsersProvider>(
      builder: (context, usersProvider, _) {
        final filteredUsers = _getFilteredUsers(usersProvider);

        if (usersProvider.isLoading &&
            usersProvider.users.isEmpty &&
            (widget.data == null || widget.data!.isEmpty)) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ข้อมูลพนักงาน',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    onPressed: _handleAddUser,
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มผู้ใช้'),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'ค้นหาผู้ใช้...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ),

            // User Cards Grid
            filteredUsers.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(
                      child: Text(
                        'ไม่พบข้อมูลผู้ใช้',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                  )
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.35,
                        ),
                    itemCount: filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = filteredUsers[index];
                      return _UserCard(
                        user: user,
                        onUpdate: () => _handleUpdate(user),
                        onDelete: () => _handleDelete(user),
                      );
                    },
                  ),
          ],
        );
      },
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.onUpdate,
    required this.onDelete,
  });

  final Map<String, dynamic> user;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final userName = user['name']?.toString() ?? 'ไม่ทราบชื่อ';
    final username = user['username']?.toString() ?? '';
    final roleId =
        user['roleId']?.toString() ?? user['role_id']?.toString() ?? '-';
    final isActive = user['isActive'] != false;
    final isSuperuser = user['isSuperuser'] == true;

    // แปลง roleId เป็นชื่อที่อ่านง่าย
    String roleName;
    IconData roleIcon;
    Color roleColor;
    switch (roleId) {
      case 'role.admin':
        roleName = 'ผู้ดูแลระบบ';
        roleIcon = Icons.admin_panel_settings;
        roleColor = Colors.orange;
        break;
      case 'role.cashier':
        roleName = 'พนักงานขาย';
        roleIcon = Icons.point_of_sale;
        roleColor = Colors.blue;
        break;
      default:
        roleName = roleId;
        roleIcon = Icons.person;
        roleColor = Colors.grey;
    }

    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Avatar + Badge
            Row(
              children: [
                // Avatar
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [roleColor, roleColor.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                // Username badge
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.muted.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '@$username',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                      if (isSuperuser) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Superuser',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.purple,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Active Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isActive ? 'เปิด' : 'ปิด',
                        style: TextStyle(
                          fontSize: 11,
                          color: isActive ? Colors.green[700] : Colors.red[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // User Name
            Text(
              userName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 8),

            // Role
            Row(
              children: [
                Icon(roleIcon, size: 16, color: roleColor),
                const SizedBox(width: 6),
                Text(
                  roleName,
                  style: TextStyle(
                    fontSize: 13,
                    color: roleColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            const Spacer(),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onUpdate,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('แก้ไข'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('ลบ'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditUserDialog extends StatefulWidget {
  const _EditUserDialog({required this.user});

  final Map<String, dynamic> user;

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late TextEditingController _nameController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late String _selectedRole;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.user['name']?.toString() ?? '',
    );
    _usernameController = TextEditingController(
      text: widget.user['username']?.toString() ?? '',
    );
    _passwordController = TextEditingController();
    _selectedRole =
        widget.user['roleId']?.toString() ??
        widget.user['role_id']?.toString() ??
        'role.cashier';
    _isActive = widget.user['isActive'] != false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('แก้ไขผู้ใช้'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'ชื่อ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'รหัสผ่านใหม่ (เว้นว่างถ้าไม่ต้องการเปลี่ยน)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: const InputDecoration(
                labelText: 'สิทธิ์',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'role.admin',
                  child: Text('ผู้ดูแลระบบ (Admin)'),
                ),
                DropdownMenuItem(
                  value: 'role.cashier',
                  child: Text('พนักงานขาย (Cashier)'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedRole = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('เปิดใช้งาน'),
              value: _isActive,
              onChanged: (value) {
                setState(() {
                  _isActive = value;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, {
              'name': _nameController.text,
              'username': _usernameController.text,
              'password': _passwordController.text.isEmpty
                  ? null
                  : _passwordController.text,
              'roleId': _selectedRole,
              'isActive': _isActive,
            });
          },
          child: const Text('บันทึก'),
        ),
      ],
    );
  }
}
