class Product {
  final String id;
  final String name;
  final double price;
  final double cost;
  final double minPrice;
  final String code;
  final String? receiptName;
  final String? defaultAddressCode;
  final String? addressCodeForAdd;
  final String? barcode;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    this.cost = 0,
    this.minPrice = 0,
    required this.code,
    this.receiptName,
    this.defaultAddressCode,
    this.addressCodeForAdd,
    this.barcode,
  });
}
