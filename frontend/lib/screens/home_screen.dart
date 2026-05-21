import 'package:flutter/material.dart';
import 'package:frontend/screens/backoffice_screen.dart';
import 'package:frontend/services/api_bills.dart';
import 'package:provider/provider.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/widgets/pos/stock_dialog.dart';
import 'package:frontend/widgets/pos/bill_log_dialog.dart';
import 'package:frontend/widgets/pos/hold_bill_dialog.dart';
import 'package:frontend/widgets/pos/search_parts_dialog.dart';
import 'package:frontend/widgets/pos/cart_summary_section.dart';
import 'package:frontend/widgets/pos/search_barcode_section.dart';
import 'package:frontend/widgets/pos/return_reference_dialog.dart';
import 'package:frontend/widgets/pos/member_register_dialog.dart';
import 'package:frontend/widgets/pos/physical_count_dialog.dart';
import 'package:frontend/widgets/pos/daily_close_dialog.dart';
import 'package:frontend/widgets/pos/requisition_dialog.dart';
import 'package:frontend/providers/bill_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/services/pos_mirror_service.dart';

enum _ScreenMode { desktop, tablet, mobile }

_ScreenMode _posScreenMode(double width) {
  if (width >= 1100) return _ScreenMode.desktop;
  if (width >= 600) return _ScreenMode.tablet;
  return _ScreenMode.mobile;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static void Function()? openCustomerWindowFn;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final GlobalKey<SearchBarcodeSectionState> _productListKey =
      GlobalKey<SearchBarcodeSectionState>();
  final FocusNode _barcodeFocusNode = FocusNode();
  bool _isCheckingPendingBill = true;
  final PosMirrorService _posMirrorService = PosMirrorService();
  int _holdCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.isAuthenticated && auth.hasBackofficeAccess) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const BackofficeScreen()),
          (route) => false,
        );
        return;
      }
      _handlePendingBillOnLaunch();
      _loadHoldCount();

      // Start broadcasting POS state for cashier/van POS sessions.
      if (auth.isPOSOperator && auth.token != null) {
        final billProvider = context.read<BillProvider>();
        _posMirrorService.connect(
          buildPosMirrorWsUrl(auth.token!),
          billProvider,
        );
      }
    });
  }

  Future<void> _loadHoldCount() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null) return;
    try {
      final bills = await ApiBillsService.getBills(
        token: token,
        limit: 100,
        offset: 0,
        statuses: const ['hold'],
        scope: 'pos',
      );
      if (mounted) setState(() => _holdCount = bills.length);
    } catch (_) {
      // ignore badge errors
    }
  }

  @override
  void dispose() {
    _posMirrorService.dispose();
    _barcodeFocusNode.dispose();
    _searchController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcodeSearch(
    String code, {
    bool clearOnSuccess = false,
  }) async {
    final upper = code.toUpperCase();
    _barcodeController.value = _barcodeController.value.copyWith(
      text: upper,
      selection: TextSelection.collapsed(offset: upper.length),
    );
    if (upper.isNotEmpty) PosMirrorService.current?.notifyBarcode(upper);
    await _productListKey.currentState?.searchByBarcode(upper);
    if (!mounted) return;
    if (clearOnSuccess) {
      _barcodeController.clear();
      await _productListKey.currentState?.searchByBarcode('');
    }
  }

  Future<void> _openSearchDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const SearchPartsDialog(),
    );
  }

  Future<void> _handlePendingBillOnLaunch() async {
    final auth = context.read<AuthProvider>();
    final billProvider = context.read<BillProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final token = auth.token;

    if (token == null) {
      if (mounted) {
        setState(() {
          _isCheckingPendingBill = false;
        });
      }
      return;
    }

    try {
      final pendingBills = await ApiBillsService.getBills(
        token: token,
        limit: 1,
        offset: 0,
        statuses: const ['new'],
        includeDetails: true,
        scope: 'pos',
      );
      if (!mounted) return;

      if (pendingBills.isEmpty) {
        billProvider.resetCurrentBillState();
        return;
      }

      final pendingBill = Map<String, dynamic>.from(pendingBills.first);
      final shouldContinue = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PendingBillDialog(bill: pendingBill),
      );
      if (!mounted) return;

      if (shouldContinue == true) {
        billProvider.loadBillSnapshot(pendingBill);
        return;
      }

      final pendingBillId = pendingBill['id']?.toString() ?? '';
      if (pendingBillId.isEmpty) {
        billProvider.resetCurrentBillState();
        return;
      }

      try {
        await ApiBillsService.cancelBill(token: token, billId: pendingBillId);
        billProvider.resetCurrentBillState();
        messenger.showSnackBar(
          const SnackBar(content: Text('ยกเลิกบิลที่ค้างอยู่แล้ว')),
        );
      } catch (e) {
        billProvider.loadBillSnapshot(pendingBill);
        messenger.showSnackBar(
          SnackBar(content: Text('ยกเลิกบิลที่ค้างอยู่ไม่สำเร็จ: $e')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('ตรวจสอบบิลที่ค้างอยู่ไม่สำเร็จ: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingPendingBill = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final bill = context.watch<BillProvider>();
    final mode = _posScreenMode(MediaQuery.of(context).size.width);

    if (_isCheckingPendingBill) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'กำลังตรวจสอบบิลที่ค้างอยู่...',
                  style: TextStyle(color: context.colorMuted),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(child: _buildForMode(context, mode, auth, bill)),
      bottomNavigationBar: null,
    );
  }

  Widget _buildForMode(
    BuildContext context,
    _ScreenMode mode,
    AuthProvider auth,
    BillProvider bill,
  ) {
    switch (mode) {
      case _ScreenMode.desktop:
        return _buildDesktopLayout(context, auth);
      case _ScreenMode.tablet:
        return _buildTabletLayout(context, auth);
      case _ScreenMode.mobile:
        return _buildMobileLayout(context, auth, bill);
    }
  }

  Widget _buildDesktopLayout(BuildContext context, AuthProvider auth) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeaderBar(
            authName: auth.name ?? 'ร้านตัวอย่าง',
            searchController: _searchController,
            onSearchTap: _openSearchDialog,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: SearchBarcodeSection(key: _productListKey),
                ),
                const SizedBox(width: 20),
                const Expanded(flex: 7, child: CartSummarySection()),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _BarcodeQuickAction(
            controller: _barcodeController,
            focusNode: _barcodeFocusNode,
            onChanged: _handleBarcodeSearch,
            onSubmit: (value) =>
                _handleBarcodeSearch(value, clearOnSuccess: true),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout(BuildContext context, AuthProvider auth) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeaderBar(
            authName: auth.name ?? 'ร้านตัวอย่าง',
            searchController: _searchController,
            onSearchTap: _openSearchDialog,
            isTablet: true,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: SearchBarcodeSection(key: _productListKey),
                ),
                const SizedBox(width: 16),
                const Expanded(flex: 6, child: CartSummarySection()),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _BarcodeQuickAction(
            controller: _barcodeController,
            focusNode: _barcodeFocusNode,
            onChanged: _handleBarcodeSearch,
            onSubmit: (value) =>
                _handleBarcodeSearch(value, clearOnSuccess: true),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    AuthProvider auth,
    BillProvider bill,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeaderBar(
            authName: auth.name ?? 'ร้านตัวอย่าง',
            searchController: _searchController,
            onSearchTap: _openSearchDialog,
            isMobile: true,
            holdCount: _holdCount,
            onShowActionSheet: () =>
                _showMobileActionSheet(context, auth, bill),
          ),
          // Keep SearchBarcodeSection mounted but hidden so barcode scan + auto-add works
          Offstage(
            offstage: true,
            child: SizedBox(
              width: 300,
              height: 400,
              child: SearchBarcodeSection(
                key: _productListKey,
                itemsPerPage: 4,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Expanded(child: CartSummarySection()),
          const SizedBox(height: 8),
          _BarcodeQuickAction(
            controller: _barcodeController,
            focusNode: _barcodeFocusNode,
            onChanged: _handleBarcodeSearch,
            onSubmit: (value) =>
                _handleBarcodeSearch(value, clearOnSuccess: true),
          ),
        ],
      ),
    );
  }

  void _showMobileActionSheet(
    BuildContext context,
    AuthProvider auth,
    BillProvider bill,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'เมนู',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: _buildActionTiles(context, auth, bill),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildActionTiles(
    BuildContext context,
    AuthProvider auth,
    BillProvider bill,
  ) {
    Widget tile(IconData icon, String label, Color? color, VoidCallback onTap) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: (color ?? Theme.of(context).colorScheme.primary)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color ?? Theme.of(context).colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ],
        ),
      );
    }

    return [
      tile(
        Icons.assignment_return_outlined,
        'คืนสินค้า',
        Theme.of(context).colorScheme.error,
        () {
          PosMirrorService.current?.notifyDialog('return');
          showDialog(
            context: context,
            builder: (_) => const ReturnReferenceDialog(),
          ).then((_) => PosMirrorService.current?.notifyDialog(null));
        },
      ),
      tile(Icons.pause_circle_outline, 'พักบิล', null, () async {
        PosMirrorService.current?.notifyDialog('hold_bill');
        await showDialog(
          context: context,
          builder: (_) => const HoldBillDialog(),
        );
        PosMirrorService.current?.notifyDialog(null);
        _loadHoldCount();
      }),
      tile(
        Icons.warning_amber_rounded,
        'สต็อก',
        Theme.of(context).colorScheme.tertiary,
        () {
          PosMirrorService.current?.notifyDialog('stock');
          showDialog(
            context: context,
            builder: (_) => const StockDialog(),
          ).then((_) => PosMirrorService.current?.notifyDialog(null));
        },
      ),
      tile(Icons.history_rounded, 'ประวัติ', null, () {
        PosMirrorService.current?.notifyDialog('bill_log');
        showDialog(
          context: context,
          builder: (_) => const BillsLogDialog(),
        ).then((_) => PosMirrorService.current?.notifyDialog(null));
      }),
      if (auth.isVanStaff) ...[
        tile(Icons.person_add_outlined, 'สมาชิก', null, () {
          PosMirrorService.current?.notifyDialog('member_register');
          showDialog(
            context: context,
            builder: (_) => const MemberRegisterDialog(),
          ).then((_) => PosMirrorService.current?.notifyDialog(null));
        }),
        tile(Icons.inventory_2_outlined, 'นับสต็อก', null, () {
          PosMirrorService.current?.notifyDialog('physical_count');
          showDialog(
            context: context,
            builder: (_) =>
                PhysicalCountDialog(branchId: auth.branchId ?? '', storeId: ''),
          ).then((_) => PosMirrorService.current?.notifyDialog(null));
        }),
        tile(Icons.calculate_outlined, 'ปิดวัน', null, () {
          PosMirrorService.current?.notifyDialog('daily_close');
          showDialog(
            context: context,
            builder: (_) => DailyCloseDialog(
              branchId: auth.branchId ?? '',
              posId: auth.posId ?? '',
            ),
          ).then((_) => PosMirrorService.current?.notifyDialog(null));
        }),
        tile(
          Icons.request_page_outlined,
          'เบิกของ',
          null,
          () => showDialog(
            context: context,
            builder: (_) => const RequisitionDialog(),
          ),
        ),
      ],
      if (HomeScreen.openCustomerWindowFn != null)
        tile(
          Icons.open_in_new_rounded,
          'หน้าจอลูกค้า',
          null,
          () => HomeScreen.openCustomerWindowFn?.call(),
        ),
    ];
  }
}

class _PendingBillDialog extends StatelessWidget {
  const _PendingBillDialog({required this.bill});

  final Map<String, dynamic> bill;

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  List<Map<String, dynamic>> _extractItems() {
    const possibleKeys = ['items', 'details', 'billItems', 'lineItems'];
    for (final key in possibleKeys) {
      final value = bill[key];
      if (value is List) {
        return value.whereType<Map<String, dynamic>>().toList();
      }
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final billId = bill['id']?.toString() ?? '-';
    final totalQty = bill['totalQty']?.toString() ?? '0';
    final itemCount = bill['itemCount']?.toString() ?? '0';
    final items = _extractItems();
    final totalAmount = _toDouble(
      bill['totalAmount'] ?? bill['purchaseAmount'] ?? bill['total'],
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'บิลที่ค้างอยู่',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'พบบิลที่ยังไม่ปิดการขายบน POS นี้',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colorMuted),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colorBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colorBorder),
                ),
                child: Column(
                  children: [
                    _buildMetaRow(context, 'เลขที่บิล', billId),
                    const SizedBox(height: 6),
                    _buildMetaRow(context, 'จำนวนรายการ', itemCount),
                    const SizedBox(height: 6),
                    _buildMetaRow(context, 'จำนวนสินค้า', '$totalQty ชิ้น'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: context.colorPrimary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: context.colorPrimary.withValues(alpha: 0.18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'รายการสินค้า',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.colorPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: const [
                        Expanded(
                          flex: 6,
                          child: Text(
                            'สินค้า',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'จำนวน',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'ราคา',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'ยังไม่มีรายการสินค้าในบิลนี้',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.colorMuted),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: SingleChildScrollView(
                          child: Column(
                            children: items.map((raw) {
                              final qtyRaw = _toDouble(
                                raw['qty'] ?? raw['quantity'] ?? raw['amount'],
                              );
                              final qty = qtyRaw <= 0 ? 1 : qtyRaw.toInt();
                              final price = _toDouble(
                                raw['unitPrice'] ??
                                    raw['price'] ??
                                    raw['unit_price'],
                              );
                              final total = _toDouble(
                                raw['amount'] ?? raw['total'] ?? price * qty,
                              );
                              final resolvedPrice = price > 0
                                  ? price
                                  : (qty > 0 ? total / qty : total);
                              final name =
                                  raw['nameTh']?.toString() ??
                                  raw['name']?.toString() ??
                                  raw['partName']?.toString() ??
                                  raw['description']?.toString() ??
                                  'สินค้า';
                              final code =
                                  raw['partCode']?.toString() ??
                                  raw['code']?.toString() ??
                                  '-';
                              final lineTotal = resolvedPrice * qty;

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 6,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            code,
                                            style: TextStyle(
                                              color: context.colorMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '$qty',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        '฿${lineTotal.toStringAsFixed(2)}',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: context.colorSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colorBorder),
                ),
                child: _buildMetaRow(
                  context,
                  'ยอดปัจจุบัน',
                  '฿${totalAmount.toStringAsFixed(2)}',
                  emphasize: true,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('ยกเลิก'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('ทำต่อ'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaRow(
    BuildContext context,
    String label,
    String value, {
    bool emphasize = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: emphasize ? context.colorText : context.colorMuted,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: emphasize ? context.colorPrimary : context.colorText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class HeaderBar extends StatelessWidget {
  const HeaderBar({
    super.key,
    required this.authName,
    required this.searchController,
    required this.onSearchTap,
    this.isTablet = false,
    this.isMobile = false,
    this.holdCount = 0,
    this.onShowActionSheet,
  });

  final String authName;
  final TextEditingController searchController;
  final VoidCallback onSearchTap;
  final bool isTablet;
  final bool isMobile;
  final int holdCount;
  final VoidCallback? onShowActionSheet;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: isMobile ? 10 : 16,
      ),
      decoration: BoxDecoration(
        color: context.colorSurface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        boxShadow: AppShadows.soft,
        border: Border.all(color: context.colorBorder),
      ),
      child: Row(
        children: [
          Expanded(child: _buildSearchBar(context)),
          SizedBox(width: isMobile ? 8 : 24),
          if (isMobile)
            _buildMobileActions(context)
          else
            _HeaderActionGroup(authName: authName, isCompact: isTablet),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: searchController,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        final displayText = hasText ? value.text.trim() : 'เลือกสินค้า';
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onSearchTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: context.colorBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: context.colorBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: context.colorMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      displayText,
                      style: TextStyle(
                        color: hasText ? context.colorText : context.colorMuted,
                      ),
                    ),
                  ),
                  if (hasText)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => searchController.clear(),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          color: context.colorMuted,
                          size: 20,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileActions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onShowActionSheet,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.colorBg,
                  border: Border.all(color: context.colorBorder),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.menu, color: context.colorPrimary),
              ),
            ),
            if (holdCount > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: context.colorDanger,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    holdCount > 9 ? '9+' : '$holdCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 8),
        CircleAvatar(
          radius: 20,
          backgroundColor: cs.primary.withValues(alpha: 0.12),
          child: Icon(Icons.person, color: cs.primary),
        ),
      ],
    );
  }
}

class _HeaderActionGroup extends StatefulWidget {
  const _HeaderActionGroup({required this.authName, this.isCompact = false});

  final String authName;
  final bool isCompact;

  @override
  State<_HeaderActionGroup> createState() => _HeaderActionGroupState();
}

class _HeaderActionGroupState extends State<_HeaderActionGroup> {
  int _holdCount = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHoldCount();
    });
  }

  Future<void> _loadHoldCount() async {
    if (_isLoading) return;
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null) return;

    setState(() => _isLoading = true);
    try {
      final bills = await ApiBillsService.getBills(
        token: token,
        limit: 100,
        offset: 0,
        statuses: const ['hold'],
        scope: 'pos',
      );
      final hold = bills.length;
      if (mounted) {
        setState(() {
          _holdCount = hold;
        });
      }
    } catch (_) {
      // ignore badge errors
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final bill = context.watch<BillProvider>();
    final gap = widget.isCompact ? 8.0 : 12.0;
    return Row(
      children: [
        SizedBox(width: gap),
        _HeaderIconButton(
          icon: Icons.assignment_return_outlined,
          iconColor: context.colorDanger,
          badgeCount: bill.returnLineCount,
          isCompact: widget.isCompact,
          onTap: () {
            PosMirrorService.current?.notifyDialog('return');
            showDialog(
              context: context,
              builder: (context) => const ReturnReferenceDialog(),
            ).then((_) => PosMirrorService.current?.notifyDialog(null));
          },
        ),
        SizedBox(width: gap),
        _HeaderIconButton(
          icon: Icons.pause_circle_outline,
          badgeCount: _holdCount,
          isCompact: widget.isCompact,
          onTap: () async {
            PosMirrorService.current?.notifyDialog('hold_bill');
            await showDialog(
              context: context,
              builder: (context) => const HoldBillDialog(),
            );
            PosMirrorService.current?.notifyDialog(null);
            if (mounted) {
              _loadHoldCount();
            }
          },
        ),
        SizedBox(width: gap),
        _HeaderIconButton(
          icon: Icons.warning_amber_rounded,
          iconColor: context.colorAccent,
          isCompact: widget.isCompact,
          onTap: () {
            PosMirrorService.current?.notifyDialog('stock');
            showDialog(
              context: context,
              builder: (context) => const StockDialog(),
            ).then((_) => PosMirrorService.current?.notifyDialog(null));
          },
        ),
        SizedBox(width: gap),
        _HeaderIconButton(
          icon: Icons.history_rounded,
          isCompact: widget.isCompact,
          onTap: () {
            PosMirrorService.current?.notifyDialog('bill_log');
            showDialog(
              context: context,
              builder: (context) => const BillsLogDialog(),
            ).then((_) => PosMirrorService.current?.notifyDialog(null));
          },
        ),
        if (auth.isVanStaff) ...[
          SizedBox(width: gap),
          _HeaderIconButton(
            icon: Icons.person_add_outlined,
            isCompact: widget.isCompact,
            onTap: () {
              PosMirrorService.current?.notifyDialog('member_register');
              showDialog(
                context: context,
                builder: (context) => const MemberRegisterDialog(),
              ).then((_) => PosMirrorService.current?.notifyDialog(null));
            },
          ),
          SizedBox(width: gap),
          _HeaderIconButton(
            icon: Icons.inventory_2_outlined,
            isCompact: widget.isCompact,
            onTap: () {
              PosMirrorService.current?.notifyDialog('physical_count');
              showDialog(
                context: context,
                builder: (context) => PhysicalCountDialog(
                  branchId: auth.branchId ?? '',
                  storeId: '',
                ),
              ).then((_) => PosMirrorService.current?.notifyDialog(null));
            },
          ),
          SizedBox(width: gap),
          _HeaderIconButton(
            icon: Icons.calculate_outlined,
            isCompact: widget.isCompact,
            onTap: () {
              PosMirrorService.current?.notifyDialog('daily_close');
              showDialog(
                context: context,
                builder: (context) => DailyCloseDialog(
                  branchId: auth.branchId ?? '',
                  posId: auth.posId ?? '',
                ),
              ).then((_) => PosMirrorService.current?.notifyDialog(null));
            },
          ),
          SizedBox(width: gap),
          _HeaderIconButton(
            icon: Icons.request_page_outlined,
            isCompact: widget.isCompact,
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => const RequisitionDialog(),
              );
            },
          ),
        ],
        SizedBox(width: gap),
        if (HomeScreen.openCustomerWindowFn != null)
          _HeaderIconButton(
            icon: Icons.open_in_new_rounded,
            isCompact: widget.isCompact,
            onTap: () {
              HomeScreen.openCustomerWindowFn?.call();
            },
          ),
        const SizedBox(width: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                widget.authName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              Text(
                'สาขา 1',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colorMuted.withValues(alpha: 0.9),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Builder(
          builder: (context) {
            final cs = Theme.of(context).colorScheme;
            final themeProvider = context.watch<ThemeProvider>();
            return PopupMenuButton<String>(
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
                        themeProvider.isDark
                            ? Icons.dark_mode
                            : Icons.light_mode,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(themeProvider.isDark ? 'Dark Mode' : 'Light Mode'),
                    ],
                  ),
                ),
                if (auth.hasBackofficeAccess)
                  const PopupMenuItem(value: 'office', child: Text('OFFICE')),
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
                } else if (value == 'office') {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BackofficeScreen()),
                  );
                }
              },
            );
          },
        ),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.iconColor,
    this.badgeCount,
    this.isCompact = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;
  final int? badgeCount;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final showBadge = (badgeCount ?? 0) > 0;
    final badgeLabel = (badgeCount ?? 0) > 9 ? '9+' : '${badgeCount ?? ''}';
    final size = isCompact ? 36.0 : 44.0;
    final radius = isCompact ? 10.0 : 14.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: context.colorBg,
              border: Border.all(color: context.colorBorder),
              borderRadius: BorderRadius.circular(radius),
            ),
            child: Icon(
              icon,
              color: iconColor ?? context.colorPrimary,
              size: isCompact ? 20 : 24,
            ),
          ),
        ),
        if (showBadge)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: context.colorDanger,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badgeLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BarcodeQuickAction extends StatelessWidget {
  const _BarcodeQuickAction({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmit;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colorSurface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: context.colorBorder),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                hintText: 'สแกนบาร์โค้ดได้ที่นี่...',
                prefixIcon: Icon(
                  Icons.qr_code_scanner,
                  color: context.colorPrimary,
                ),
              ),
              onSubmitted: onSubmit,
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colorAccent,
                foregroundColor: context.colorText,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              onPressed: () => onSubmit(controller.text.trim()),
              icon: const Icon(Icons.local_fire_department),
              label: const Text(
                'SCAN',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
