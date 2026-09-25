import 'package:flutter/material.dart';
import 'package:frontend/models/product.dart';
import 'package:frontend/theme/app_theme.dart';

/// Maps a branch-scoped `/parts/search` result to the stock row that the POS
/// can actually sell from.
///
/// New backends provide [addressCode] and [availableQty] explicitly. The
/// address-list fallback keeps older/local backends safe by selecting a row
/// with positive stock instead of blindly choosing the default (which may be
/// empty while another branch address has stock).
Product mapPosProductForSale(Map<String, dynamic> json) {
  final serverAddressCode = _nonEmptyString(json['addressCode']);
  final serverAvailableQty = _productQty(json['availableQty']);

  Map<String, dynamic>? selectedAddress;
  final rawAddresses = (json['addresses'] as List?) ?? const [];

  if (serverAddressCode != null && serverAvailableQty > 0) {
    for (final address in rawAddresses) {
      if (address is! Map<String, dynamic>) continue;
      if (_addressCode(address) == serverAddressCode) {
        selectedAddress = address;
        break;
      }
    }
  }

  selectedAddress ??= _firstPositiveAddress(rawAddresses);

  final addressCode = serverAddressCode != null && serverAvailableQty > 0
      ? serverAddressCode
      : selectedAddress == null
      ? null
      : _addressCode(selectedAddress);
  final availableQty = serverAddressCode != null && serverAvailableQty > 0
      ? serverAvailableQty
      : selectedAddress == null
      ? 0
      : _productQty(selectedAddress['qty']);

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

Map<String, dynamic>? _firstPositiveAddress(List<dynamic> addresses) {
  for (final address in addresses) {
    if (address is Map<String, dynamic> && _productQty(address['qty']) > 0) {
      return address;
    }
  }
  return null;
}

String? _addressCode(Map<String, dynamic> address) => _nonEmptyString(
  address['addressCode'] ?? address['address_code'] ?? address['code'],
);

String? _nonEmptyString(dynamic value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
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
        product.availableQty <= 0 ||
        product.addressCodeForAdd == null ||
        product.addressCodeForAdd!.isEmpty;
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
                      soldOut ? 'หมดจากคลัง' : 'เหลือ ${product.availableQty}',
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
