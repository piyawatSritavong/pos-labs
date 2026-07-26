import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frontend/models/product.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/bill_provider.dart';
import 'package:frontend/services/api_parts.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/pos_error_message.dart';
import 'package:provider/provider.dart';

class SearchPartsDialog extends StatefulWidget {
  const SearchPartsDialog({super.key});

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadParts();
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final raw = await ApiPartsService.searchParts(
        token: token,
        query: '',
        saleableOnly: true,
        limit: 45,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _products = raw.map(_mapProduct).toList();
        _currentPage = 0;
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    } catch (e) {
      if (showError && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดสินค้าไม่สำเร็จ: $e')));
      }
    } finally {
      if (mounted) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });
    try {
      final raw = await ApiPartsService.searchParts(
        token: token,
        query: query,
        saleableOnly: true,
        limit: 20,
        offset: 0,
      );
      setState(() {
        _products = raw.map(_mapProduct).toList();
        _currentPage = 0;
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ค้นหาไม่สำเร็จ: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Product _mapProduct(Map<String, dynamic> json) {
    final rawAddresses = (json['addresses'] as List?) ?? [];
    Map<String, dynamic>? defaultAddress;
    for (final addr in rawAddresses) {
      if (addr is Map<String, dynamic> &&
          _toDouble(addr['qty']) > 0 &&
          (addr['isDefault'] == true || addr['is_default'] == true)) {
        defaultAddress = addr;
        break;
      }
    }
    if (defaultAddress == null) {
      for (final addr in rawAddresses) {
        if (addr is Map<String, dynamic> && _toDouble(addr['qty']) > 0) {
          defaultAddress = addr;
          break;
        }
      }
    }

    final defaultAddressCode =
        defaultAddress?['addressCode']?.toString() ??
        defaultAddress?['code']?.toString();

    return Product(
      id: json['id']?.toString() ?? json['code']?.toString() ?? '',
      name: json['nameTh'] ?? json['name_th'] ?? json['name'] ?? '',
      price: _toDouble(json['price'] ?? json['unitPrice']),
      cost: _toDouble(json['cost']),
      minPrice: _toDouble(json['minPrice'] ?? json['min_price']),
      code: json['code']?.toString() ?? '',
      receiptName: json['receiptName']?.toString(),
      defaultAddressCode: defaultAddressCode,
      barcode: json['barCode']?.toString() ?? json['barcode']?.toString(),
      addressCodeForAdd: json['addressCode']?.toString() ?? defaultAddressCode,
    );
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
                                  return _DialogProductCard(
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
      if (product.addressCodeForAdd != null &&
          product.addressCodeForAdd!.isNotEmpty) {
        await bill.addItem(
          token: token,
          partCode: product.code,
          addressCode: product.addressCodeForAdd!,
          qty: 1,
        );
      } else if (product.barcode != null && product.barcode!.isNotEmpty) {
        await bill.addItemByBarcode(token: token, barcode: product.barcode!);
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('สินค้านี้ไม่มี address หรือ barcode สำหรับเพิ่มบิล'),
          ),
        );
        return;
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('เพิ่มสินค้าไม่สำเร็จ: ${posErrorMessage(e)}')),
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

class _DialogProductCard extends StatelessWidget {
  const _DialogProductCard({required this.product, required this.onAdd});

  final Product product;
  final VoidCallback onAdd;

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
                Text(
                  '฿${product.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 40,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              onPressed: onAdd,
              child: const Text('+ เพิ่ม'),
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
