import 'package:flutter/material.dart';
import 'package:frontend/services/api_service.dart';

double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

class BillProvider extends ChangeNotifier {
  BillProvider();

  String? _billId;
  Map<String, dynamic>? _currentBill;
  Map<String, dynamic>? get currentBill => _currentBill;
  List<Map<String, dynamic>> _items = [];

  // summary ที่ดึงมาจาก backend
  double _purchaseAmount = 0.0; // ยอดก่อนส่วนลด
  double _totalDiscount = 0.0; // ส่วนลดรวม
  double _vatAmount = 0.0; // VAT
  double _totalAmount = 0.0; // รวมสุทธิ

  bool isLoading = false;

  String? get billId => _billId;
  double get subtotal => _purchaseAmount;
  double get discount => _totalDiscount;
  double get tax => _vatAmount;
  double get total => _totalAmount;
  List<Map<String, dynamic>> get items => List.unmodifiable(_items);

  // taxRate เอาไว้ให้ UI เดิมใช้ต่อ
  double get taxRate {
    final base = _purchaseAmount - _totalDiscount;
    if (base <= 0) return 0.0;
    return _vatAmount / base;
  }

  // ใช้ตอน backend คืน bill object มา (from /bills/switch, /add-item..., /bills/:id, /payment)
  void _applyBill(Map<String, dynamic> bill) {
    _currentBill = bill;
    _billId = bill['id']?.toString() ?? bill['billId']?.toString();
    _purchaseAmount = _toDouble(
      bill['purchaseAmount'] ?? bill['purchase_amount'] ?? bill['subtotal'],
    );
    _totalDiscount = _toDouble(
      bill['totalDiscount'] ?? bill['discount'] ?? bill['total_discount'],
    );
    _vatAmount = _toDouble(
      bill['vatAmount'] ??
          bill['taxAmount'] ??
          bill['vat_amount'] ??
          bill['tax'],
    );
    _totalAmount = _toDouble(
      bill['totalAmount'] ?? bill['total'] ?? bill['grandTotal'],
    );
    _items = _extractItems(bill);
    _backfillTotalsIfNeeded();
    notifyListeners();
  }

  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> bill) {
    const possibleKeys = ['items', 'billItems', 'lineItems', 'details'];
    for (final key in possibleKeys) {
      final value = bill[key];
      if (value is List) {
        return value.whereType<Map<String, dynamic>>().toList();
      }
    }
    final firstListEntry = bill.entries.firstWhere(
      (entry) => entry.value is List,
      orElse: () => MapEntry('', null),
    );
    if (firstListEntry.value is List) {
      return (firstListEntry.value as List)
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    return [];
  }

  void _backfillTotalsIfNeeded() {
    final subtotalFromItems = _calculateSubtotalFromItems(_items);
    if (_purchaseAmount <= 0 && subtotalFromItems > 0) {
      _purchaseAmount = subtotalFromItems;
    }
    if (_totalAmount <= 0 && subtotalFromItems > 0) {
      final base = (_purchaseAmount - _totalDiscount).clamp(0, double.infinity);
      _totalAmount = base + _vatAmount;
    }
  }

  double _calculateSubtotalFromItems(List<Map<String, dynamic>> entries) {
    double sum = 0;
    for (final item in entries) {
      final amount = _toDouble(item['amount'] ?? item['total']);
      if (amount > 0) {
        sum += amount;
        continue;
      }
      final qty = _toDouble(item['qty'] ?? item['quantity'] ?? 1);
      final unitPrice = _toDouble(
        item['price'] ?? item['unitPrice'] ?? item['unit_price'] ?? item['cost'],
      );
      sum += unitPrice * (qty <= 0 ? 1 : qty);
    }
    return sum;
  }

  Future<void> switchBill({required String token, String? targetBillId}) async {
    isLoading = true;
    notifyListeners();
    try {
      final bill = await ApiService.switchBill(
        token: token,
        targetBillId: targetBillId,
      );
      _applyBill(bill);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _ensureBill({required String token}) async {
    if (_billId == null) {
      await switchBill(token: token, targetBillId: '');
    }
  }

  Future<void> addItemByBarcode({
    required String token,
    required String barcode,
    int qty = 1,
  }) async {
    await _ensureBill(token: token);
    if (_billId == null) {
      throw Exception('Bill id is not initialized');
    }

    isLoading = true;
    notifyListeners();
    try {
      final bill = await ApiService.addItemToBillByBarcode(
        token: token,
        billId: _billId!,
        barcode: barcode,
        qty: qty,
      );
      _applyBill(bill);
      if (_items.isEmpty) {
        await _reloadBill(token: token);
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addItem({
    required String token,
    required String partCode,
    required String addressCode,
    int qty = 1,
  }) async {
    await _ensureBill(token: token);
    if (_billId == null) {
      throw Exception('Bill id is not initialized');
    }

    isLoading = true;
    notifyListeners();
    try {
      final bill = await ApiService.addItemToBill(
        token: token,
        billId: _billId!,
        partCode: partCode,
        addressCode: addressCode,
        qty: qty,
      );
      _applyBill(bill);
      if (_items.isEmpty) {
        await _reloadBill(token: token);
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> clearBill({required String token}) async {
    await switchBill(token: token);
  }

  Future<void> removeItem({
    required String token,
    required String partCode,
    required String addressCode,
    int qty = 1,
    bool isRemoveAll = false,
  }) async {
    await _ensureBill(token: token);
    if (_billId == null) {
      throw Exception('Bill id is not initialized');
    }

    isLoading = true;
    notifyListeners();
    try {
      final bill = await ApiService.removeItemFromBill(
        token: token,
        billId: _billId!,
        partCode: partCode,
        addressCode: addressCode,
        qty: qty,
        isRemoveAll: isRemoveAll,
      );
      _applyBill(bill);
      if (_items.isEmpty && (_currentBill?['details'] != null)) {
        await _reloadBill(token: token);
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> payCurrentBill({required String token}) async {
    if (_billId == null) {
      throw Exception('Bill id is not initialized');
    }

    isLoading = true;
    notifyListeners();
    try {
      final bill = await ApiService.payBill(token: token, billId: _billId!);
      _applyBill(bill);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setManualDiscount({
    required String token,
    required String promotionCode,
  }) async {
    await _ensureBill(token: token);
    if (_billId == null) {
      throw Exception('Bill id is not initialized');
    }

    isLoading = true;
    notifyListeners();
    try {
      final bill = await ApiService.addBillDiscount(
        token: token,
        billId: _billId!,
        promotionCode: promotionCode,
      );
      _applyBill(bill);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _reloadBill({required String token}) async {
    if (_billId == null) return;
    try {
      final latest = await ApiService.getBill(token: token, billId: _billId!);
      _applyBill(latest);
    } catch (_) {
      // ignore sync errors
    }
  }
}
