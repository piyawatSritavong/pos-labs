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
import 'package:frontend/widgets/backoffice/pos_restock_requests_page.dart';
import 'package:frontend/widgets/backoffice/cash_reconciliation_page.dart';
import 'package:frontend/widgets/backoffice/stock_variance_page.dart';
import 'package:frontend/widgets/backoffice/support_pos_page.dart';
import 'package:frontend/widgets/session_guard.dart';
import 'package:provider/provider.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/home_screen.dart';
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
//
// Server-side search + paging: instead of pulling the whole catalog (~1,500
// rows) and filtering in Dart, we fetch one page at a time via /parts/search
// (which now also batches address lookups, so it is no longer N+1). An empty
// query lists all parts, paged.
class PartsProvider extends ChangeNotifier {
  bool isLoading = false;
  String? error;
  List<Map<String, dynamic>> parts = [];
  String query = '';
  String? storeId; // คลังสินค้าที่เลือกกรอง (null = ทุกคลัง)
  int offset = 0;
  int pageSize = 50; // selectable page size (20/50/100)
  int total = 0; // total matching parts (for page-jump)
  bool hasMore = false;

  int get pageCount => pageSize <= 0 ? 1 : ((total + pageSize - 1) ~/ pageSize);
  int get currentPage => pageSize <= 0 ? 1 : (offset ~/ pageSize) + 1;

  Future<void> load(String token, {String? query, int offset = 0}) async {
    if (query != null) this.query = query;
    this.offset = offset;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final result = await ApiService.searchPartsPaged(
        token: token,
        query: this.query,
        limit: pageSize,
        offset: offset,
        // Admin catalog view: show every part, including ones with no stock in
        // the admin's branch (e.g. a product just created). Without this the
        // branch-scoped search hides newly added products entirely.
        crossBranch: true,
        storeId: storeId,
      );
      parts = result.parts;
      total = result.total;
      hasMore = offset + parts.length < total;
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> nextPage(String token) async {
    if (!hasMore) return;
    await load(token, offset: offset + pageSize);
  }

  Future<void> prevPage(String token) async {
    if (offset <= 0) return;
    await load(token, offset: (offset - pageSize).clamp(0, offset));
  }

  // Jump to a 1-based page number.
  Future<void> goToPage(String token, int page) async {
    final p = page.clamp(1, pageCount == 0 ? 1 : pageCount);
    await load(token, offset: (p - 1) * pageSize);
  }

  // Change page size and reload from the first page.
  Future<void> setPageSize(String token, int size) async {
    pageSize = size;
    await load(token, offset: 0);
  }

  // Backward-compatible entry points used by the Parts page.
  Future<void> fetchParts(String token) => load(token, query: '', offset: 0);
  Future<void> search(String token, {String query = ''}) =>
      load(token, query: query, offset: 0);
}

// 5) Addresses (/addresses)
//
// Server-side search + paging via /addresses?q=&storeId=&limit=&offset= instead
// of loading the whole catalog and filtering in Dart.
class AddressesProvider extends ChangeNotifier {
  static const int pageSize = 50;

  bool isLoading = false;
  String? error;
  List<Map<String, dynamic>> addresses = [];
  String query = '';
  String? storeId;
  int offset = 0;
  bool hasMore = false;

  Future<void> load(
    String token, {
    String? query,
    String? storeId,
    bool clearStore = false,
    int offset = 0,
  }) async {
    if (query != null) this.query = query;
    if (clearStore) {
      this.storeId = null;
    } else if (storeId != null) {
      this.storeId = storeId;
    }
    this.offset = offset;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final results = await ApiService.getAddresses(
        token: token,
        limit: pageSize,
        offset: offset,
        query: this.query,
        storeId: this.storeId,
      );
      addresses = results;
      hasMore = results.length == pageSize;
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> nextPage(String token) async {
    if (!hasMore) return;
    await load(token, offset: offset + pageSize);
  }

  Future<void> prevPage(String token) async {
    if (offset <= 0) return;
    await load(token, offset: (offset - pageSize).clamp(0, offset));
  }

  // Backward-compatible entry point used by the Addresses page.
  Future<void> fetchAddresses(String token) => load(token, offset: 0);
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
      child: const SessionGuard(child: _BackofficeShell()),
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
  // NOTE: Thai labels are display-only; `pageIndex` (the "path" into _pages)
  // is unchanged. Order of entries = display order. All features are enabled
  // on this branch (client-ppsale/demo); the jaiheng deploy branch hides some.
  final List<_SidebarItem> _sidebarItems = const [
    _SidebarItem(label: 'องค์กร', isHeader: true),
    _SidebarItem(
      label: 'พนักงาน',
      page: 'จัดการพนักงาน',
      icon: Icons.people_alt_outlined,
      pageIndex: 0,
      subtitle: 'จัดการบัญชีพนักงาน',
    ),
    _SidebarItem(
      label: 'สาขา',
      page: 'จัดการสาขา',
      icon: Icons.store_outlined,
      pageIndex: 3,
      subtitle: 'จัดการสาขาและร้าน',
    ),
    _SidebarItem(
      label: 'พนักงานในสาขา',
      page: 'พนักงานในสาขา',
      icon: Icons.account_tree_outlined,
      pageIndex: 1,
      subtitle: 'กำหนดสาขาให้พนักงาน',
    ),
    _SidebarItem(
      label: 'ข้อมูลบริษัท',
      page: 'ตั้งค่าบริษัท',
      icon: Icons.business_outlined,
      pageIndex: 2,
      subtitle: 'ตั้งค่าโปรไฟล์บริษัท',
    ),
    _SidebarItem(
      label: 'ขายสินค้า (POS)',
      page: 'ขายสินค้า (POS)',
      icon: Icons.point_of_sale_outlined,
      pageIndex: 4,
      subtitle: 'ขายสินค้าเหมือนพนักงานหน้ารถ',
    ),

    _SidebarItem(label: 'ข้อมูลหลัก', isHeader: true),
    _SidebarItem(
      label: 'สินค้า',
      page: 'ข้อมูลสินค้า',
      icon: Icons.inventory_2_outlined,
      pageIndex: 5,
      subtitle: 'ข้อมูลหลักสินค้า',
    ),
    _SidebarItem(
      label: 'คลังสินค้า',
      page: 'คลัง / สต๊อก',
      icon: Icons.warehouse_outlined,
      pageIndex: 6,
      subtitle: 'สต๊อกตามร้านและชั้นวาง',
    ),
    _SidebarItem(
      label: 'สมาชิก',
      page: 'จัดการสมาชิก',
      icon: Icons.badge_outlined,
      pageIndex: 8,
      subtitle: 'จัดการข้อมูลและแต้มสมาชิก',
    ),
    _SidebarItem(
      label: 'พิมพ์บาร์โค้ด',
      page: 'พิมพ์บาร์โค้ด',
      icon: Icons.qr_code_2_outlined,
      pageIndex: 17,
      subtitle: 'เลือกสินค้าและจำนวน จากนั้นพิมพ์ฉลาก',
    ),

    _SidebarItem(label: 'การขาย / รายงาน', isHeader: true),
    _SidebarItem(
      label: 'ประวัติการขาย',
      page: 'ประวัติการขาย',
      icon: Icons.receipt_long_outlined,
      pageIndex: 9,
      subtitle: 'ประวัติการขายและรายละเอียดบิล',
    ),
    _SidebarItem(
      label: 'คืนสินค้า',
      page: 'คืนสินค้า / ใบลดหนี้',
      icon: Icons.assignment_return_outlined,
      pageIndex: 10,
      subtitle: 'ติดตามการคืนเงินและบิลอ้างอิง',
    ),
    _SidebarItem(
      label: 'รายงาน',
      page: 'ส่งออกรายงาน',
      icon: Icons.download_outlined,
      pageIndex: 11,
      subtitle: 'ส่งออกรายงาน CSV',
    ),
    _SidebarItem(
      label: 'ตั้งค่าการชำระเงิน',
      page: 'ตั้งค่าการชำระเงิน',
      icon: Icons.qr_code_2_outlined,
      pageIndex: 12,
      subtitle: 'ตั้งค่า QR รับเงิน',
    ),
    _SidebarItem(
      label: 'โอนสินค้า',
      page: 'โอนย้ายสินค้า',
      icon: Icons.local_shipping_outlined,
      pageIndex: 13,
      subtitle: 'โอนย้ายสินค้า HQ → รถ',
    ),
    _SidebarItem(
      label: 'ใบเบิกสินค้าเข้ารถ',
      page: 'ใบเบิกสินค้าเข้ารถ',
      icon: Icons.assignment_turned_in_outlined,
      pageIndex: 18,
      subtitle: 'ตรวจเอกสารเบิกสินค้าและยืนยันโอนเข้ารถ',
    ),
    _SidebarItem(
      label: 'รายงานปิดยอดประจำวัน',
      page: 'รายงานปิดยอดประจำวัน',
      icon: Icons.account_balance_wallet_outlined,
      pageIndex: 14,
      subtitle: 'ยอดปิดประจำวันที่ POS ส่งมา และยืนยันรับเงิน',
    ),
    _SidebarItem(
      label: 'ส่วนต่างสต๊อก',
      page: 'รายงานส่วนต่างสต๊อก',
      icon: Icons.compare_arrows_outlined,
      pageIndex: 15,
      subtitle: 'รายงานส่วนต่างสต๊อก',
    ),
    _SidebarItem(label: 'ช่วยเหลือ', isHeader: true),
    _SidebarItem(
      label: 'มอนิเตอร์ POS',
      page: 'มอนิเตอร์ POS',
      icon: Icons.support_agent_outlined,
      pageIndex: 16,
      subtitle: 'ดูหน้าจอพนักงานหน้ารถแบบเรียลไทม์',
    ),
  ];

  // Hidden by request: Promotions (7) and POS device management (19). Their
  // sidebar entries are removed and the pages blocked even if reached
  // programmatically.
  static const Set<int> _blockedPageIndices = {7, 19};

  // pages for each logical menu (indexed by pageIndex above)
  final List _pages = const [
    UsersManagementSection(),
    UserBranchesSection(),
    CompanySettingsSection(),
    BranchesManagementSection(),
    HomeScreen(embedded: true), // index 4 — admin POS sell page (was POS Management)
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
    PosRestockRequestsPage(),
    PosManagementSection(), // index 19 — จัดการเครื่อง POS (admin-only)
  ];

  int _currentPageIndex =
      0; // default to Users page (adjusted by role in didChangeDependencies)
  bool _pageInitialized = false;
  // Collapsed state hides BOTH the left sidebar and the top header bar.
  bool _sidebarCollapsed = false;

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
    // SUPPORT (16), "พิมพ์บาร์โค้ด" (17) and เครื่อง POS (19) — admin-only.
    // Users (0) stays visible so HQ Manager can manage POS Staff accounts
    const hiddenPageIndices = {1, 2, 3, 4, 12, 16, 17, 19};
    return _sidebarItems.where((item) {
      if (item.isHeader) {
        if (item.label == 'ช่วยเหลือ') return false;
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
    final cs = Theme.of(context).colorScheme;

    // Guard: blocked pages cannot be opened even if the index is set somehow.
    final bool blocked = _blockedPageIndices.contains(_currentPageIndex);
    // The POS sell page brings its own Scaffold/header, so render it full-bleed.
    final bool isPosPage = _currentPageIndex == 4;

    final Widget body;
    if (blocked) {
      body = const Center(child: Text('ไม่สามารถเข้าถึงเมนูนี้'));
    } else if (isPosPage) {
      body = _pages[_currentPageIndex];
    } else {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: _pages[_currentPageIndex],
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_sidebarCollapsed)
                _BackofficeSidebar(
                  items: visibleItems,
                  selectedPageIndex: _currentPageIndex,
                  onSelectPage: (pageIndex) {
                    setState(() {
                      _currentPageIndex = pageIndex;
                    });
                  },
                  onToggleCollapse: () =>
                      setState(() => _sidebarCollapsed = true),
                ),
              Expanded(
                child: Column(
                  children: [
                    if (!_sidebarCollapsed)
                      _BackofficeTopBar(
                        title: _currentPageTitle,
                        subtitle: _currentPageSubtitle,
                      ),
                    Expanded(child: body),
                  ],
                ),
              ),
            ],
          ),
          // Persistent re-open button (same top-left corner) shown only when
          // collapsed — pressing it brings back the sidebar + header.
          if (_sidebarCollapsed)
            Positioned(
              top: 8,
              left: 8,
              child: SafeArea(
                child: Material(
                  color: cs.surface,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: IconButton(
                    icon: const Icon(Icons.menu),
                    tooltip: 'แสดงเมนู',
                    onPressed: () =>
                        setState(() => _sidebarCollapsed = false),
                  ),
                ),
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
    required this.onToggleCollapse,
  });

  final List<_SidebarItem> items;
  final int selectedPageIndex;
  final ValueChanged<int> onSelectPage;
  final VoidCallback onToggleCollapse;

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
                  'assets/images/pp-logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.dashboard_customize, color: cs.primary),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.menu_open),
                tooltip: 'ซ่อนเมนู',
                onPressed: onToggleCollapse,
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
                              color: isActive
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                            ),
                          if (item.icon != null) const SizedBox(width: 12),
                          Text(
                            item.label,
                            style: TextStyle(
                              color: isActive
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
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
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
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
