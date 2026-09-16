import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frontend/models/product.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/bill_provider.dart';
import 'package:frontend/services/api_parts.dart';
import 'package:frontend/services/app_dialog_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class SearchPartsDialog extends StatefulWidget {
  const SearchPartsDialog({super.key, this.initialQuery = ''});

  /// Lets every POS search entry point use the same server-side search flow.
  /// In particular, text typed in the quick input must not be treated as a
  /// product code/barcode when it is actually a Thai product name.
  final String initialQuery;

  @override
  State<SearchPartsDialog> createState() => _SearchPartsDialogState();
}

class _SearchPartsDialogState extends State<SearchPartsDialog> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  List<Product> _products = [];
  int _currentPage = 0;
  final PageController _pageController = PageController();
  Timer? _searchDebounce;
  int _searchRequestId = 0;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_searchController.text.isEmpty) {
        _loadParts();
      } else {
        _performSearch();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadParts({bool showError = false}) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    if (token == null) {
      if (showError) {
        await AppDialogService.showError(
          context,
          error: Exception('missing_token'),
          fallback: 'กรุณาเข้าสู่ระบบอีกครั้ง',
        );
      }
      return;
    }

    final requestId = ++_searchRequestId;
    setState(() => _isLoading = true);
    try {
      final raw = await ApiPartsService.searchParts(
        token: token,
        query: '',
        limit: 45,
        offset: 0,
      );
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _products = raw.map(_mapProduct).toList();
        _currentPage = 0;
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    } catch (e) {
      if (showError && mounted && requestId == _searchRequestId) {
        await AppDialogService.showError(
          context,
          error: e,
          fallback: 'โหลดสินค้าไม่สำเร็จ',
        );
      }
    } finally {
      if (mounted && requestId == _searchRequestId) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      await _loadParts();
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    if (token == null) {
      await AppDialogService.showError(
        context,
        error: Exception('missing_token'),
        fallback: 'กรุณาเข้าสู่ระบบอีกครั้ง',
      );
      return;
    }

    final requestId = ++_searchRequestId;
    setState(() {
      _isLoading = true;
    });
    try {
      final raw = await ApiPartsService.searchParts(
        token: token,
        query: query,
        limit: 20,
        offset: 0,
      );
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _products = raw.map(_mapProduct).toList();
        _currentPage = 0;
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    } catch (e) {
      if (mounted && requestId == _searchRequestId) {
        await AppDialogService.showError(
          context,
          error: e,
          fallback: 'ค้นหาสินค้าไม่สำเร็จ',
        );
      }
    } finally {
      if (mounted && requestId == _searchRequestId) {
        setState(() => _isLoading = false);
      }
    }
  }

  Product _mapProduct(Map<String, dynamic> json) {
    final posId = context.read<AuthProvider>().posId?.trim() ?? '';
    return mapPosProductForSale(json, posId: posId);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _performSearch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = _chunkProducts();
    final hasPages = pages.isNotEmpty;

    final safePageIndex = hasPages
        ? _currentPage.clamp(0, pages.length - 1).toInt()
        : 0;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 960,
        height: 640,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'ค้นหาสินค้าโดยรหัส ชื่อ หรือบาร์โค้ด',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onSubmitted: (_) => _performSearch(),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _performSearch,
                    child: const Text('ค้นหา'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _products.isEmpty
                  ? const _DialogEmptyState()
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              const Text(
                                'รายการสินค้า',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${_products.length} รายการ',
                                style: const TextStyle(color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: PageView.builder(
                            controller: _pageController,
                            physics: const BouncingScrollPhysics(),
                            onPageChanged: (index) {
                              setState(() => _currentPage = index);
                            },
                            itemCount: pages.length,
                            itemBuilder: (context, pageIndex) {
                              final pageItems = pages[pageIndex];
                              return GridView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 8,
                                ),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      mainAxisSpacing: 16,
                                      crossAxisSpacing: 16,
                                      childAspectRatio: 2.7,
                                    ),
                                itemCount: pageItems.length,
                                itemBuilder: (context, index) {
                                  final product = pageItems[index];
                                  return PosProductCard(
                                    product: product,
                                    onAdd: () => _handleAddProduct(product),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (hasPages)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              pages.length,
                              (index) => GestureDetector(
                                onTap: () {
                                  if (_pageController.hasClients) {
                                    _pageController.animateToPage(
                                      index,
                                      duration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      curve: Curves.easeOut,
                                    );
                                  }
                                },
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: index == safePageIndex
                                        ? AppColors.primary
                                        : AppColors.border,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAddProduct(Product product) async {
    final messenger = ScaffoldMessenger.of(context);
    if (product.availableQty <= 0 ||
        product.addressCodeForAdd == null ||
        product.addressCodeForAdd!.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('สินค้านี้ไม่มีสต็อกในรถของจุดขายนี้')),
      );
      return;
    }
    final auth = context.read<AuthProvider>();
    final bill = context.read<BillProvider>();
    final token = auth.token;
    if (token == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
      );
      return;
    }

    try {
      await bill.addItem(
        token: token,
        partCode: product.code,
        addressCode: product.addressCodeForAdd!,
        qty: 1,
      );
    } catch (e) {
      await AppDialogService.showError(
        context,
        error: e,
        fallback: 'เพิ่มสินค้าเข้าบิลไม่สำเร็จ',
      );
    }
  }

  List<List<Product>> _chunkProducts() {
    final chunks = <List<Product>>[];
    for (var i = 0; i < _products.length; i += 9) {
      final end = i + 9 > _products.length ? _products.length : i + 9;
      chunks.add(_products.sublist(i, end));
    }
    return chunks;
  }
}

Product mapPosProductForSale(
  Map<String, dynamic> json, {
  required String posId,
}) {
  final rawAddresses = (json['addresses'] as List?) ?? [];
  Map<String, dynamic>? vehicleAddress;
  var availableQty = 0;

  // A sale can only reduce stock from the current POS vehicle. Never fall
  // back to the warehouse/default address: the backend correctly rejects it,
  // but the old UI still presented an enabled Add button to the cashier.
  final normalizedPosId = posId.trim();
  final vehicleStoreId = normalizedPosId.isEmpty
      ? null
      : 'vehicle_$normalizedPosId';
  if (vehicleStoreId != null) {
    for (final address in rawAddresses) {
      if (address is! Map<String, dynamic>) continue;
      final store = address['store'];
      final storeId = store is Map
          ? store['id']?.toString()
          : (address['storeId'] ?? address['store_id'])?.toString();
      if (storeId != vehicleStoreId) continue;
      final qty = _productQty(address['qty']);
      if (qty <= 0) continue;
      availableQty += qty;
      vehicleAddress ??= address;
    }
  }

  final addressCode =
      vehicleAddress?['addressCode']?.toString() ??
      vehicleAddress?['address_code']?.toString() ??
      vehicleAddress?['code']?.toString();

  return Product(
    id: json['id']?.toString() ?? json['code']?.toString() ?? '',
    name: json['nameTh'] ?? json['name_th'] ?? json['name'] ?? '',
    price: _productDouble(json['price'] ?? json['unitPrice']),
    code: json['code']?.toString() ?? '',
    receiptName: json['receiptName']?.toString(),
    defaultAddressCode: addressCode,
    barcode: json['barCode']?.toString() ?? json['barcode']?.toString(),
    addressCodeForAdd: addressCode,
    availableQty: availableQty,
  );
}

double _productDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int _productQty(dynamic value) => _productDouble(value).floor();

class PosProductCard extends StatelessWidget {
  const PosProductCard({super.key, required this.product, required this.onAdd});

  final Product product;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final soldOut =
        product.availableQty <= 0 || product.addressCodeForAdd == null;
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
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.build, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'รหัส ${product.code}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '฿${product.price.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: soldOut ? AppColors.muted : AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      soldOut ? 'หมดจากรถ' : 'เหลือ ${product.availableQty}',
                      style: TextStyle(
                        color: soldOut
                            ? Colors.orange.shade800
                            : AppColors.muted,
                        fontSize: 12,
                        fontWeight: soldOut
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 40,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: soldOut ? AppColors.muted : AppColors.primary,
                side: BorderSide(
                  color: soldOut ? AppColors.border : AppColors.primary,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              onPressed: soldOut ? null : onAdd,
              child: Text(soldOut ? 'หมด' : '+ เพิ่ม'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogEmptyState extends StatelessWidget {
  const _DialogEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.inventory_2_outlined, size: 56, color: AppColors.muted),
          SizedBox(height: 12),
          Text('เลือกสินค้า', style: TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}
