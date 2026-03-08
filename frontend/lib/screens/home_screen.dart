import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frontend/services/api_bills.dart';
import 'package:provider/provider.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/screens/office_screen.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/widgets/pos/stock_dialog.dart';
import 'package:frontend/widgets/pos/bill_log_dialog.dart';
import 'package:frontend/widgets/pos/hold_bill_dialog.dart';
import 'package:frontend/widgets/pos/search_parts_dialog.dart';
import 'package:frontend/widgets/pos/cart_summary_section.dart';
import 'package:frontend/widgets/pos/search_barcode_section.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final GlobalKey<SearchBarcodeSectionState> _productListKey =
      GlobalKey<SearchBarcodeSectionState>();
  final FocusNode _barcodeFocusNode = FocusNode();
  Timer? _refocusTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusScanner());
  }

  @override
  void dispose() {
    _refocusTimer?.cancel();
    _barcodeFocusNode.dispose();
    _searchController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcodeSearch(
    String code, {
    bool clearOnSuccess = false,
  }) async {
    _scheduleRefocus();
    final upper = code.toUpperCase();
    _barcodeController.value = _barcodeController.value.copyWith(
      text: upper,
      selection: TextSelection.collapsed(offset: upper.length),
    );
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

  void _scheduleRefocus() {
    _refocusTimer?.cancel();
    _refocusTimer = Timer(const Duration(seconds: 30), () {
      _focusScanner();
    });
  }

  void _focusScanner() {
    if (!mounted) return;
    FocusScope.of(context).requestFocus(_barcodeFocusNode);
    _scheduleRefocus();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
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
                      flex: 7,
                      child: SearchBarcodeSection(
                        key: _productListKey,
                      ),
                    ),
                    const SizedBox(width: 20),
                    const Expanded(flex: 3, child: CartSummarySection()),
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
        ),
      ),
    );
  }
}

class HeaderBar extends StatelessWidget {
  const HeaderBar({
    required this.authName,
    required this.searchController,
    required this.onSearchTap,
  });

  final String authName;
  final TextEditingController searchController;
  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.shopping_bag, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                authName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              Text(
                'สาขา 1',
                style: TextStyle(
                  color: AppColors.muted.withValues(alpha: 0.9),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: searchController,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                final displayText =
                    hasText ? value.text.trim() : 'พิมค้นหาสินค้า';
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onSearchTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, color: AppColors.muted),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              displayText,
                              style: TextStyle(
                                color: hasText
                                    ? AppColors.text
                                    : AppColors.muted,
                              ),
                            ),
                          ),
                          if (hasText)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                searchController.clear();
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close,
                                  color: AppColors.muted,
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
            ),
          ),
          const SizedBox(width: 24),
          _HeaderActionGroup(),
        ],
      ),
    );
  }
}

class _HeaderActionGroup extends StatefulWidget {
  const _HeaderActionGroup();

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
      final bills =
          await ApiBillsService.getBills(token: token, limit: 100, offset: 0);
      final hold = bills
          .where(
            (b) => (b['status']?.toString().toLowerCase() ?? '') == 'hold',
          )
          .length;
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
    return Row(
      children: [
        const SizedBox(width: 12),
        _HeaderIconButton(
          icon: Icons.pause_circle_outline,
          badgeCount: _holdCount,
          onTap: () async {
            await showDialog(
              context: context,
              builder: (context) => const HoldBillDialog(),
            );
            if (mounted) {
              _loadHoldCount();
            }
          },
        ),
        const SizedBox(width: 12),
        _HeaderIconButton(
          icon: Icons.warning_amber_rounded,
          iconColor: AppColors.accent,
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => const StockDialog(),
            );
          },
        ),
        const SizedBox(width: 12),
        _HeaderIconButton(
          icon: Icons.history_rounded,
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => const BillsLogDialog(),
            );
          },
        ),
        const SizedBox(width: 16),
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
              const PopupMenuItem(value: 'office', child: Text('OFFICE')),
            const PopupMenuItem(value: 'logout', child: Text('ออกจากระบบ')),
          ],
          onSelected: (value) async {
            if (value == 'logout') {
              await context.read<AuthProvider>().logout();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            } else if (value == 'office') {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OfficeScreen()),
              );
            }
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
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final showBadge = (badgeCount ?? 0) > 0;
    final badgeLabel = (badgeCount ?? 0) > 9 ? '9+' : '${badgeCount ?? ''}';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.bg,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor ?? AppColors.primary),
          ),
        ),
        if (showBadge)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.danger,
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(
                hintText: 'สแกนบาร์โค้ดได้ที่นี่...',
                prefixIcon: Icon(
                  Icons.qr_code_scanner,
                  color: AppColors.primary,
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
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.text,
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
