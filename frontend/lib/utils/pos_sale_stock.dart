import 'package:frontend/models/product.dart';

/// Maps the stock contract returned by a sale search. The top-level fields are
/// authoritative because the backend chose the exact address checkout will
/// debit. Address parsing remains as a compatibility fallback for an older
/// server during a rolling deployment.
Product mapPosSearchProduct(Map<String, dynamic> json) {
  final rawAddresses = (json['addresses'] as List?) ?? [];
  Map<String, dynamic>? defaultAddress;
  for (final addr in rawAddresses) {
    if (addr is! Map<String, dynamic> || _toDouble(addr['qty']) <= 0) {
      continue;
    }
    if (defaultAddress == null ||
        _toDouble(addr['qty']) > _toDouble(defaultAddress['qty'])) {
      defaultAddress = addr;
    }
  }

  final authoritativeAddress = json['addressCode']?.toString().trim() ?? '';
  final hasAuthoritativeStock =
      json.containsKey('addressCode') || json.containsKey('availableQty');
  final fallbackAddress =
      defaultAddress?['addressCode']?.toString() ??
      defaultAddress?['code']?.toString();
  final String? addressCode = hasAuthoritativeStock
      ? (authoritativeAddress.isEmpty ? null : authoritativeAddress)
      : fallbackAddress;
  final availableQty = json.containsKey('availableQty')
      ? _toQty(json['availableQty'])
      : _toQty(defaultAddress?['qty']);

  return Product(
    id: json['id']?.toString() ?? json['code']?.toString() ?? '',
    name: json['nameTh'] ?? json['name_th'] ?? json['name'] ?? '',
    price: _toDouble(json['price'] ?? json['unitPrice']),
    cost: _toDouble(json['cost']),
    minPrice: _toDouble(json['minPrice'] ?? json['min_price']),
    code: json['code']?.toString() ?? '',
    receiptName: json['receiptName']?.toString(),
    defaultAddressCode: addressCode,
    barcode: json['barCode']?.toString() ?? json['barcode']?.toString(),
    addressCodeForAdd: addressCode,
    availableQty: availableQty,
  );
}

/// Reads the remaining quantity returned after a successful add. This makes
/// an open search result follow the database instead of keeping its stale
/// pre-sale number on screen.
int? remainingQtyFromBill(
  Map<String, dynamic> bill, {
  required String partCode,
  required String addressCode,
}) {
  final rawItems = (bill['items'] as List?) ?? (bill['details'] as List?) ?? [];
  for (final raw in rawItems) {
    if (raw is! Map<String, dynamic>) continue;
    final itemPart =
        raw['partCode']?.toString() ?? raw['part_code']?.toString() ?? '';
    final itemAddress =
        raw['addressCode']?.toString() ?? raw['address_code']?.toString() ?? '';
    if (itemPart != partCode || itemAddress != addressCode) continue;
    final value =
        raw['remainingQty'] ?? raw['remaining_qty'] ?? raw['totalStock'];
    if (value == null) return null;
    return _toQty(value);
  }
  return null;
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int _toQty(dynamic value) => _toDouble(value).floor();
