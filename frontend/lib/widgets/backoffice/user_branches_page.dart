import 'package:flutter/material.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/services/api_service.dart';
// ปรับให้ตรงกับของจริง ถ้าคุณใช้ Provider / Riverpod อื่น ๆ
import 'package:provider/provider.dart';
import 'package:frontend/providers/auth_provider.dart';

class UserBranchesSection extends StatefulWidget {
  const UserBranchesSection({super.key});

  @override
  State<UserBranchesSection> createState() => _UserBranchesSectionState();
}

class _UserBranchesSectionState extends State<UserBranchesSection> {
  final TextEditingController _searchController = TextEditingController();

  bool _isInitialLoading = false;
  bool _isLoadingUserMappings = false;
  bool _isLoadingBranchMappings = false;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _branches = [];

  String? _selectedUserKey;
  String? _selectedBranchKey;

  /// branchId ที่ user ที่เลือกสามารถเข้าได้
  Set<String> _branchKeysForSelectedUser = {};

  /// userId ของพนักงานในสาขาที่เลือก
  Set<String> _userKeysForSelectedBranch = {};

  String _filter = '';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ===================== Helper: key & display =====================

  String _userKey(Map<String, dynamic> user) {
    final id = user['id'] ?? user['userId'];
    if (id != null) return id.toString();
    return (user['username'] ?? '').toString();
  }

  String _userDisplay(Map<String, dynamic> user) {
    final username = user['username']?.toString() ?? '';
    final name = user['name']?.toString() ?? '';
    if (username.isNotEmpty && name.isNotEmpty) {
      return '$username ($name)';
    }
    return username.isNotEmpty ? username : name;
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

      String? defaultUserKey;
      String? defaultBranchKey;

      if (users.isNotEmpty) {
        defaultUserKey = _userKey(users.first);
      }
      if (branches.isNotEmpty) {
        defaultBranchKey = _branchKey(branches.first);
      }

      setState(() {
        _users = users;
        _branches = branches;
        _selectedUserKey = defaultUserKey;
        _selectedBranchKey = defaultBranchKey;
      });

      if (defaultUserKey != null) {
        await _loadUserBranchesForUser(defaultUserKey);
      }
      if (defaultBranchKey != null) {
        await _loadUserBranchesForBranch(defaultBranchKey);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('โหลดข้อมูลผู้ใช้/สาขาไม่สำเร็จ: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    }
  }

  Future<void> _loadUserBranchesForUser(String userKey) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _isLoadingUserMappings = true;
    });

    try {
      final mappings = await ApiService.getUserBranches(
        token: token,
        userId: userKey,
      );

      final branchIds = <String>{};

      for (final m in mappings) {
        // รองรับหลายฟอร์แมต เช่น { branchId }, { branch_id }, { branch: { branchId } }
        final bid =
            (m['branchId'] ??
                    m['branch_id'] ??
                    m['branch']?['branchId'] ??
                    m['branch']?['id'])
                ?.toString();
        if (bid != null && bid.isNotEmpty) {
          branchIds.add(bid);
        }
      }

      setState(() {
        _branchKeysForSelectedUser = branchIds;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('โหลดสาขาที่ผู้ใช้เข้าได้ไม่สำเร็จ: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingUserMappings = false;
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
        // รองรับหลายฟอร์แมต เช่น { userId }, { user_id }, { user: { id } }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('โหลดพนักงานในสาขาไม่สำเร็จ: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBranchMappings = false;
        });
      }
    }
  }

  // ===================== Actions =====================

  void _onSearchChanged(String value) {
    setState(() {
      _filter = value.trim().toLowerCase();
    });
  }

  void _onSavePermissionsPressed() {
    // ตอนนี้ ApiService ยังมีแค่ GET /user-branches
    // เลยแสดงข้อความแจ้งเตือนแทนการบันทึกจริง
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'ยังไม่รองรับการบันทึกสิทธิ์ (ไม่มี endpoint แก้ไข user-branches ใน ApiService)',
        ),
      ),
    );
  }

  Future<void> _onRefreshPressed() async {
    if (_selectedUserKey != null) {
      await _loadUserBranchesForUser(_selectedUserKey!);
    }
    if (_selectedBranchKey != null) {
      await _loadUserBranchesForBranch(_selectedBranchKey!);
    }
  }

  // ===================== Build =====================

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    Iterable<Map<String, dynamic>> accessibleBranches = _branches.where(
      (b) => _branchKeysForSelectedUser.contains(_branchKey(b)),
    );

    Iterable<Map<String, dynamic>> employeesInBranch = _users.where(
      (u) => _userKeysForSelectedBranch.contains(_userKey(u)),
    );

    if (_filter.isNotEmpty) {
      final f = _filter;
      accessibleBranches = accessibleBranches.where((b) {
        final text = _branchDisplay(b).toLowerCase();
        return text.contains(f);
      });
      employeesInBranch = employeesInBranch.where((u) {
        final text = _userDisplay(u).toLowerCase();
        return text.contains(f);
      });
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top actions row
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _onSavePermissionsPressed,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('บันทึกการตั้งค่าสิทธิ์'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _onRefreshPressed,
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
                        hintText: 'ค้นหาผู้ใช้หรือสาขา...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Main card fills remaining height
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
                        // Selector row
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'เลือกผู้ใช้',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    value: _selectedUserKey,
                                    items: _users
                                        .map(
                                          (u) => DropdownMenuItem<String>(
                                            value: _userKey(u),
                                            child: Text(_userDisplay(u)),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) async {
                                      if (value == null) return;
                                      setState(() {
                                        _selectedUserKey = value;
                                        _branchKeysForSelectedUser.clear();
                                      });
                                      await _loadUserBranchesForUser(value);
                                    },
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'เลือกสาขา',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    value: _selectedBranchKey,
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
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Two side-by-side panels inside main card
                        Expanded(
                          child: Row(
                            children: [
                              // Left: branches that user can access
                              Expanded(
                                child: Card(
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'สาขาที่ผู้ใช้เข้าได้',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        const Divider(height: 1),
                                        const SizedBox(height: 8),
                                        if (_isLoadingUserMappings)
                                          const Expanded(
                                            child: Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            ),
                                          )
                                        else
                                          Expanded(
                                            child: ListView.builder(
                                              itemCount:
                                                  accessibleBranches.length,
                                              itemBuilder: (context, index) {
                                                final branch =
                                                    accessibleBranches
                                                        .elementAt(index);
                                                return ListTile(
                                                  dense: true,
                                                  title: Text(
                                                    _branchDisplay(branch),
                                                  ),
                                                  trailing: const Icon(
                                                    Icons.remove_circle_outline,
                                                    color: Colors.redAccent,
                                                  ),
                                                  onTap: () {
                                                    // ยังไม่มี API ลบสิทธิ์สาขาออกจากผู้ใช้
                                                  },
                                                );
                                              },
                                            ),
                                          ),
                                        Align(
                                          alignment: Alignment.bottomRight,
                                          child: TextButton.icon(
                                            onPressed: () {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'ยังไม่รองรับการเพิ่มสิทธิ์สาขาให้ผู้ใช้ (รอ backend)',
                                                  ),
                                                ),
                                              );
                                            },
                                            icon: const Icon(Icons.add),
                                            label: const Text('เพิ่มสาขา'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),

                              // Right: employees in selected branch
                              Expanded(
                                child: Card(
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'พนักงานในสาขานี้',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        const Divider(height: 1),
                                        const SizedBox(height: 8),
                                        if (_isLoadingBranchMappings)
                                          const Expanded(
                                            child: Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            ),
                                          )
                                        else
                                          Expanded(
                                            child: ListView.builder(
                                              itemCount:
                                                  employeesInBranch.length,
                                              itemBuilder: (context, index) {
                                                final user = employeesInBranch
                                                    .elementAt(index);
                                                return ListTile(
                                                  dense: true,
                                                  title: Text(
                                                    user['username']
                                                            ?.toString() ??
                                                        '',
                                                  ),
                                                  subtitle: Text(
                                                    user['name']?.toString() ??
                                                        '',
                                                  ),
                                                  trailing: const Icon(
                                                    Icons.remove_circle_outline,
                                                    color: Colors.redAccent,
                                                  ),
                                                  onTap: () {
                                                    // ยังไม่มี API ลบสิทธิ์ผู้ใช้ออกจากสาขา
                                                  },
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
