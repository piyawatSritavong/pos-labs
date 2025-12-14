import 'package:frontend/models/product.dart';
import 'package:flutter/material.dart';

class CartItem {
  final Product product;
  int qty;

  CartItem({
    required this.product,
    this.qty = 1,
  });

  double get lineTotal => product.price * qty;
}

class CartProvider extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  double taxRate = 0.07;
  double discount = 0.0;

  Map<String, CartItem> get items => _items;

  List<CartItem> get itemsList => _items.values.toList();

  double get subtotal =>
      _items.values.fold(0.0, (sum, item) => sum + item.lineTotal);

  double get tax => subtotal * taxRate;

  double get total => subtotal - discount + tax;

  void setDiscount(double amount) {
    discount = amount;
    notifyListeners();
  }

  void addProduct(Product product) {
    if (_items.containsKey(product.id)) {
      _items[product.id]!.qty += 1;
    } else {
      _items[product.id] = CartItem(product: product, qty: 1);
    }
    notifyListeners();
  }

  void removeOne(String productId) {
    if (!_items.containsKey(productId)) return;

    final item = _items[productId]!;
    if (item.qty > 1) {
      item.qty -= 1;
    } else {
      _items.remove(productId);
    }
    notifyListeners();
  }

  void clear() {
    _items.clear();
    discount = 0.0;
    notifyListeners();
  }
}