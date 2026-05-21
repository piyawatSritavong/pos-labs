import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:frontend/widgets/backoffice/addresses_page.dart';
import 'package:frontend/widgets/backoffice/barcode_print_page.dart';
import 'package:frontend/widgets/backoffice/bills_history_page.dart';
import 'package:frontend/widgets/backoffice/branches_page.dart';
import 'package:frontend/widgets/backoffice/company_page.dart';
import 'package:frontend/widgets/backoffice/parts_page.dart';
import 'package:frontend/widgets/backoffice/payment_page.dart';
import 'package:frontend/widgets/backoffice/pos_devices_page.dart';
import 'package:frontend/widgets/backoffice/promotions_page.dart';
import 'package:frontend/widgets/backoffice/reports_page.dart';
import 'package:frontend/widgets/backoffice/returns_history_page.dart';
import 'package:frontend/widgets/backoffice/members_page.dart';
import 'package:frontend/widgets/backoffice/user_branches_page.dart';
import 'package:frontend/widgets/backoffice/user_page.dart';
import 'package:frontend/widgets/backoffice/inventory_transfer_page.dart';
import 'package:frontend/widgets/backoffice/cash_reconciliation_page.dart';
import 'package:frontend/widgets/backoffice/stock_variance_page.dart';
import 'package:frontend/widgets/backoffice/support_pos_page.dart';
import 'package:provider/provider.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/login_screen.dart';

import 'package:frontend/services/api_service.dart';

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
    // Default raised to 2000 so the Parts page shows the full real-data
    // catalog (~1,566 rows) without pagination UI. Backend MaxLimit is 2000.
    int limit = 2000,
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
    String? memberId,
    List<String>? statuses,
    bool includeDetails = false,
    String scope = 'branch',
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
        memberId: memberId,
        statuses: statuses,
        includeDetails: includeDetails,
        scope: scope,
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
      subtitle: 'Manage employee accounts',
    ),
    _SidebarItem(
      label: 'User-Branches',
      page: 'User-Branch Access',
      icon: Icons.account_tree_outlined,
      pageIndex: 1,
      subtitle: 'Assign branches to users',
    ),
    _SidebarItem(
      label: 'Company',
      page: 'Company Settings',
      icon: Icons.business_outlined,
      pageIndex: 2,
      subtitle: 'Configure company profile',
    ),
    _SidebarItem(
      label: 'Branches',
      page: 'Branch Management',
      icon: Icons.store_outlined,
      pageIndex: 3,
      subtitle: 'Manage branches and stores',
    ),
    _SidebarItem(
      label: 'POS',
      page: 'POS Management',
      icon: Icons.point_of_sale_outlined,
      pageIndex: 4,
      subtitle: 'Manage POS terminals',
    ),

    _SidebarItem(label: 'MASTER DATA', isHeader: true),
    _SidebarItem(
      label: 'Parts',
      page: 'Product Master',
      icon: Icons.inventory_2_outlined,
      pageIndex: 5,
      subtitle: 'Product master data',
    ),
    _SidebarItem(
      label: 'Addresses',
      page: 'Stock / Inventory',
      icon: Icons.warehouse_outlined,
      pageIndex: 6,
      subtitle: 'Inventory by store and shelf',
    ),
    _SidebarItem(
      label: 'Promotions',
      page: 'Promotions Management',
      icon: Icons.local_offer_outlined,
      pageIndex: 7,
      subtitle: 'Discount and promotion rules',
    ),
    _SidebarItem(
      label: 'Members',
      page: 'Members Management',
      icon: Icons.badge_outlined,
      pageIndex: 8,
      subtitle: 'Manage member profiles and points',
    ),
    _SidebarItem(
      label: 'พิมพ์บาร์โค้ด',
      page: 'พิมพ์บาร์โค้ด',
      icon: Icons.qr_code_2_outlined,
      pageIndex: 17,
      subtitle: 'เลือกสินค้าและจำนวน จากนั้นพิมพ์ลงกระดาษ A4',
    ),

    _SidebarItem(label: 'OPERATIONS / REPORTS', isHeader: true),
    _SidebarItem(
      label: 'Bills',
      page: 'Bills History',
      icon: Icons.receipt_long_outlined,
      pageIndex: 9,
      subtitle: 'Sales history and bill details',
    ),
    _SidebarItem(
      label: 'Returns',
      page: 'Returns / Credit Notes',
      icon: Icons.assignment_return_outlined,
      pageIndex: 10,
      subtitle: 'Track refund flow and reference invoices',
    ),
    _SidebarItem(
      label: 'Reports',
      page: 'Report Exports',
      icon: Icons.download_outlined,
      pageIndex: 11,
      subtitle: 'Export CSV reports from backend',
    ),
    _SidebarItem(
      label: 'Payment',
      page: 'Payment Settings',
      icon: Icons.qr_code_2_outlined,
      pageIndex: 12,
      subtitle: 'QR payment settings',
    ),
    _SidebarItem(
      label: 'Transfers',
      page: 'Inventory Transfer',
      icon: Icons.local_shipping_outlined,
      pageIndex: 13,
      subtitle: 'โอนย้ายสินค้า HQ → รถ',
    ),
    _SidebarItem(
      label: 'Cash Recon',
      page: 'Cash Reconciliation',
      icon: Icons.account_balance_wallet_outlined,
      pageIndex: 14,
      subtitle: 'ยืนยันรับเงินจากรถ',
    ),
    _SidebarItem(
      label: 'Variance',
      page: 'Stock Variance',
      icon: Icons.compare_arrows_outlined,
      pageIndex: 15,
      subtitle: 'รายงานส่วนต่างสต๊อก',
    ),
    _SidebarItem(label: 'SUPPORT', isHeader: true),
    _SidebarItem(
      label: 'Support POS',
      page: 'Support POS',
      icon: Icons.support_agent_outlined,
      pageIndex: 16,
      subtitle: 'Monitor หน้าจอ Van Staff แบบ Real-time',
    ),
  ];

  // pages for each logical menu (indexed by pageIndex above)
  final List _pages = const [
    UsersManagementSection(),
    UserBranchesSection(),
    CompanySettingsSection(),
    BranchesManagementSection(),
    PosManagementSection(),
    PartsManagementSection(),
    AddressesManagementSection(),
    PromotionsManagementSection(),
    MembersManagementSection(),
    BillsHistorySection(),
    ReturnsHistorySection(),
    ReportsExportSection(),
    QrPaymentSettingsSection(),
    InventoryTransferPage(),
    CashReconciliationPage(),
    StockVariancePage(),
    SupportPosPage(),
    BarcodePrintPage(), // index 17 — admin-only (hidden for hq_manager)
  ];

  int _currentPageIndex = 0; // default to Users page (adjusted by role in didChangeDependencies)
  bool _pageInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_pageInitialized) {
      _pageInitialized = true;
      final auth = context.read<AuthProvider>();
      if (!auth.isSuperAdmin) {
        // HQ Manager starts at Users (index 0) — now visible
        _currentPageIndex = 0;
      }
    }
  }

  List<_SidebarItem> _getVisibleItems(AuthProvider auth) {
    if (auth.isSuperAdmin) return _sidebarItems;
    // HQ Manager: hide User-Branches/Company/Branches/POS (1-4), Payment (12),
    // SUPPORT (16), and "พิมพ์บาร์โค้ด" (17 — admin-only feature).
    // Users (0) stays visible so HQ Manager can manage Van Staff accounts
    const hiddenPageIndices = {1, 2, 3, 4, 12, 16, 17};
    return _sidebarItems.where((item) {
      if (item.isHeader) {
        if (item.label == 'SUPPORT') return false;
        return true; // show ORGANIZATION (Users page still visible under it)
      }
      if (item.pageIndex == null) return true;
      return !hiddenPageIndices.contains(item.pageIndex);
    }).toList();
  }

  String get _currentPageTitle {
    final item = _sidebarItems.firstWhere(
      (item) => !item.isHeader && item.pageIndex == _currentPageIndex,
      orElse: () => const _SidebarItem(label: 'Backoffice', page: 'Backoffice'),
    );
    return item.page ?? item.label;
  }

  String? get _currentPageSubtitle {
    final item = _sidebarItems.firstWhere(
      (item) => !item.isHeader && item.pageIndex == _currentPageIndex,
      orElse: () => const _SidebarItem(label: 'Backoffice', page: 'Backoffice'),
    );
    return item.subtitle;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final visibleItems = _getVisibleItems(auth);
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BackofficeSidebar(
            items: visibleItems,
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
                _BackofficeTopBar(
                  title: _currentPageTitle,
                  subtitle: _currentPageSubtitle,
                ),
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
    this.subtitle,
  });

  final String label;
  final String? page;
  final String? subtitle;
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 260,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(right: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // ไจ๊เฮง brand logo. Falls back to icon if image fails to load.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/images/logoJaiHeng.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.dashboard_customize,
                    color: cs.primary,
                  ),
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
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurfaceVariant,
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
                            ? cs.primary.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          if (item.icon != null)
                            Icon(
                              item.icon,
                              color: isActive ? cs.primary : cs.onSurfaceVariant,
                            ),
                          if (item.icon != null) const SizedBox(width: 12),
                          Text(
                            item.label,
                            style: TextStyle(
                              color: isActive ? cs.primary : cs.onSurfaceVariant,
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
  const _BackofficeTopBar({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeProvider = context.watch<ThemeProvider>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const Spacer(),
          PopupMenuButton<String>(
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: cs.primary.withValues(alpha: 0.12),
              child: Icon(Icons.person, color: cs.primary),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'theme',
                child: Row(
                  children: [
                    Icon(
                      themeProvider.isDark ? Icons.dark_mode : Icons.light_mode,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(themeProvider.isDark ? 'Dark Mode' : 'Light Mode'),
                  ],
                ),
              ),
              const PopupMenuItem(value: 'logout', child: Text('ออกจากระบบ')),
            ],
            onSelected: (value) async {
              if (value == 'theme') {
                context.read<ThemeProvider>().toggle();
              } else if (value == 'logout') {
                await context.read<AuthProvider>().logout();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
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
