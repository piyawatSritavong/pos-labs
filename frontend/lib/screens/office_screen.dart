import 'package:flutter/material.dart';
import 'package:frontend/services/api_branches.dart';
import 'package:frontend/services/api_company.dart';
import 'package:frontend/services/api_pos.dart';
import 'package:frontend/services/api_user_branches.dart';
import 'package:frontend/services/api_users.dart';
import 'package:provider/provider.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/branches_provider.dart';
import 'package:frontend/providers/company_provider.dart';
import 'package:frontend/providers/users_provider.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/branches/branches_tab.dart';
import 'package:frontend/widgets/company/company_tab.dart';
import 'package:frontend/widgets/users/users_tab.dart';

class OfficeScreen extends StatefulWidget {
  const OfficeScreen({super.key});

  @override
  State<OfficeScreen> createState() => _OfficeScreenState();
}

class _OfficeScreenState extends State<OfficeScreen> {
  static final _menuItems = [
    _SidebarItem('Overview', Icons.dashboard_outlined),
    _SidebarItem('Users', Icons.people_alt_outlined),
    _SidebarItem('Company', Icons.business_outlined),
    _SidebarItem('Branches', Icons.store_outlined),
    _SidebarItem('POS & User Branches', Icons.link_outlined),
  ];
  int _selectedIndex = 0;
  bool _isLoading = true;
  String? _error;
  String? _mockNotice;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _posDevices = [];
  List<Map<String, dynamic>> _userBranches = [];
  Map<String, dynamic>? _company;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDashboard();
    });
  }

  Future<void> _loadDashboard() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null) {
      _applyMockData('token หาย – แสดงข้อมูลตัวอย่าง');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        ApiUsersService.getUsers(token: token),
        ApiCompanyService.getCompany(token: token),
        ApiBranchesService.getBranches(token: token, limit: 100),
        ApiPosService.getPosDevices(token: token, limit: 100),
      ]);

      final users = results[0] as List<Map<String, dynamic>>;
      final company = results[1] as Map<String, dynamic>;
      final branches = results[2] as List<Map<String, dynamic>>;
      final posDevices = results[3] as List<Map<String, dynamic>>;

      // Backend ไม่มี GET /user-branches (list all)
      // เราเลย aggregate จาก GET /user-branches/branch/:branch_id แทน
      final branchIds = branches
          .map((b) => b['branchId']?.toString() ?? b['branch_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList();

      final userBranchesByBranch = await Future.wait(
        branchIds.map((id) async {
          try {
            return await ApiUserBranchesService.getUserBranches(token: token, branchId: id);
          } catch (_) {
            return <Map<String, dynamic>>[];
          }
        }),
      );

      final userBranches = <Map<String, dynamic>>[];
      for (final list in userBranchesByBranch) {
        userBranches.addAll(list);
      }

      setState(() {
        _mockNotice = null;
        _users = users;
        _company = company;
        _branches = branches;
        _posDevices = posDevices;
        _userBranches = userBranches;
      });
    } catch (e) {
      _applyMockData('โหลดข้อมูลจริงไม่สำเร็จ: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _applyMockData(String reason) {
    setState(() {
      _mockNotice = reason;
      _error = null;
      _isLoading = false;
      _company = {
        'companyNameTh': 'บริษัทตัวอย่าง จำกัด',
        'companyAddressTh': '123 ถนนสุขุมวิท กรุงเทพฯ',
        'phone': '02-123-4567',
        'email': 'info@example.com',
        'website': 'https://example.com',
        'taxRate': 0.07,
        'taxType': 'vat',
      };
      _users = [
        {
          'name': 'Mock Admin',
          'username': 'admin',
          'roleId': 'role.admin',
          'isActive': true,
        },
        {
          'name': 'Mock Cashier',
          'username': 'cashier',
          'roleId': 'role.cashier',
          'isActive': true,
        },
      ];
      _branches = [
        {
          'branchId': '00000',
          'branchNameTh': 'สาขากลางเมือง',
          'branchAddressTh': '456 ถนนพระราม 9',
          'phone': '02-222-2222',
        },
      ];
      _posDevices = [
        {'posId': 'POS001', 'branchId': '00000'},
        {'posId': 'POS002', 'branchId': '00000'},
      ];
      _userBranches = [
        {'userId': 'admin', 'branchId': '00000'},
        {'userId': 'cashier', 'branchId': '00000'},
      ];
    });
  }

  Widget _buildGuardedBody(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isAdmin) {
      Future.microtask(() {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      });
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _loadDashboard)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Sidebar(
                      items: _menuItems,
                      selectedIndex: _selectedIndex,
                      onSelect: (index) =>
                          setState(() => _selectedIndex = index),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          _TopBar(onSearch: (query) {}),
                          if (_mockNotice != null)
                            _NoticeBanner(message: _mockNotice!),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                              child: _buildContentForIndex(_selectedIndex),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildGuardedBody(context);
  }

  Widget _buildContentForIndex(int index) {
    switch (index) {
      case 0:
        return _OverviewTab(
          company: _company,
          users: _users,
          branches: _branches,
          posDevices: _posDevices,
          userBranches: _userBranches,
        );
      case 1:
        return UsersTab(data: _users);
      case 2:
        return CompanyTab(data: _company);
      case 3:
        return BranchesTab(data: _branches);
      case 4:
        return _PosUserBranchesTab(
          posDevices: _posDevices,
          userBranches: _userBranches,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.company,
    required this.users,
    required this.branches,
    required this.posDevices,
    required this.userBranches,
  });

  final Map<String, dynamic>? company;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> posDevices;
  final List<Map<String, dynamic>> userBranches;

  @override
  Widget build(BuildContext context) {
    // ใช้ Consumer เพื่อรับข้อมูลล่าสุดจาก providers
    return Consumer3<UsersProvider, CompanyProvider, BranchesProvider>(
      builder: (context, usersProvider, companyProvider, branchesProvider, _) {
        // ใช้ข้อมูลจาก provider ถ้ามี, ไม่งั้นใช้จาก props
        final currentUsers = usersProvider.users.isNotEmpty 
            ? usersProvider.users 
            : users;
        final currentCompany = companyProvider.company ?? company;
        final currentBranches = branchesProvider.branches.isNotEmpty
            ? branchesProvider.branches
            : branches;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _StatCard(
                    title: 'Users',
                    value: currentUsers.length.toString(),
                    icon: Icons.people_alt_outlined,
                  ),
                  _StatCard(
                    title: 'Branches',
                    value: currentBranches.length.toString(),
                    icon: Icons.store_outlined,
                  ),
                  _StatCard(
                    title: 'POS Devices',
                    value: posDevices.length.toString(),
                    icon: Icons.point_of_sale_outlined,
                  ),
                  _StatCard(
                    title: 'User/Branch links',
                    value: userBranches.length.toString(),
                    icon: Icons.link_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: const [
                  Expanded(
                    child: _ChartCard(
                      title: 'ยอดขายรายเดือน',
                      subtitle: 'ข้อมูลจำลอง',
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: _ChartCard(
                      title: 'อัตราการเติบโต',
                      subtitle: 'จำลอง',
                      variant: ChartVariant.ring,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (currentCompany != null)
                _SectionContainer(
                  title: 'Company Profile',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentCompany['companyNameTh']?.toString() ??
                            currentCompany['companyName']?.toString() ??
                            'ไม่ทราบชื่อ',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        currentCompany['companyAddressTh']?.toString() ??
                            currentCompany['companyAddress']?.toString() ??
                            '-',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          _InlineInfo(
                            label: 'โทร',
                            value: currentCompany['phone']?.toString() ?? '-',
                          ),
                          _InlineInfo(
                            label: 'อีเมล',
                            value: currentCompany['email']?.toString() ?? '-',
                          ),
                          _InlineInfo(
                            label: 'ภาษี',
                            value:
                                '${((currentCompany['taxRate'] ?? 0) * 100).toStringAsFixed(2)}% (${currentCompany['taxType'] ?? '-'})',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PosUserBranchesTab extends StatelessWidget {
  const _PosUserBranchesTab({
    required this.posDevices,
    required this.userBranches,
  });

  final List<Map<String, dynamic>> posDevices;
  final List<Map<String, dynamic>> userBranches;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionContainer(
            title: 'POS Devices',
            child: posDevices.isEmpty
                ? const _EmptyMessage(message: 'ยังไม่มี POS ที่ลงทะเบียน')
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: posDevices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final pos = posDevices[index];
                      return ListTile(
                        leading: const Icon(Icons.point_of_sale_outlined),
                        title: Text(pos['posId']?.toString() ?? 'POS'),
                        subtitle: Text('สาขา ${pos['branchId'] ?? '-'}'),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 24),
          _SectionContainer(
            title: 'User Branch Assignments',
            child: userBranches.isEmpty
                ? const _EmptyMessage(message: 'ยังไม่มีการกำหนดสาขาให้ผู้ใช้')
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: userBranches.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final link = userBranches[index];
                      return ListTile(
                        leading: const Icon(Icons.link_outlined),
                        title: Text('User: ${link['userId'] ?? '-'}'),
                        subtitle: Text('Branch: ${link['branchId'] ?? '-'}'),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionContainer extends StatelessWidget {
  const _SectionContainer({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _InlineInfo extends StatelessWidget {
  const _InlineInfo({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(message, style: const TextStyle(color: AppColors.muted)),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.danger),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('ลองใหม่')),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_SidebarItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.dashboard_customize, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              const Text(
                'POS Office',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final isActive = index == selectedIndex;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onSelect(index),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item.icon,
                            color: isActive ? AppColors.primary : AppColors.muted,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            item.label,
                            style: TextStyle(
                              color:
                                  isActive ? AppColors.primary : AppColors.muted,
                              fontWeight:
                                  isActive ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSearch});

  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Spacer(),
          PopupMenuButton<String>(
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              child: const Icon(Icons.person, color: AppColors.primary),
            ),
            itemBuilder: (context) => [
              if (auth.isAdmin)
                const PopupMenuItem(value: 'pos', child: Text('POS')),
              const PopupMenuItem(value: 'logout', child: Text('ออกจากระบบ')),
            ],
            onSelected: (value) async {
              if (value == 'logout') {
                await context.read<AuthProvider>().logout();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              } else if (value == 'pos') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SidebarItem {
  const _SidebarItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}

enum ChartVariant { line, ring, purple }

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    this.variant = ChartVariant.line,
  });

  final String title;
  final String subtitle;
  final ChartVariant variant;

  @override
  Widget build(BuildContext context) {
    final Gradient gradient;
    Color accent;
    switch (variant) {
      case ChartVariant.ring:
        gradient = const LinearGradient(
          colors: [Color(0xFF14B8A6), Color(0xFF6D28D9)],
        );
        accent = const Color(0xFF14B8A6);
        break;
      case ChartVariant.purple:
        gradient = const LinearGradient(
          colors: [Color(0xFF5B21B6), Color(0xFF8B5CF6)],
        );
        accent = Colors.white;
        break;
      default:
        gradient = const LinearGradient(
          colors: [Color(0xFFF472B6), Color(0xFFFBBF24)],
        );
        accent = AppColors.text;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: variant == ChartVariant.purple ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      height: 230,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: accent.withOpacity(0.7)),
          ),
          const Spacer(),
          Container(
            height: 120,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text(
                'Chart Placeholder',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
