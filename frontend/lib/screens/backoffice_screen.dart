import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/services/api_service.dart';

// เมนูหน้าจอหลังบ้านสำหรับแอดมิน ใช้จัดการ:
// - Users
// - User Branches
// - Company
// - Branches
// - POS devices
// - Parts (สินค้า)
// - Addresses (สต็อกตามที่เก็บ)
// - Promotions
// - Bills history
// - Payment / QR settings

// ======================================================================
// Providers for Backoffice modules
// ======================================================================

// 1) Company settings (/company)
class CompanyProvider extends ChangeNotifier {
  bool isLoading = false;
  String? error;
  Map<String, dynamic>? company;

  Future<void> fetchCompany(String token) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      company = await ApiService.getCompany(token: token);
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateCompany(String token, Map<String, dynamic> payload) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      company = await ApiService.updateCompany(
        token: token,
        companyName: payload['companyName'] ?? '',
        companyNameTh: payload['companyNameTh'] ?? '',
        companyAddress: payload['companyAddress'] ?? '',
        companyAddressTh: payload['companyAddressTh'] ?? '',
        phone: payload['phone'] ?? '',
        email: payload['email'] ?? '',
        website: payload['website'] ?? '',
        logoUrl: payload['logoUrl'],
        taxRate: (payload['taxRate'] ?? 0).toDouble(),
        taxType: payload['taxType'] ?? 'xvat',
      );
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

// 2) Branches (/branches)
class BranchesProvider extends ChangeNotifier {
  bool isLoading = false;
  String? error;
  List<Map<String, dynamic>> branches = [];

  Future<void> fetchBranches(String token) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      branches = await ApiService.getBranches(token: token);
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

// 3) POS devices (/pos)
class PosDevicesProvider extends ChangeNotifier {
  bool isLoading = false;
  String? error;
  List<Map<String, dynamic>> devices = [];

  Future<void> fetchDevices(String token) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      devices = await ApiService.getPosDevices(token: token);
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

// 4) Parts (/parts, /parts/search)
class PartsProvider extends ChangeNotifier {
  bool isLoading = false;
  String? error;
  List<Map<String, dynamic>> parts = [];

  Future<void> fetchParts(
    String token, {
    int limit = 20,
    int offset = 0,
  }) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      parts = await ApiService.getParts(
        token: token,
        limit: limit,
        offset: offset,
      );
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> search(String token, {String query = ''}) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      parts = await ApiService.searchParts(
        token: token,
        query: query,
        limit: 50,
        offset: 0,
      );
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

// 5) Addresses (/addresses)
class AddressesProvider extends ChangeNotifier {
  bool isLoading = false;
  String? error;
  List<Map<String, dynamic>> addresses = [];

  Future<void> fetchAddresses(String token) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      addresses = await ApiService.getAddresses(
        token: token,
        limit: 100,
        offset: 0,
      );
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

// 6) Promotions (/promotions)
class PromotionsProvider extends ChangeNotifier {
  bool isLoading = false;
  String? error;
  List<Map<String, dynamic>> promotions = [];

  Future<void> fetchPromotions(String token) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      promotions = await ApiService.getPromotions(
        token: token,
        limit: 100,
        offset: 0,
      );
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

// 7) Bills history (/bills)
class BillsProvider extends ChangeNotifier {
  bool isLoading = false;
  String? error;
  List<Map<String, dynamic>> bills = [];

  Future<void> fetchBills(
    String token, {
    int limit = 50,
    int offset = 0,
    String? date,
    String? dateFrom,
    String? dateTo,
  }) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      bills = await ApiService.getBills(
        token: token,
        limit: limit,
        offset: offset,
        date: date,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

// 8) Assets / QR image (/assets/qr-image)
class AssetsProvider extends ChangeNotifier {
  bool isLoading = false;
  String? error;
  Uint8List? qrImage;

  Future<void> loadQrImage(String token) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      qrImage = await ApiService.getQrImage(token: token);
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

// ======================================================================
// Main Backoffice Screen
// ======================================================================

class BackofficeScreen extends StatelessWidget {
  const BackofficeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CompanyProvider()),
        ChangeNotifierProvider(create: (_) => BranchesProvider()),
        ChangeNotifierProvider(create: (_) => PosDevicesProvider()),
        ChangeNotifierProvider(create: (_) => PartsProvider()),
        ChangeNotifierProvider(create: (_) => AddressesProvider()),
        ChangeNotifierProvider(create: (_) => PromotionsProvider()),
        ChangeNotifierProvider(create: (_) => BillsProvider()),
        ChangeNotifierProvider(create: (_) => AssetsProvider()),
      ],
      child: const _BackofficeShell(),
    );
  }
}

class _BackofficeShell extends StatefulWidget {
  const _BackofficeShell();

  @override
  State<_BackofficeShell> createState() => _BackofficeShellState();
}

class _BackofficeShellState extends State<_BackofficeShell> {
  // sidebar items (with group headers)
  final List<_SidebarItem> _sidebarItems = const [
    _SidebarItem(label: 'ORGANIZATION', isHeader: true),
    _SidebarItem(
      label: 'Users',
      page: 'User Management',
      icon: Icons.people_alt_outlined,
      pageIndex: 0,
    ),
    _SidebarItem(
      label: 'User-Branches',
      page: 'User-Branch Access',
      icon: Icons.account_tree_outlined,
      pageIndex: 1,
    ),
    _SidebarItem(
      label: 'Company',
      page: 'Company Settings',
      icon: Icons.business_outlined,
      pageIndex: 2,
    ),
    _SidebarItem(
      label: 'Branches',
      page: 'Branch Management',
      icon: Icons.store_outlined,
      pageIndex: 3,
    ),
    _SidebarItem(
      label: 'POS',
      page: 'POS Management',
      icon: Icons.point_of_sale_outlined,
      pageIndex: 4,
    ),

    _SidebarItem(label: 'MASTER DATA', isHeader: true),
    _SidebarItem(
      label: 'Parts',
      page: 'Product Master',
      icon: Icons.inventory_2_outlined,
      pageIndex: 5,
    ),
    _SidebarItem(
      label: 'Addresses',
      page: 'Stock / Inventory',
      icon: Icons.warehouse_outlined,
      pageIndex: 6,
    ),
    _SidebarItem(
      label: 'Promotions',
      page: 'Promotions Management',
      icon: Icons.local_offer_outlined,
      pageIndex: 7,
    ),

    _SidebarItem(label: 'OPERATIONS / REPORTS', isHeader: true),
    _SidebarItem(
      label: 'Bills',
      page: 'Bills History',
      icon: Icons.receipt_long_outlined,
      pageIndex: 8,
    ),
    _SidebarItem(
      label: 'Payment',
      page: 'Payment Settings',
      icon: Icons.qr_code_2_outlined,
      pageIndex: 9,
    ),
  ];

  // pages for each logical menu (indexed by pageIndex above)
  final List<Widget> _pages = const [
    UsersManagementSection(),
    UserBranchesSection(),
    CompanySettingsSection(),
    BranchesManagementSection(),
    PosManagementSection(),
    PartsManagementSection(),
    AddressesManagementSection(),
    PromotionsManagementSection(),
    BillsHistorySection(),
    QrPaymentSettingsSection(),
  ];

  int _currentPageIndex = 0; // default to Users page

  String get _currentPageTitle {
    final item = _sidebarItems.firstWhere(
      (item) => !item.isHeader && item.pageIndex == _currentPageIndex,
      orElse: () => const _SidebarItem(label: 'Backoffice', page: 'Backoffice'),
    );
    return item.page ?? item.label;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BackofficeSidebar(
            items: _sidebarItems,
            selectedPageIndex: _currentPageIndex,
            onSelectPage: (pageIndex) {
              setState(() {
                _currentPageIndex = pageIndex;
              });
            },
          ),
          Expanded(
            child: Column(
              children: [
                _BackofficeTopBar(title: _currentPageTitle),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    child: _pages[_currentPageIndex],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem {
  const _SidebarItem({
    required this.label,
    this.page,
    this.icon,
    this.pageIndex,
    this.isHeader = false,
  });

  final String label;
  final String? page;
  final IconData? icon;
  final int? pageIndex;
  final bool isHeader;
}

class _BackofficeSidebar extends StatelessWidget {
  const _BackofficeSidebar({
    required this.items,
    required this.selectedPageIndex,
    required this.onSelectPage,
  });

  final List<_SidebarItem> items;
  final int selectedPageIndex;
  final ValueChanged<int> onSelectPage;

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
                child: const Icon(
                  Icons.dashboard_customize,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'POS Backoffice',
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

                if (item.isHeader) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
                    child: Text(
                      item.label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.muted,
                        letterSpacing: 1.2,
                      ),
                    ),
                  );
                }

                final bool isActive =
                    item.pageIndex != null &&
                    item.pageIndex == selectedPageIndex;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: item.pageIndex == null
                        ? null
                        : () => onSelectPage(item.pageIndex!),
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
                          if (item.icon != null)
                            Icon(
                              item.icon,
                              color: isActive
                                  ? AppColors.primary
                                  : AppColors.muted,
                            ),
                          if (item.icon != null) const SizedBox(width: 12),
                          Text(
                            item.label,
                            style: TextStyle(
                              color: isActive
                                  ? AppColors.primary
                                  : AppColors.muted,
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.w500,
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

class _BackofficeTopBar extends StatelessWidget {
  const _BackofficeTopBar({required this.title});

  final String title;

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
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
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
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// 1) /users – จัดการผู้ใช้งาน (พนักงาน)
// ======================================================================

class UsersManagementSection extends StatelessWidget {
  const UsersManagementSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  // TODO: เปิดฟอร์มสร้างพนักงานใหม่
                },
                icon: const Icon(Icons.person_add),
                label: const Text('เพิ่มพนักงานใหม่'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  // TODO: refresh /users
                },
                icon: const Icon(Icons.refresh),
                label: const Text('รีเฟรช'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Username')),
                  DataColumn(label: Text('Name')),
                  DataColumn(label: Text('Role')),
                  DataColumn(label: Text('Active')),
                  DataColumn(label: Text('Superuser')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: [
                  // ตัวอย่าง mock data ไว้ก่อน
                  DataRow(
                    cells: [
                      const DataCell(Text('cashier01')),
                      const DataCell(Text('Cashier #1')),
                      const DataCell(Text('CASHIER')),
                      const DataCell(
                        Icon(Icons.check_circle, color: Colors.green),
                      ),
                      const DataCell(Icon(Icons.cancel, color: Colors.grey)),
                      DataCell(
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                // TODO: แก้ไข user
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.lock_reset),
                              onPressed: () {
                                // TODO: ตั้งรหัสผ่านใหม่
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                // TODO: ลบ user
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// 2) /user-branches – ผู้ใช้ผูกกับสาขาอะไรบ้าง
// ======================================================================

class UserBranchesSection extends StatelessWidget {
  const UserBranchesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('เลือกผู้ใช้'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      items: const [
                        DropdownMenuItem(
                          value: 'cashier01',
                          child: Text('cashier01'),
                        ),
                      ],
                      onChanged: (value) {
                        // TODO: โหลดสาขาที่ user นี้เข้าถึงได้
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
                    const Text('เลือกสาขา'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      items: const [
                        DropdownMenuItem(
                          value: 'B001',
                          child: Text('B001 - Main Branch'),
                        ),
                      ],
                      onChanged: (value) {
                        // TODO: โหลด user ที่ผูกกับ branch นี้
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
          Expanded(
            child: Row(
              children: [
                // รายการสาขาที่ user นี้เข้าได้
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'สาขาที่ผู้ใช้เข้าได้',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Divider(),
                          Expanded(
                            child: ListView(
                              children: const [
                                ListTile(
                                  title: Text('B001 - Main Branch'),
                                  trailing: Icon(Icons.remove_circle_outline),
                                ),
                              ],
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: TextButton.icon(
                              onPressed: () {
                                // TODO: เพิ่มสิทธิ์สาขาให้ user
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
                // รายชื่อ user ที่สาขานี้
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'พนักงานในสาขานี้',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Divider(),
                          Expanded(
                            child: ListView(
                              children: const [
                                ListTile(
                                  title: Text('cashier01'),
                                  subtitle: Text('Cashier #1'),
                                  trailing: Icon(Icons.remove_circle_outline),
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
        ],
      ),
    );
  }
}

// ======================================================================
// 3) /company – ตั้งค่าบริษัท / หัวบิล
// ======================================================================

class CompanySettingsSection extends StatelessWidget {
  const CompanySettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'ชื่อบริษัท (ไทย)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'ชื่อบริษัท (อังกฤษ)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'ที่อยู่ (ไทย)',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'ที่อยู่ (อังกฤษ)',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          decoration: const InputDecoration(
                            labelText: 'เบอร์โทร',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          decoration: const InputDecoration(labelText: 'Email'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Website'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          decoration: const InputDecoration(
                            labelText: 'VAT Rate (%)',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Tax Type',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'xvat',
                              child: Text('ราคานอก VAT (xvat)'),
                            ),
                            DropdownMenuItem(
                              value: 'ivat',
                              child: Text('ราคารวม VAT (ivat)'),
                            ),
                          ],
                          onChanged: (_) {},
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          // TODO: upload logo
                        },
                        icon: const Icon(Icons.image),
                        label: const Text('อัปโหลดโลโก้'),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          // TODO: call updateCompany(...)
                        },
                        child: const Text('บันทึกการเปลี่ยนแปลง'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// 4) /branches – สาขา
// ======================================================================

class BranchesManagementSection extends StatelessWidget {
  const BranchesManagementSection({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final branchesProvider = context.watch<BranchesProvider>();
    final token = auth.token ?? '';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  // TODO: เปิดฟอร์มสร้างสาขาใหม่ แล้วใช้ ApiService.createBranch() ผ่าน provider ในอนาคต
                },
                icon: const Icon(Icons.add_business),
                label: const Text('เพิ่มสาขาใหม่'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  if (token.isEmpty) return;
                  context.read<BranchesProvider>().fetchBranches(token);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('รีเฟรช'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Branch ID')),
                  DataColumn(label: Text('ชื่อสาขา')),
                  DataColumn(label: Text('ที่อยู่')),
                  DataColumn(label: Text('โทร')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: branchesProvider.isLoading
                    ? const []
                    : (branchesProvider.branches.isEmpty
                          ? const [
                              DataRow(
                                cells: [
                                  DataCell(Text('-')),
                                  DataCell(Text('ยังไม่มีข้อมูลสาขา')),
                                  DataCell(Text('-')),
                                  DataCell(Text('-')),
                                  DataCell(Text('-')),
                                  DataCell(Text('-')),
                                ],
                              ),
                            ]
                          : branchesProvider.branches.map((b) {
                              final branchId = b['branchId']?.toString() ?? '';
                              final branchName =
                                  b['branchName']?.toString() ?? '';
                              final address =
                                  b['branchAddress']?.toString() ?? '';
                              final phone = b['phone']?.toString() ?? '';
                              final email = b['email']?.toString() ?? '';
                              return DataRow(
                                cells: [
                                  DataCell(Text(branchId)),
                                  DataCell(Text(branchName)),
                                  DataCell(Text(address)),
                                  DataCell(Text(phone)),
                                  DataCell(Text(email)),
                                  DataCell(
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.store),
                                          tooltip: 'ดูคลัง/Store ภายในสาขานี้',
                                          onPressed: () {
                                            // TODO
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit),
                                          onPressed: () {
                                            // TODO: แก้ไขสาขา
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete),
                                          onPressed: () {
                                            // TODO: ลบสาขา ผ่าน ApiService.deleteBranch
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// 5) /pos – เครื่อง POS
// ======================================================================

class PosManagementSection extends StatelessWidget {
  const PosManagementSection({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final posProvider = context.watch<PosDevicesProvider>();
    final token = auth.token ?? '';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  // TODO: เปิดฟอร์มสร้าง POS ใหม่
                },
                icon: const Icon(Icons.point_of_sale),
                label: const Text('สร้าง POS ใหม่'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  if (token.isEmpty) return;
                  context.read<PosDevicesProvider>().fetchDevices(token);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('รีเฟรช'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('POS ID')),
                  DataColumn(label: Text('ชื่อ POS')),
                  DataColumn(label: Text('สาขา')),
                  DataColumn(label: Text('Active')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: posProvider.isLoading
                    ? const []
                    : (posProvider.devices.isEmpty
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
                          : posProvider.devices.map((d) {
                              final posId = d['posId']?.toString() ?? '';
                              final posName = d['posName']?.toString() ?? '';
                              final branchId = d['branchId']?.toString() ?? '';
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
                                          onPressed: () {
                                            // TODO: togglePosActivate(...)
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.vpn_key),
                                          tooltip: 'ดู/รีเซ็ต secret',
                                          onPressed: () {
                                            // TODO: getPosSecret / refreshPosSecret
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete),
                                          onPressed: () {
                                            // TODO: deletePos(...)
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// 6) /parts – สินค้า
// ======================================================================

class PartsManagementSection extends StatelessWidget {
  const PartsManagementSection({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final partsProvider = context.watch<PartsProvider>();
    final token = auth.token ?? '';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'ค้นหาสินค้า (ชื่อ, code, barcode)...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (value) {
                    if (token.isEmpty) return;
                    context
                        .read<PartsProvider>()
                        .search(token, query: value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  // TODO: เปิดฟอร์มเพิ่มสินค้าใหม่
                },
                icon: const Icon(Icons.add),
                label: const Text('เพิ่มสินค้าใหม่'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: partsProvider.isLoading
                  ? const [
                      ListTile(
                        leading: CircularProgressIndicator(),
                        title: Text('กำลังโหลดสินค้า...'),
                      ),
                    ]
                  : (partsProvider.parts.isEmpty
                      ? const [
                          ListTile(
                            title: Text('ยังไม่มีข้อมูลสินค้า'),
                          ),
                        ]
                      : partsProvider.parts.map((p) {
                          final code = p['code']?.toString() ?? '';
                          final name = p['name']?.toString() ?? '';
                          final barcode = p['barcode']?.toString() ?? '';
                          final unit = p['unit']?.toString() ?? '';
                          final price = p['price']?.toString() ?? '';
                          return ListTile(
                            leading: const Icon(Icons.inventory_2),
                            title: Text('$code - $name'),
                            subtitle:
                                Text('Barcode: $barcode  •  Unit: $unit'),
                            trailing: Text('฿$price'),
                          );
                        }).toList()),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// 7) /addresses – สต็อก/ที่เก็บสินค้า
// ======================================================================

class AddressesManagementSection extends StatelessWidget {
  const AddressesManagementSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'เลือกสาขา/คลัง',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'store-main',
                      child: Text('Main Store'),
                    ),
                  ],
                  onChanged: (_) {},
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'ค้นหาตาม partCode หรือชื่อสินค้า...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (value) {
                    // TODO: filter inventory
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Part Code')),
                  DataColumn(label: Text('ชื่อสินค้า')),
                  DataColumn(label: Text('Store')),
                  DataColumn(label: Text('Shelf')),
                  DataColumn(label: Text('Qty')),
                  DataColumn(label: Text('Min / ROP')),
                  DataColumn(label: Text('Max')),
                ],
                rows: const [
                  DataRow(
                    cells: [
                      DataCell(Text('P001')),
                      DataCell(Text('น้ำดื่ม 600ml')),
                      DataCell(Text('Main Store')),
                      DataCell(Text('A-01')),
                      DataCell(Text('120')),
                      DataCell(Text('20 / 30')),
                      DataCell(Text('300')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// 8) /promotions – โปรโมชั่น
// ======================================================================

class PromotionsManagementSection extends StatelessWidget {
  const PromotionsManagementSection({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final promotionsProvider = context.watch<PromotionsProvider>();
    final token = auth.token ?? '';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  // TODO: เปิดฟอร์มสร้างโปรโมชั่นใหม่
                },
                icon: const Icon(Icons.local_offer),
                label: const Text('สร้างโปรโมชั่นใหม่'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  if (token.isEmpty) return;
                  context
                      .read<PromotionsProvider>()
                      .fetchPromotions(token);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('รีเฟรช'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Code')),
                  DataColumn(label: Text('รายละเอียด')),
                  DataColumn(label: Text('ประเภท')),
                  DataColumn(label: Text('Amount')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: promotionsProvider.isLoading
                    ? const []
                    : (promotionsProvider.promotions.isEmpty
                        ? const [
                            DataRow(
                              cells: [
                                DataCell(Text('-')),
                                DataCell(Text('ยังไม่มีโปรโมชั่น')),
                                DataCell(Text('-')),
                                DataCell(Text('-')),
                                DataCell(Text('-')),
                              ],
                            ),
                          ]
                        : promotionsProvider.promotions.map((p) {
                            final code = p['code']?.toString() ?? '';
                            final details =
                                p['details']?.toString() ?? '';
                            final unit = p['unit']?.toString() ?? '';
                            final amount = p['amount']?.toString() ?? '';
                            return DataRow(
                              cells: [
                                DataCell(Text(code)),
                                DataCell(Text(details)),
                                DataCell(Text(unit)),
                                DataCell(Text(amount)),
                                DataCell(
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () {
                                          // TODO: แก้ไข promotion
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete),
                                        onPressed: () {
                                          // TODO: ลบ promotion
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// 9) /bills – ประวัติการขาย
// ======================================================================

class BillsHistorySection extends StatelessWidget {
  const BillsHistorySection({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final billsProvider = context.watch<BillsProvider>();
    final token = auth.token ?? '';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'ค้นหาตาม Bill ID หรือคำค้นอื่น ๆ',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (value) {
                    // TODO: ใส่ filter ตาม billId / keyword ในภายหลัง
                    if (token.isEmpty) return;
                    context
                        .read<BillsProvider>()
                        .fetchBills(token, limit: 50, offset: 0);
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  if (token.isEmpty) return;
                  context
                      .read<BillsProvider>()
                      .fetchBills(token, limit: 50, offset: 0);
                },
                icon: const Icon(Icons.date_range),
                label: const Text('โหลดข้อมูล'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: billsProvider.isLoading
                  ? const [
                      ListTile(
                        leading: CircularProgressIndicator(),
                        title: Text('กำลังโหลดประวัติบิล...'),
                      ),
                    ]
                  : (billsProvider.bills.isEmpty
                      ? const [
                          ListTile(
                            title: Text('ยังไม่มีประวัติบิล'),
                          ),
                        ]
                      : billsProvider.bills.map((b) {
                          final billId = b['billId']?.toString() ??
                              b['id']?.toString() ??
                              '';
                          final dateTime =
                              b['dateTime']?.toString() ?? '';
                          final method =
                              b['paymentMethod']?.toString() ?? '';
                          final total =
                              b['totalAmount']?.toString() ?? '';
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.receipt_long),
                              title: Text(billId),
                              subtitle: Text(
                                  '$dateTime  •  $method  •  ฿$total'),
                              trailing:
                                  PopupMenuButton<String>(
                                onSelected: (value) {
                                  // TODO: handle view / cancel
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'view',
                                    child: Text('ดูรายละเอียดบิล'),
                                  ),
                                  PopupMenuItem(
                                    value: 'cancel',
                                    child: Text('ยกเลิกบิล'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList()),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// 10) /assets/qr-image – ตั้งค่า QR Payment
// ======================================================================

class QrPaymentSettingsSection extends StatelessWidget {
  const QrPaymentSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final assetsProvider = context.watch<AssetsProvider>();
    final token = auth.token ?? '';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  if (token.isEmpty) return;
                  context.read<AssetsProvider>().loadQrImage(token);
                },
                icon: const Icon(Icons.qr_code_2),
                label: const Text('โหลด QR สำหรับหน้าชำระเงิน'),
              ),
              const SizedBox(width: 8),
              if (assetsProvider.isLoading)
                const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (assetsProvider.error != null)
            Text(
              assetsProvider.error!,
              style: const TextStyle(color: Colors.red),
            ),
          const SizedBox(height: 8),
          if (assetsProvider.qrImage != null)
            Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Image.memory(
                    assetsProvider.qrImage!,
                    width: 200,
                    height: 200,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            )
          else
            const Center(
              child: Text(
                'ยังไม่มี QR โหลดขึ้นมา\nกดปุ่มด้านบนเพื่อโหลดรูป QR จากระบบ',
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}