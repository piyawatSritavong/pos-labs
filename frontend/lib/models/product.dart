class Product {
  final String id;
  final String name;
  final double price;
  final String code;
  final String? defaultAddressCode;
  final String? addressCodeForAdd;
  final String? barcode;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.code,
    this.defaultAddressCode,
    this.addressCodeForAdd,
    this.barcode,
  });
}
