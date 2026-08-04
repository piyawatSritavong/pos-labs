import 'package:flutter/material.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/app_dialog_service.dart';
import 'package:provider/provider.dart';
import 'package:frontend/providers/auth_provider.dart';

class UserBranchesSection extends StatefulWidget {
  const UserBranchesSection({super.key});

  @override
  State<UserBranchesSection> createState() => _UserBranchesSectionState();
}

class _UserBranchesSectionState extends State<UserBranchesSection> {
  bool _isInitialLoading = false;
  bool _isLoadingBranchMappings = false;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _branches = [];

  String? _selectedBranchKey;

  /// userId ของพนักงานในสาขาที่เลือก
  Set<String> _userKeysForSelectedBranch = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  // ===================== Helper: key & display =====================

  String _userKey(Map<String, dynamic> user) {
    final id = user['id'] ?? user['userId'];
    if (id != null) return id.toString();
    return (user['username'] ?? '').toString();
  }

  String _branchKey(Map<String, dynamic> branch) {
    final id = branch['branchId'] ?? branch['id'];
    return (id ?? '').toString();
  }

  String _branchDisplay(Map<String, dynamic> branch) {
    final code = branch['branchId']?.toString() ?? '';
    final name =
        branch['branchName']?.toString() ??
        branch['branchNameTh']?.toString() ??
        '';
    if (code.isNotEmpty && name.isNotEmpty) {
      return '$code - $name';
    }
    return code.isNotEmpty ? code : name;
  }

  // ===================== Load data =====================

  Future<void> _loadInitialData() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _isInitialLoading = true;
    });

    try {
      final users = await ApiService.getUsers(
        token: token,
        limit: 200,
        offset: 0,
      );
      final branches = await ApiService.getBranches(
        token: token,
        limit: 200,
        offset: 0,
      );

      String? defaultBranchKey;
      if (branches.isNotEmpty) {
        defaultBranchKey = _branchKey(branches.first);
      }

      setState(() {
        _users = users;
        _branches = branches;
        _selectedBranchKey = defaultBranchKey;
      });

      if (defaultBranchKey != null) {
        await _loadUserBranchesForBranch(defaultBranchKey);
      }
    } catch (e) {
      if (!mounted) return;
      final retry = await AppDialogService.showError(
        context,
        error: e,
        fallback: 'โหลดข้อมูลผู้ใช้และสาขาไม่สำเร็จ',
        allowRetry: true,
      );
      if (retry && mounted) await _loadInitialData();
    } finally {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    }
  }

  Future<void> _loadUserBranchesForBranch(String branchKey) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _isLoadingBranchMappings = true;
    });

    try {
      final mappings = await ApiService.getUserBranches(
        token: token,
        branchId: branchKey,
      );

      final userIds = <String>{};
      for (final m in mappings) {
        final uid = (m['userId'] ?? m['user_id'] ?? m['user']?['id'])
            ?.toString();
        if (uid != null && uid.isNotEmpty) {
          userIds.add(uid);
        }
      }

      setState(() {
        _userKeysForSelectedBranch = userIds;
      });
    } catch (e) {
      if (!mounted) return;
      final retry = await AppDialogService.showError(
        context,
        error: e,
        fallback: 'โหลดพนักงานในสาขาไม่สำเร็จ',
        allowRetry: true,
      );
      if (retry && mounted) await _loadUserBranchesForBranch(branchKey);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBranchMappings = false;
        });
      }
    }
  }

  // ===================== Build =====================

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final employeesInBranch = _users
        .where((u) => _userKeysForSelectedBranch.contains(_userKey(u)))
        .toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Branch selector row
              Row(
                children: [
                  const Text(
                    'สาขา:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('branch_${_selectedBranchKey ?? ''}'),
                      initialValue: _selectedBranchKey,
                      items: _branches
                          .map(
                            (b) => DropdownMenuItem<String>(
                              value: _branchKey(b),
                              child: Text(_branchDisplay(b)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) async {
                        if (value == null) return;
                        setState(() {
                          _selectedBranchKey = value;
                          _userKeysForSelectedBranch.clear();
                        });
                        await _loadUserBranchesForBranch(value);
                      },
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'รีเฟรช',
                    onPressed: () {
                      if (_selectedBranchKey != null) {
                        _loadUserBranchesForBranch(_selectedBranchKey!);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Employees list
              Expanded(
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'พนักงานในสาขา (${employeesInBranch.length} คน)',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_isLoadingBranchMappings)
                          const Expanded(
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (employeesInBranch.isEmpty)
                          const Expanded(
                            child: Center(
                              child: Text(
                                'ไม่มีพนักงานในสาขานี้',
                                style: TextStyle(color: AppColors.muted),
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: ListView.separated(
                              itemCount: employeesInBranch.length,
                              separatorBuilder: (_, _) => const Divider(
                                height: 1,
                                color: AppColors.border,
                              ),
                              itemBuilder: (context, i) {
                                final u = employeesInBranch[i];
                                final username =
                                    u['username']?.toString() ?? '';
                                final name = u['name']?.toString() ?? '';
                                final roleId = u['roleId']?.toString() ?? '';
                                final roleLabel = roleId == 'role.admin'
                                    ? 'Super Admin'
                                    : roleId == 'role.hq_manager'
                                    ? 'HQ Manager'
                                    : roleId == 'role.van_staff'
                                    ? 'POS Staff'
                                    : roleId;
                                return ListTile(
                                  leading: const Icon(Icons.person_outline),
                                  title: Text(
                                    name.isNotEmpty ? name : username,
                                  ),
                                  subtitle: username.isNotEmpty
                                      ? Text(username)
                                      : null,
                                  trailing: roleLabel.isNotEmpty
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.08,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Text(
                                            roleLabel,
                                            style: const TextStyle(
                                              color: AppColors.primary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )
                                      : null,
                                );
                              },
                            ),
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
}
