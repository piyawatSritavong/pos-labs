import 'package:flutter/material.dart';
import 'package:frontend/models/product.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/bill_provider.dart';
import 'package:frontend/services/api_parts.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class SearchBarcodeSection extends StatefulWidget {
  const SearchBarcodeSection({super.key, this.itemsPerPage = 9});

  final int itemsPerPage;

  @override
  State<SearchBarcodeSection> createState() => SearchBarcodeSectionState();
}

class SearchBarcodeSectionState extends State<SearchBarcodeSection> {
  bool _isLoading = false;
  bool _isAutoAdding = false;
  String? _lastAutoAddedBarcode;
  List<Product> _products = [];
  final PageController _pageController = PageController();
  int _currentPage = 0;

  List<List<Product>> _chunkedProducts() {
    final pageSize = widget.itemsPerPage;
    final chunks = <List<Product>>[];
    for (var i = 0; i < _products.length; i += pageSize) {
      final end = i + pageSize > _products.length
          ? _products.length
          : i + pageSize;
      chunks.add(_products.sublist(i, end));
    }
    return chunks;
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Product _mapProduct(Map<String, dynamic> json) {
    final rawAddresses = (json['addresses'] as List?) ?? [];

    final barcode = json['barCode']?.toString() ?? json['barcode']?.toString();

    Map<String, dynamic>? defaultAddress;

    for (final addr in rawAddresses) {
      if (addr is Map<String, dynamic> &&
          (addr['isDefault'] == true || addr['is_default'] == true)) {
        defaultAddress = addr;
        break;
      }
    }

    if (defaultAddress == null) {
      for (final addr in rawAddresses) {
        if (addr is! Map<String, dynamic>) continue;
        final qty = _toDouble(addr['qty']);
        if (qty > 0) {
          defaultAddress = addr;
          break;
        }
      }
    }

    if (defaultAddress == null && rawAddresses.isNotEmpty) {
      final first = rawAddresses.first;
      if (first is Map<String, dynamic>) {
        defaultAddress = first;
      }
    }

    final defaultAddressCode =
        defaultAddress?['addressCode']?.toString() ??
        defaultAddress?['code']?.toString();

    return Product(
      id: json['id']?.toString() ?? json['code']?.toString() ?? '',
      name: json['nameTh'] ?? json['name_th'] ?? json['name'] ?? '',
      price: _toDouble(json['price'] ?? json['unitPrice']),
      code: json['code']?.toString() ?? '',
      defaultAddressCode: defaultAddressCode,
      barcode: barcode,
    );
  }

  Future<void> searchByBarcode(String barcode) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    if (token == null) return;
    final trimmed = barcode.trim().toUpperCase();
    if (trimmed.isEmpty) {
      setState(() {
        _products = [];
        _currentPage = 0;
      });
      _lastAutoAddedBarcode = null;
      return;
    }

    setState(() => _isLoading = true);
    try {
      final raw = await ApiPartsService.getPartByCode(
        token: token,
        code: trimmed,
      );
      final product = _mapProduct(raw);
      _products = [product];
      if (_lastAutoAddedBarcode != trimmed) {
        final added = await _autoAddProduct(product);
        if (added) {
          _lastAutoAddedBarcode = trimmed;
        }
      }
    } catch (e) {
      debugPrint('getPartByCode error: $e');
      _products = [];
      _lastAutoAddedBarcode = null;
    } finally {
      _completeLoadingAndReset();
    }
  }

  Future<bool> _autoAddProduct(Product product) async {
    if (_isAutoAdding) return false;
    _isAutoAdding = true;
    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<AuthProvider>();
    final bill = context.read<BillProvider>();
    final token = auth.token;
    if (token == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
      );
      _isAutoAdding = false;
      return false;
    }

    try {
      if (product.defaultAddressCode != null &&
          product.defaultAddressCode!.isNotEmpty) {
        await bill.addItem(
          token: token,
          partCode: product.code,
          addressCode: product.defaultAddressCode!,
          qty: 1,
        );
        return true;
      } else if (product.barcode != null && product.barcode!.isNotEmpty) {
        await bill.addItemByBarcode(
          token: token,
          barcode: product.barcode!,
          qty: 1,
        );
        return true;
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('ไม่พบ default store หรือ barcode สำหรับสินค้านี้'),
          ),
        );
        return false;
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('เพิ่มสินค้าไม่สำเร็จ: $e')),
      );
      return false;
    } finally {
      _isAutoAdding = false;
    }
  }

  void _completeLoadingAndReset() {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _currentPage = 0;
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _chunkedProducts();
    final currentPageIndex = pages.isEmpty
        ? 0
        : _currentPage.clamp(0, pages.length - 1).toInt();
    final currentPageCount = pages.isEmpty ? 0 : pages[currentPageIndex].length;

    return Container(
      decoration: BoxDecoration(
        color: context.colorSurface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: context.colorBorder),
        boxShadow: AppShadows.soft,
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'รายการสินค้า',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '$currentPageCount รายการ',
                style: TextStyle(color: context.colorMuted),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Expanded(
                        child: pages.isEmpty
                            ? const _EmptyProductsState()
                            : PageView.builder(
                                controller: _pageController,
                                onPageChanged: (index) {
                                  setState(() => _currentPage = index);
                                },
                                itemCount: pages.length,
                                itemBuilder: (context, pageIndex) {
                                  final pageItems = pages[pageIndex];
                                  return ListView.separated(
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    shrinkWrap: true,
                                    padding: EdgeInsets.zero,
                                    itemCount: pageItems.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      final product = pageItems[index];
                                      return _ProductCard(
                                        product: product,
                                        onAdd: () async {
                                          await _autoAddProduct(product);
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 16),
                      if (pages.isNotEmpty)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            pages.length,
                            (index) => GestureDetector(
                              onTap: () {
                                if (_pageController.hasClients) {
                                  _pageController.animateToPage(
                                    index,
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeOut,
                                  );
                                }
                              },
                              child: Container(
                                width: 12,
                                height: 12,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                ),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: index == _currentPage
                                      ? context.colorPrimary
                                      : context.colorBorder,
                                ),
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

class _EmptyProductsState extends StatelessWidget {
  const _EmptyProductsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 48, color: context.colorMuted),
          const SizedBox(height: 8),
          Text(
            'ยิงบาร์โค้ด/พิมค้นหา',
            style: TextStyle(color: context.colorMuted),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onAdd});

  final Product product;
  final Future<void> Function() onAdd;

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
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: context.colorPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.build, color: context.colorPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'รหัส ${product.code}',
                  style: TextStyle(color: context.colorMuted, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '฿${product.price.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: context.colorPrimary,
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
                foregroundColor: context.colorPrimary,
                side: BorderSide(color: context.colorPrimary),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              onPressed: () {
                onAdd();
              },
              child: const Text('+ เพิ่ม'),
            ),
          ),
        ],
      ),
    );
  }
}
