import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/providers/auth_provider.dart';

// ──────────────────────────────────────────────
// Permission definitions
// ──────────────────────────────────────────────

const _vanStaffDefaultPerms = {
  'perm.branch.read',
  'perm.parts.read',
  'perm.bills.read',
  'perm.bills.write',
  'perm.promotions.read',
  'perm.qr_image.read',
  'perm.members.read',
  'perm.members.write',
  'perm.transfers.read',
  'perm.transfers.write',
  'perm.stock_count.read',
  'perm.stock_count.write',
  'perm.daily_close.read',
  'perm.daily_close.write',
  'perm.reports_variance.read',
};

const _hqManagerDefaultPerms = {
  'perm.branch.read',
  'perm.users.read',
  'perm.users.write',
  'perm.users.delete',
  'perm.user_branch.read',
  'perm.user_branch.write',
  'perm.parts.read',
  'perm.parts.write',
  'perm.parts.delete',
  'perm.addresses.read',
  'perm.addresses.write',
  'perm.addresses.delete',
  'perm.promotions.read',
  'perm.promotions.write',
  'perm.promotions.delete',
  'perm.members.read',
  'perm.members.write',
  'perm.members.delete',
  'perm.bills.read',
  'perm.bills.write',
  'perm.qr_image.read',
  'perm.qr_image.write',
  'perm.reports_bill.read',
  'perm.reports_parts.read',
  'perm.reports_inventory.read',
  'perm.transfers.read',
  'perm.transfers.write',
  'perm.transfers.approve',
  'perm.stock_count.read',
  'perm.daily_close.read',
  'perm.cash_reconciliation.read',
  'perm.cash_reconciliation.write',
  'perm.reports_variance.read',
};

Set<String> _allPermIds() {
  final out = <String>{};
  for (final group in _permGroups) {
    for (final perm in group.$2) {
      out.add(perm.$1);
    }
  }
  return out;
}

Set<String> _defaultPermsForRole(String? roleId) {
  if (roleId == 'role.admin') return _allPermIds();
  if (roleId == 'role.hq_manager') return {..._hqManagerDefaultPerms};
  if (roleId == 'role.van_staff') return {..._vanStaffDefaultPerms};
  return {};
}

// Groups for checklist display
const _permGroups = [
  (
    'ขาย / บิล',
    [('perm.bills.read', 'อ่านบิล'), ('perm.bills.write', 'สร้าง/แก้ไขบิล')],
  ),
  (
    'สมาชิก',
    [
      ('perm.members.read', 'อ่านสมาชิก'),
      ('perm.members.write', 'สร้าง/แก้ไขสมาชิก'),
      ('perm.members.delete', 'ลบสมาชิก'),
    ],
  ),
  (
    'สินค้า (Parts)',
    [
      ('perm.parts.read', 'อ่านสินค้า'),
      ('perm.parts.write', 'แก้ไขสินค้า'),
      ('perm.parts.delete', 'ลบสินค้า'),
    ],
  ),
  (
    'ที่อยู่คลัง',
    [
      ('perm.addresses.read', 'อ่านที่อยู่คลัง'),
      ('perm.addresses.write', 'แก้ไขที่อยู่คลัง'),
      ('perm.addresses.delete', 'ลบที่อยู่คลัง'),
    ],
  ),
  (
    'โปรโมชัน',
    [
      ('perm.promotions.read', 'อ่านโปรโมชัน'),
      ('perm.promotions.write', 'แก้ไขโปรโมชัน'),
      ('perm.promotions.delete', 'ลบโปรโมชัน'),
    ],
  ),
  (
    'โอนสินค้า',
    [
      ('perm.transfers.read', 'อ่านใบโอน'),
      ('perm.transfers.write', 'สร้างใบโอน / รับสินค้า'),
      ('perm.transfers.approve', 'อนุมัติ / จัดส่งใบโอน'),
    ],
  ),
  (
    'นับสต๊อก',
    [
      ('perm.stock_count.read', 'อ่านการนับ'),
      ('perm.stock_count.write', 'บันทึกการนับ'),
    ],
  ),
  (
    'ปิดยอด',
    [
      ('perm.daily_close.read', 'อ่านการปิดยอด'),
      ('perm.daily_close.write', 'ปิดยอดประจำวัน'),
    ],
  ),
  (
    'รับเงิน / การเงิน',
    [
      ('perm.cash_reconciliation.read', 'อ่านการรับเงิน'),
      ('perm.cash_reconciliation.write', 'บันทึกการรับเงิน'),
      ('perm.qr_image.read', 'อ่าน QR Payment'),
      ('perm.qr_image.write', 'อัปโหลด QR Payment'),
    ],
  ),
  (
    'รายงาน',
    [
      ('perm.reports_bill.read', 'Export รายงานบิล'),
      ('perm.reports_parts.read', 'Export รายงานสินค้า'),
      ('perm.reports_inventory.read', 'Export รายงานสต๊อก'),
      ('perm.reports_variance.read', 'รายงาน Variance'),
    ],
  ),
];

String _roleLabel(String roleId) {
  switch (roleId) {
    case 'role.admin':
      return 'Admin';
    case 'role.hq_manager':
      return 'HQ Manager';
    case 'role.van_staff':
      return 'POS Staff';
    default:
      return roleId;
  }
}

// ──────────────────────────────────────────────
// Widget
// ──────────────────────────────────────────────

class UsersManagementSection extends StatefulWidget {
  const UsersManagementSection({super.key});

  @override
  State<UsersManagementSection> createState() => _UsersManagementSectionState();
}

class _UsersManagementSectionState extends State<UsersManagementSection> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _roles = [];
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
    if (_searchTerm.isEmpty) return _users;
    final term = _searchTerm.toLowerCase();
    return _users.where((u) {
      final username = (u['username'] ?? '').toString().toLowerCase();
      final name = (u['name'] ?? '').toString().toLowerCase();
      final branchLabel = _branchLabelById(
        (u['branchId'] ?? '').toString(),
      ).toLowerCase();
      return username.contains(term) ||
          name.contains(term) ||
          branchLabel.contains(term);
    }).toList();
  }

  String _branchKey(Map<String, dynamic> branch) {
    return (branch['branchId'] ?? branch['id'] ?? '').toString();
  }

  String _branchDisplay(Map<String, dynamic> branch) {
    final branchId = _branchKey(branch);
    final branchName =
        branch['branchNameTh']?.toString().trim().isNotEmpty == true
        ? branch['branchNameTh'].toString().trim()
        : branch['branchName']?.toString().trim() ?? '';
    if (branchId.isNotEmpty && branchName.isNotEmpty) {
      return '$branchId - $branchName';
    }
    if (branchId.isNotEmpty) {
      return branchId;
    }
    if (branchName.isNotEmpty) {
      return branchName;
    }
    return '-';
  }

  String _branchLabelById(String branchId) {
    if (branchId.isEmpty) return '-';
    for (final branch in _branches) {
      if (_branchKey(branch) == branchId) {
        return _branchDisplay(branch);
      }
    }
    return branchId;
  }

  Future<void> _syncUserPrimaryBranch({
    required String token,
    required String userId,
    required String branchId,
  }) async {
    final mappings = await ApiService.getUserBranches(
      token: token,
      userId: userId,
    );
    final existingBranchIds = mappings
        .map((m) => (m['branchId'] ?? m['branch_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    for (final existingBranchId in existingBranchIds) {
      if (existingBranchId == branchId) continue;
      await ApiService.deleteUserBranch(
        token: token,
        userId: userId,
        branchId: existingBranchId,
      );
    }

    if (!existingBranchIds.contains(branchId)) {
      await ApiService.createUserBranch(
        token: token,
        userId: userId,
        branchId: branchId,
      );
    }
  }

  Future<void> _loadUsers() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait<dynamic>([
        ApiService.getUsers(token: token, limit: 200, offset: 0),
        ApiService.getBranches(token: token, limit: 200, offset: 0),
        ApiService.getRoles(token: token),
      ]);
      final users = (results[0] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      final branches = (results[1] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      final roles = (results[2] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      if (!mounted) return;
      setState(() {
        _users = users;
        _branches = branches;
        _roles = roles;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('โหลดรายชื่อผู้ใช้ไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openUserForm({Map<String, dynamic>? user}) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) return;
    if (_branches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่พบข้อมูลสาขา ไม่สามารถจัดการผู้ใช้ได้'),
        ),
      );
      return;
    }

    final isEdit = user != null;

    // Base roles (Admin + POS Staff) + any custom roles already created, plus a
    // "create new role" entry (super admin only).
    const baseRoleIds = {
      'role.admin',
      'role.hq_manager',
      'role.cashier',
      'role.van_staff',
    };
    final customRoles = _roles
        .where((r) => !baseRoleIds.contains((r['id'] ?? '').toString()))
        .map(
          (r) => (
            (r['name'] ?? r['id'] ?? '').toString(),
            (r['id'] ?? '').toString(),
          ),
        )
        .toList();
    final availableRoles = <(String, String)>[
      if (auth.isSuperAdmin) ('Admin', 'role.admin'),
      ('POS Staff', 'role.van_staff'),
      ...customRoles,
      if (auth.isSuperAdmin) ('➕ สร้างบทบาทใหม่', '__new__'),
    ];

    final usernameController = TextEditingController(
      text: user != null ? '${user['username'] ?? ''}' : '',
    );
    final nameController = TextEditingController(
      text: user != null ? '${user['name'] ?? ''}' : '',
    );
    final passwordController = TextEditingController();
    final newRoleNameController = TextEditingController();

    bool isActive = user == null
        ? true
        : (user['isActive'] is bool
              ? user['isActive'] as bool
              : user['isActive']?.toString() == 'true');

    String? selectedRole = isEdit ? user['roleId']?.toString() : null;
    String? selectedBranchId = user?['branchId']?.toString();
    if (selectedBranchId == null || selectedBranchId.isEmpty) {
      selectedBranchId = auth.branchId?.isNotEmpty == true
          ? auth.branchId
          : _branchKey(_branches.first);
    }

    // Initialise permissions: from user's customPermissions if set, else role defaults
    final rawCustom = user?['customPermissions'];
    Set<String> selectedPermissions;
    if (rawCustom != null && rawCustom is List && rawCustom.isNotEmpty) {
      selectedPermissions = Set<String>.from(
        rawCustom.map((p) => p.toString()),
      );
    } else {
      selectedPermissions = _defaultPermsForRole(selectedRole);
    }

    // Only Super Admin can edit permissions
    final canEditPerms = auth.isSuperAdmin;

    final shouldSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? 'แก้ไขผู้ใช้' : 'เพิ่มพนักงานใหม่'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Username
                      TextField(
                        controller: usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Name
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'ชื่อ - นามสกุล',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Role dropdown
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'user_role_${selectedRole ?? ''}_${isEdit ? 'edit' : 'create'}',
                        ),
                        initialValue:
                            availableRoles.any((r) => r.$2 == selectedRole)
                            ? selectedRole
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'ตำแหน่ง (Role)',
                          border: OutlineInputBorder(),
                        ),
                        items: availableRoles
                            .map(
                              (r) => DropdownMenuItem(
                                value: r.$2,
                                child: Text(r.$1),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          setDialogState(() {
                            selectedRole = v;
                            // Reset permissions to role defaults when role changes
                            selectedPermissions = _defaultPermsForRole(v);
                          });
                        },
                      ),
                      if (selectedRole == '__new__') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: newRoleNameController,
                          decoration: const InputDecoration(
                            labelText: 'ชื่อบทบาทใหม่',
                            hintText: 'เช่น หัวหน้ากะ',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'ติ๊กสิทธิ์ที่ต้องการให้บทบาทนี้ด้านล่าง',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'user_branch_${selectedBranchId ?? ''}_${isEdit ? 'edit' : 'create'}',
                        ),
                        initialValue:
                            _branches.any(
                              (branch) =>
                                  _branchKey(branch) == selectedBranchId,
                            )
                            ? selectedBranchId
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'สาขาประจำ',
                          border: OutlineInputBorder(),
                        ),
                        items: _branches
                            .map(
                              (branch) => DropdownMenuItem<String>(
                                value: _branchKey(branch),
                                child: Text(_branchDisplay(branch)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => selectedBranchId = v),
                      ),
                      const SizedBox(height: 12),
                      // Password
                      TextField(
                        controller: passwordController,
                        decoration: InputDecoration(
                          labelText: isEdit
                              ? 'รหัสผ่านใหม่ (ถ้าต้องการเปลี่ยน)'
                              : 'รหัสผ่านเริ่มต้น',
                          border: const OutlineInputBorder(),
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 4),
                      // Active switch
                      SwitchListTile(
                        value: isActive,
                        onChanged: (v) => setDialogState(() => isActive = v),
                        title: const Text('เปิดใช้งาน (Active)'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      const Divider(),
                      // Permission checklist
                      Row(
                        children: [
                          const Icon(
                            Icons.security_outlined,
                            size: 16,
                            color: AppColors.muted,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'สิทธิ์การใช้งาน',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          if (canEditPerms && selectedRole != null)
                            TextButton(
                              onPressed: () => setDialogState(() {
                                selectedPermissions = _defaultPermsForRole(
                                  selectedRole,
                                );
                              }),
                              child: const Text(
                                'รีเซ็ต',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                      if (!canEditPerms)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'แสดงสิทธิ์ตาม role เริ่มต้น (แก้ไขได้โดย Super Admin เท่านั้น)',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.muted.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ..._permGroups.map((group) {
                        final groupName = group.$1;
                        final perms = group.$2;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 2),
                              child: Text(
                                groupName,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.muted,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            ...perms.map((perm) {
                              final permId = perm.$1;
                              final permLabel = perm.$2;
                              return CheckboxListTile(
                                value: selectedPermissions.contains(permId),
                                onChanged: canEditPerms
                                    ? (v) => setDialogState(() {
                                        if (v == true) {
                                          selectedPermissions.add(permId);
                                        } else {
                                          selectedPermissions.remove(permId);
                                        }
                                      })
                                    : null,
                                title: Text(
                                  permLabel,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              );
                            }),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (usernameController.text.trim().isEmpty ||
                        nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('กรุณากรอก Username และชื่อให้ครบ'),
                        ),
                      );
                      return;
                    }
                    if (selectedRole == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('กรุณาเลือกตำแหน่ง (Role)'),
                        ),
                      );
                      return;
                    }
                    if (selectedBranchId == null || selectedBranchId!.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('กรุณาเลือกสาขาประจำ')),
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
      passwordController.dispose();
      return;
    }

    // If the operator chose "create new role", create it first (with the ticked
    // permissions) and assign the resulting role id to this user.
    if (selectedRole == '__new__') {
      final newRoleName = newRoleNameController.text.trim();
      if (newRoleName.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('กรุณากรอกชื่อบทบาทใหม่')),
          );
        }
        return;
      }
      try {
        final created = await ApiService.createRole(
          token: token,
          name: newRoleName,
          permissions: selectedPermissions.toList(),
        );
        selectedRole = (created['id'] ?? '').toString();
        if (selectedRole == null || selectedRole!.isEmpty) {
          throw Exception('ไม่พบรหัสบทบาทใหม่');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('สร้างบทบาทใหม่ไม่สำเร็จ: $e')),
          );
        }
        return;
      }
    }

    // Build customPermissions list (null = use role defaults, non-null = override)
    // We always send it so the server knows the intended permissions
    final customPerms = canEditPerms ? selectedPermissions.toList() : null;

    try {
      if (isEdit) {
        final userId = '${user['id'] ?? user['userId'] ?? ''}';
        if (userId.isEmpty) throw Exception('ไม่พบรหัสผู้ใช้');
        await ApiService.updateUser(
          token: token,
          userId: userId,
          username: usernameController.text.trim(),
          roleId: selectedRole!,
          name: nameController.text.trim(),
          password: passwordController.text.isEmpty
              ? null
              : passwordController.text,
          isActive: isActive,
          isSuperuser: false,
          customPermissions: customPerms,
        );
        await _syncUserPrimaryBranch(
          token: token,
          userId: userId,
          branchId: selectedBranchId!,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('แก้ไขผู้ใช้สำเร็จ')));
      } else {
        final createdUser = await ApiService.createUser(
          token: token,
          username: usernameController.text.trim(),
          roleId: selectedRole!,
          name: nameController.text.trim(),
          password: passwordController.text,
          isActive: isActive,
          isSuperuser: false,
          customPermissions: customPerms,
        );
        final userId = (createdUser['id'] ?? createdUser['userId'] ?? '')
            .toString();
        if (userId.isEmpty) {
          throw Exception('สร้างผู้ใช้สำเร็จแต่ไม่พบรหัสผู้ใช้');
        }
        await _syncUserPrimaryBranch(
          token: token,
          userId: userId,
          branchId: selectedBranchId!,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('สร้างผู้ใช้ใหม่สำเร็จ')));
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
      passwordController.dispose();
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> user) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) return;

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
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () {
                if (passwordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('กรุณากำหนดรหัสผ่านใหม่')),
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
      if (userId.isEmpty) throw Exception('ไม่พบรหัสผู้ใช้');
      await ApiService.updateUser(
        token: token,
        userId: userId,
        username: '${user['username'] ?? ''}',
        roleId: '${user['roleId'] ?? user['role'] ?? ''}',
        name: '${user['name'] ?? ''}',
        password: passwordController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ตั้งรหัสผ่านใหม่สำเร็จ')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ตั้งรหัสผ่านใหม่ไม่สำเร็จ: $e')));
    } finally {
      passwordController.dispose();
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) return;

    final username = '${user['username'] ?? ''}';

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ยืนยันการลบผู้ใช้'),
        content: Text(
          'คุณต้องการลบผู้ใช้ "$username" จริงหรือไม่? ไม่สามารถย้อนกลับได้',
        ),
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
      ),
    );

    if (shouldDelete != true) return;

    try {
      final userId = '${user['id'] ?? user['userId'] ?? ''}';
      if (userId.isEmpty) throw Exception('ไม่พบรหัสผู้ใช้');
      await ApiService.deleteUser(token: token, userId: userId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ลบผู้ใช้สำเร็จ')));
      await _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ลบผู้ใช้ไม่สำเร็จ: $e')));
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
                      onChanged: (v) => setState(() => _searchTerm = v.trim()),
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
                        Expanded(child: _buildTable()),
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
          DataColumn(label: Text('ชื่อ')),
          DataColumn(label: Text('สาขา')),
          DataColumn(label: Text('ตำแหน่ง')),
          DataColumn(label: Text('สถานะ')),
          DataColumn(label: Text('Actions')),
        ],
        rows: users.map((u) {
          final username = '${u['username'] ?? ''}';
          final name = '${u['name'] ?? ''}';
          final branchId = '${u['branchId'] ?? ''}';
          final roleId = '${u['roleId'] ?? u['role'] ?? ''}';
          final isActive =
              u['isActive'] == true ||
              u['isActive']?.toString().toLowerCase() == 'true';

          // Role badge color
          Color roleBadgeColor;
          switch (roleId) {
            case 'role.admin':
              roleBadgeColor = Colors.deepPurple;
            case 'role.hq_manager':
              roleBadgeColor = AppColors.primary;
            case 'role.van_staff':
              roleBadgeColor = Colors.teal;
            default:
              roleBadgeColor = AppColors.muted;
          }

          return DataRow(
            cells: [
              DataCell(Text(username.isEmpty ? '-' : username)),
              DataCell(Text(name.isEmpty ? '-' : name)),
              DataCell(Text(_branchLabelById(branchId))),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: roleBadgeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: roleBadgeColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    _roleLabel(roleId),
                    style: TextStyle(
                      color: roleBadgeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              DataCell(
                Row(
                  children: [
                    Icon(
                      isActive ? Icons.check_circle : Icons.cancel,
                      color: isActive ? Colors.green : Colors.grey,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isActive ? 'Active' : 'Inactive',
                      style: TextStyle(
                        fontSize: 12,
                        color: isActive ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              DataCell(
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      tooltip: 'แก้ไขผู้ใช้',
                      onPressed: () => _openUserForm(user: u),
                    ),
                    IconButton(
                      icon: const Icon(Icons.lock_reset, size: 18),
                      tooltip: 'ตั้งรหัสผ่านใหม่',
                      onPressed: () => _resetPassword(u),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 18),
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
