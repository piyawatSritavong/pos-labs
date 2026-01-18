import 'package:flutter/material.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/screens/home_screen.dart';

/// หน้าจอหลังบ้านสำหรับแอดมิน ใช้จัดการ:
/// - Users
/// - User Branches
/// - Company
/// - Branches
/// - POS devices
/// - Parts (สินค้า)
/// - Addresses (สต็อกตามที่เก็บ)
/// - Promotions
/// - Bills history
/// - Payment / QR settings

class BackofficeScreen extends StatefulWidget {
  const BackofficeScreen({super.key});

  @override
  State<BackofficeScreen> createState() => _BackofficeScreenState();
}

class _BackofficeScreenState extends State<BackofficeScreen> {
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
    return Container
    (
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
                    item.pageIndex != null && item.pageIndex == selectedPageIndex;

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
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
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
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  // TODO: เปิดฟอร์มสร้างสาขาใหม่
                },
                icon: const Icon(Icons.add_business),
                label: const Text('เพิ่มสาขาใหม่'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  // TODO: refresh branches
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
                rows: [
                  DataRow(
                    cells: [
                      const DataCell(Text('B001')),
                      const DataCell(Text('Main Branch')),
                      const DataCell(Text('Bangkok')),
                      const DataCell(Text('02-000-0000')),
                      const DataCell(Text('main@example.com')),
                      DataCell(
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.store),
                              tooltip: 'ดูคลัง/Store ภายในสาขานี้',
                              onPressed: () {
                                // TODO: แสดง store ภายในสาขา
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
                                // TODO: ลบสาขา
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
// 5) /pos – เครื่อง POS
// ======================================================================

class PosManagementSection extends StatelessWidget {
  const PosManagementSection({super.key});

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
                  // TODO: เปิดฟอร์มสร้าง POS ใหม่
                },
                icon: const Icon(Icons.point_of_sale),
                label: const Text('สร้าง POS ใหม่'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  // TODO: รีเฟรชรายการ POS
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
                rows: [
                  DataRow(
                    cells: [
                      const DataCell(Text('POS001')),
                      const DataCell(Text('Counter 1')),
                      const DataCell(Text('B001')),
                      const DataCell(
                        Icon(Icons.check_circle, color: Colors.green),
                      ),
                      DataCell(
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.power_settings_new),
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
// 6) /parts – สินค้า
// ======================================================================

class PartsManagementSection extends StatelessWidget {
  const PartsManagementSection({super.key});

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
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'ค้นหาสินค้า (ชื่อ, code, barcode)...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (value) {
                    // TODO: searchParts(...)
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
              children: const [
                ListTile(
                  leading: Icon(Icons.inventory_2),
                  title: Text('P001 - น้ำดื่ม 600ml'),
                  subtitle: Text('Barcode: 8850000000000  •  Unit: ขวด'),
                  trailing: Text('฿10.00'),
                ),
                ListTile(
                  leading: Icon(Icons.inventory_2),
                  title: Text('P002 - น้ำดื่ม 600ml (ลัง)'),
                  subtitle: Text('Barcode: 8850000000001  •  Unit: ลัง'),
                  trailing: Text('฿220.00'),
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
                  // TODO: โหลดรายการโปรโมชั่น
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
                rows: [
                  DataRow(
                    cells: [
                      const DataCell(Text('DISC10')),
                      const DataCell(Text('ส่วนลด 10% ทั้งบิล')),
                      const DataCell(Text('%')),
                      const DataCell(Text('10')),
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
// 9) /bills – ประวัติการขาย
// ======================================================================

class BillsHistorySection extends StatelessWidget {
  const BillsHistorySection({super.key});

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
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'ค้นหาตาม Bill ID หรือคำค้นอื่น ๆ',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (value) {
                    // TODO: โหลด /bills ด้วย filter
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  // TODO: ใส่ date range picker
                },
                icon: const Icon(Icons.date_range),
                label: const Text('เลือกช่วงวันที่'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long),
                    title: const Text('BILL-20260101-0001'),
                    subtitle: const Text(
                      '01/01/2026  10:30  •  Cash  •  ฿350.00',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        // TODO: handle action
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'view',
                          child: Text('ดูรายละเอียดบิล'),
                        ),
                        const PopupMenuItem(
                          value: 'cancel',
                          child: Text('ยกเลิกบิล'),
                        ),
                      ],
                    ),
                    onTap: () {
                      // TODO: เปิด dialog แสดงรายละเอียดบิล (GET /bills/:id)
                    },
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
// 10) /assets/qr-image – ตั้งค่า QR Payment
// ======================================================================

class QrPaymentSettingsSection extends StatelessWidget {
  const QrPaymentSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ตัวอย่าง QR ปัจจุบัน',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Center(
                              child: Container(
                                width: 200,
                                height: 200,
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: Text('Preview QR\n(โหลดจาก backend)'),
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                // TODO: โหลดภาพจาก ApiBillsService.getQrImage(...)
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('รีเฟรชรูป'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 1,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'อัปโหลด QR ใหม่',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'รองรับไฟล์ .png / .jpg\n'
                            'ควรเป็น QR Static หรือ PromptPay ที่ร้านใช้จริง',
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () {
                              // TODO: เปิด file picker แล้ว uploadQrImage(...)
                            },
                            icon: const Icon(Icons.upload),
                            label: const Text('เลือกไฟล์และอัปโหลด'),
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
