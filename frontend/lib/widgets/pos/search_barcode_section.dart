import 'package:flutter/material.dart';
import 'package:frontend/models/product.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/bill_provider.dart';
import 'package:frontend/services/api_parts.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/pos_sale_stock.dart';
import 'package:frontend/utils/pos_error_message.dart';
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

  Future<void> searchByBarcode(String barcode) async {
    final auth = context.read<AuthProvider>();
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
      if (_lastAutoAddedBarcode != trimmed) {
        try {
          final billSnapshot = await _addScannedBarcode(
            token: token,
            barcode: trimmed,
          );
          final product = _mapProductFromBill(billSnapshot, trimmed);
          _products = product == null ? [] : [product];
          _lastAutoAddedBarcode = trimmed;
          return;
        } catch (e) {
          debugPrint('direct add by barcode failed: $e');
        }
      }

      // Resolve the fallback through the sale search too. GET /parts/:code is
      // branch-wide and can include the warehouse; sale search is pinned by
      // the backend to this session's configured POS store.
      final matches = await ApiPartsService.searchParts(
        token: token,
        query: trimmed,
        saleableOnly: true,
        includeOutOfStock: true,
        limit: 500,
        offset: 0,
      );
      final exact = matches.cast<Map<String, dynamic>?>().firstWhere((item) {
        if (item == null) return false;
        final code = item['code']?.toString().toUpperCase();
        final itemBarcode = (item['barCode'] ?? item['barcode'])
            ?.toString()
            .toUpperCase();
        return code == trimmed || itemBarcode == trimmed;
      }, orElse: () => null);
      if (exact == null) {
        throw Exception('part_not_found');
      }
      final product = mapPosSearchProduct(exact);
      _products = [product];
      if (product.availableQty <= 0 ||
          product.addressCodeForAdd == null ||
          product.addressCodeForAdd!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('สินค้านี้หมดจากคลังประจำ POS')),
          );
        }
        return;
      }
      if (_lastAutoAddedBarcode != trimmed) {
        final added = await _autoAddProduct(product, scannedBarcode: trimmed);
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

  Future<Map<String, dynamic>> _addScannedBarcode({
    required String token,
    required String barcode,
  }) {
    return context.read<BillProvider>().addItemByBarcode(
      token: token,
      barcode: barcode,
      qty: 1,
    );
  }

  Product? _mapProductFromBill(Map<String, dynamic> bill, String barcode) {
    final rawItems =
        (bill['items'] as List?) ?? (bill['details'] as List?) ?? [];
    if (rawItems.isEmpty) return null;

    Map<String, dynamic>? item;
    for (final raw in rawItems.reversed) {
      if (raw is Map<String, dynamic>) {
        item = raw;
        break;
      }
    }
    if (item == null) return null;

    final partCode =
        item['partCode']?.toString() ?? item['part_code']?.toString() ?? '';
    final addressCode =
        item['addressCode']?.toString() ??
        item['address_code']?.toString() ??
        '';
    final name =
        item['partName']?.toString() ??
        item['name']?.toString() ??
        item['receiptName']?.toString() ??
        partCode;

    return Product(
      id: partCode,
      name: name,
      price: _toDouble(item['price']),
      code: partCode,
      receiptName: item['receiptName']?.toString(),
      defaultAddressCode: addressCode,
      addressCodeForAdd: addressCode,
      barcode: barcode,
      availableQty:
          (item['remainingQty'] ?? item['remaining_qty'] ?? item['totalStock'])
              is num
          ? ((item['remainingQty'] ??
                        item['remaining_qty'] ??
                        item['totalStock'])
                    as num)
                .toInt()
          : 0,
    );
  }

  void _syncProductStock(Product product, Map<String, dynamic> bill) {
    final addressCode = product.addressCodeForAdd;
    if (!mounted || addressCode == null || addressCode.isEmpty) return;
    final remaining = remainingQtyFromBill(
      bill,
      partCode: product.code,
      addressCode: addressCode,
    );
    if (remaining == null) return;
    setState(() {
      _products = _products
          .map(
            (candidate) =>
                candidate.code == product.code &&
                    candidate.addressCodeForAdd == addressCode
                ? candidate.copyWith(availableQty: remaining)
                : candidate,
          )
          .toList();
    });
  }

  Future<bool> _autoAddProduct(
    Product product, {
    required String scannedBarcode,
  }) async {
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
      Object? barcodeError;
      final barcodeForAdd = scannedBarcode.trim().isNotEmpty
          ? scannedBarcode.trim()
          : product.barcode?.trim();
      if (barcodeForAdd != null && barcodeForAdd.isNotEmpty) {
        try {
          final updatedBill = await bill.addItemByBarcode(
            token: token,
            barcode: barcodeForAdd,
            qty: 1,
          );
          _syncProductStock(product, updatedBill);
          return true;
        } catch (e) {
          final catalogBarcode = product.barcode?.trim();
          if (catalogBarcode != null &&
              catalogBarcode.isNotEmpty &&
              catalogBarcode != barcodeForAdd) {
            final updatedBill = await bill.addItemByBarcode(
              token: token,
              barcode: catalogBarcode,
              qty: 1,
            );
            _syncProductStock(product, updatedBill);
            return true;
          }
          barcodeError = e;
        }
      }
      if (product.defaultAddressCode != null &&
          product.defaultAddressCode!.isNotEmpty) {
        final updatedBill = await bill.addItem(
          token: token,
          partCode: product.code,
          addressCode: product.defaultAddressCode!,
          qty: 1,
        );
        _syncProductStock(product, updatedBill);
        return true;
      } else {
        if (barcodeError != null) {
          throw barcodeError;
        }
        messenger.showSnackBar(
          const SnackBar(
            content: Text('ไม่พบ default store หรือ barcode สำหรับสินค้านี้'),
          ),
        );
        return false;
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('เพิ่มสินค้าไม่สำเร็จ: ${posErrorMessage(e)}')),
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
                                    separatorBuilder: (context, index) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      final product = pageItems[index];
                                      return _ProductCard(
                                        product: product,
                                        onAdd: () async {
                                          await _autoAddProduct(
                                            product,
                                            scannedBarcode:
                                                product.barcode ?? product.code,
                                          );
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
    final soldOut =
        product.availableQty <= 0 ||
        product.addressCodeForAdd == null ||
        product.addressCodeForAdd!.isEmpty;
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
                Row(
                  children: [
                    Text(
                      '฿${product.price.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: soldOut
                            ? context.colorMuted
                            : context.colorPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      soldOut ? 'หมด' : 'เหลือ ${product.availableQty}',
                      style: TextStyle(
                        color: soldOut
                            ? Colors.orange.shade800
                            : context.colorMuted,
                        fontSize: 12,
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
                foregroundColor: soldOut
                    ? context.colorMuted
                    : context.colorPrimary,
                side: BorderSide(
                  color: soldOut ? context.colorBorder : context.colorPrimary,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radius),
                ),
              ),
              onPressed: soldOut
                  ? null
                  : () {
                      onAdd();
                    },
              child: Text(soldOut ? 'หมด' : '+ เพิ่ม'),
            ),
          ),
        ],
      ),
    );
  }
}
