import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:frontend/services/api_service.dart';

double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

class BillProvider extends ChangeNotifier {
  BillProvider() {
    _initWebSync();
  }

  String? _billId;
  Map<String, dynamic>? _currentBill;
  Map<String, dynamic>? get currentBill => _currentBill;
  List<Map<String, dynamic>> _items = [];

  // summary ที่ดึงมาจาก backend
  double _purchaseAmount = 0.0; // ยอดก่อนส่วนลด
  double _totalDiscount = 0.0; // ส่วนลดรวม
  double _vatAmount = 0.0; // VAT
  double _totalAmount = 0.0; // รวมสุทธิ

  bool _awaitingCashPayment = false;
  double _awaitingCashAmount = 0.0;
  bool _awaitingQrPayment = false;

  bool get isAwaitingCashPayment => _awaitingCashPayment;
  double get awaitingCashAmount => _awaitingCashAmount;
  bool get isAwaitingQrPayment => _awaitingQrPayment;

  bool _showThankYouOverlay = false;
  bool get showThankYouOverlay => _showThankYouOverlay;

  bool isLoading = false;
  Map<String, dynamic>? _returnReferenceBill;
  final List<Map<String, dynamic>> _returnLines = [];

  String? get billId => _billId;
  double get subtotal => _purchaseAmount;
  double get discount => _totalDiscount;
  double get tax => _vatAmount;
  double get total => _totalAmount;
  List<Map<String, dynamic>> get items => List.unmodifiable(_items);
  Map<String, dynamic>? get returnReferenceBill => _returnReferenceBill == null
      ? null
      : Map<String, dynamic>.from(_returnReferenceBill!);
  List<Map<String, dynamic>> get returnLines => List.unmodifiable(_returnLines);
  bool get hasReturnItems => _returnLines.isNotEmpty;
  String? get returnReferenceBillId => _returnReferenceBill == null
      ? null
      : _returnReferenceBill!['id']?.toString();
  int get returnLineCount => _returnLines.fold<int>(
    0,
    (sum, line) =>
        sum +
        (_toDouble(line['qty']) <= 0 ? 1 : _toDouble(line['qty']).toInt()),
  );
  double get returnCreditAmount {
    double sum = 0;
    for (final line in _returnLines) {
      final amount = _toDouble(line['lineTotal'] ?? line['amount']);
      sum += amount.abs();
    }
    return sum;
  }

  double get netSettlementAmount => _totalAmount - returnCreditAmount;

  // taxRate เอาไว้ให้ UI เดิมใช้ต่อ
  double get taxRate {
    final base = _purchaseAmount - _totalDiscount;
    if (base <= 0) return 0.0;
    return _vatAmount / base;
  }

  // ใช้ตอน backend คืน bill object มา (from /bills/switch, /add-item..., /bills/:id, /payment)
  void _applyBill(Map<String, dynamic> bill, {bool sync = true}) {
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

    // Restore cash-payment waiting state if present in payload
    _awaitingCashPayment = bill['awaitingCashPayment'] == true;
    final awaitingAmountRaw = bill['awaitingCashAmount'];
    if (awaitingAmountRaw is num) {
      _awaitingCashAmount = awaitingAmountRaw.toDouble();
    } else if (awaitingAmountRaw is String) {
      _awaitingCashAmount = double.tryParse(awaitingAmountRaw) ?? 0.0;
    } else {
      _awaitingCashAmount = 0.0;
    }
    _awaitingQrPayment = bill['awaitingQrPayment'] == true;

    _showThankYouOverlay = bill['showThankYouOverlay'] == true;

    if (sync) {
      _syncToLocalStorage();
    }

    notifyListeners();
  }

  void _syncToLocalStorage() {
    if (!kIsWeb || _currentBill == null) return;
    try {
      final json = jsonEncode(_currentBill);
      html.window.localStorage['bill_state'] = json;
    } catch (_) {
      // ignore serialization errors
    }
  }

  void _initWebSync() {
    if (!kIsWeb) return;

    // 1) โหลดค่าล่าสุดจาก localStorage ตอนเปิดแท็บ
    final raw = html.window.localStorage['bill_state'];
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _applyBill(map, sync: false);
      } catch (_) {
        // ignore parse errors
      }
    }

    // 2) ฟัง storage event จากแท็บอื่น แล้วอัปเดต state
    html.window.onStorage.listen((event) {
      if (event.key != 'bill_state') return;
      final newValue = event.newValue;
      if (newValue == null || newValue.isEmpty) return;
      try {
        final map = jsonDecode(newValue) as Map<String, dynamic>;
        _applyBill(map, sync: false);
      } catch (_) {
        // ignore parse errors
      }
    });
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

  /// Set a local-only discount amount, clamp and sync to storage and listeners.
  void applyLocalDiscount({required double discountAmount}) {
    // Clamp discount between 0 and subtotal
    final numClamped = discountAmount.clamp(0.0, _purchaseAmount);
    _totalDiscount = numClamped.toDouble();

    // Recalculate total based on current subtotal, discount, and VAT
    final base = (_purchaseAmount - _totalDiscount).clamp(0.0, double.infinity);
    _totalAmount = base + _vatAmount;

    // Keep currentBill in sync so it can be broadcast to other tabs
    if (_currentBill != null) {
      _currentBill = Map<String, dynamic>.from(_currentBill!);
    } else {
      _currentBill = <String, dynamic>{};
    }
    _currentBill!['purchaseAmount'] = _purchaseAmount;
    _currentBill!['totalDiscount'] = _totalDiscount;
    _currentBill!['vatAmount'] = _vatAmount;
    _currentBill!['totalAmount'] = _totalAmount;

    _syncToLocalStorage();
    notifyListeners();
  }

  void setAwaitingCashPayment({required bool value, double? amount}) {
    _awaitingCashPayment = value;
    if (value && amount != null) {
      _awaitingCashAmount = amount;
      // เมื่อใช้โหมดเงินสด ให้ปิดสถานะรอชำระแบบ QR
      _awaitingQrPayment = false;
    } else if (!value) {
      _awaitingCashAmount = 0.0;
    }

    // Ensure _currentBill exists before mutating
    if (_currentBill != null) {
      _currentBill = Map<String, dynamic>.from(_currentBill!);
    } else {
      _currentBill = <String, dynamic>{};
    }

    _currentBill!['awaitingCashPayment'] = _awaitingCashPayment;
    _currentBill!['awaitingCashAmount'] = _awaitingCashAmount;
    _currentBill!['awaitingQrPayment'] = _awaitingQrPayment;

    _syncToLocalStorage();
    notifyListeners();
  }

  void setAwaitingQrPayment(bool value) {
    _awaitingQrPayment = value;
    if (value) {
      // เมื่อใช้โหมด QR ให้ปิดสถานะรอชำระเงินสด
      _awaitingCashPayment = false;
      _awaitingCashAmount = 0.0;
    }

    // Ensure _currentBill exists before mutating
    if (_currentBill != null) {
      _currentBill = Map<String, dynamic>.from(_currentBill!);
    } else {
      _currentBill = <String, dynamic>{};
    }

    _currentBill!['awaitingQrPayment'] = _awaitingQrPayment;
    _currentBill!['awaitingCashPayment'] = _awaitingCashPayment;
    _currentBill!['awaitingCashAmount'] = _awaitingCashAmount;

    _syncToLocalStorage();
    notifyListeners();
  }

  void setShowThankYouOverlay(bool value) {
    _showThankYouOverlay = value;

    // Ensure _currentBill exists before mutating
    if (_currentBill != null) {
      _currentBill = Map<String, dynamic>.from(_currentBill!);
    } else {
      _currentBill = <String, dynamic>{};
    }

    _currentBill!['showThankYouOverlay'] = _showThankYouOverlay;

    _syncToLocalStorage();
    notifyListeners();
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
        item['price'] ??
            item['unitPrice'] ??
            item['unit_price'] ??
            item['cost'],
      );
      sum += unitPrice * (qty <= 0 ? 1 : qty);
    }
    return sum;
  }

  void startReturnSession({required Map<String, dynamic> referenceBill}) {
    final refId =
        referenceBill['id']?.toString() ??
        referenceBill['billId']?.toString() ??
        '';
    if (refId.isEmpty) {
      throw Exception('ไม่พบบิลอ้างอิง');
    }
    _returnReferenceBill = {
      'id': refId,
      'createdAt': referenceBill['createdAt']?.toString(),
      'customerName': referenceBill['customerName']?.toString(),
      'status': referenceBill['status']?.toString(),
    };
    _returnLines.clear();
    notifyListeners();
  }

  void setReturnLineFromDetail({
    required Map<String, dynamic> detail,
    required int qty,
  }) {
    if (_returnReferenceBill == null) {
      throw Exception('ยังไม่ได้เลือกบิลอ้างอิง');
    }

    final partCode = detail['partCode']?.toString() ?? '';
    final addressCode = detail['addressCode']?.toString() ?? '';
    final codeKey = '$partCode|$addressCode';
    if (partCode.isEmpty) {
      throw Exception('รายการสินค้าไม่มี partCode');
    }

    final originalQty = _toDouble(detail['qty'] ?? detail['quantity']).toInt();
    final unitPrice = _toDouble(
      detail['price'] ?? detail['unitPrice'] ?? detail['unit_price'],
    );
    final safeQty = qty.clamp(0, originalQty <= 0 ? 0 : originalQty);

    _returnLines.removeWhere(
      (line) =>
          '${line['partCode'] ?? ''}|${line['addressCode'] ?? ''}' == codeKey,
    );

    if (safeQty > 0) {
      _returnLines.add({
        'type': 'return',
        'referenceBillId': _returnReferenceBill!['id'],
        'partCode': partCode,
        'addressCode': addressCode,
        'name':
            detail['nameTh']?.toString() ??
            detail['name']?.toString() ??
            'สินค้า',
        'qty': safeQty,
        'price': unitPrice,
        'lineTotal': -(unitPrice * safeQty),
        'originalQty': originalQty,
      });
    }

    notifyListeners();
  }

  void clearReturnSession() {
    _returnReferenceBill = null;
    _returnLines.clear();
    notifyListeners();
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
    // ถ้ามีบิลอยู่ ให้ยกเลิกบิลก่อนเพื่อคืนสต็อกใน backend
    if (_billId != null) {
      try {
        await ApiService.cancelBill(token: token, billId: _billId!);
      } catch (_) {
        // ถ้ายกเลิกบิลล้มเหลว ไม่ให้แอปค้าง แต่ยังคงพยายามสลับไปบิลใหม่
      }
    }

    await switchBill(token: token, targetBillId: '');
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

  Future<void> payCurrentBill({
    required String token,
    String paymentMethod = 'cash',
    String? paymentRef,
  }) async {
    if (_billId == null) {
      throw Exception('Bill id is not initialized');
    }

    isLoading = true;
    notifyListeners();
    try {
      final bill = await ApiService.payBill(
        token: token,
        billId: _billId!,
        paymentMethod: paymentMethod,
        paymentRef: paymentRef,
      );
      _applyBill(bill);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> holdCurrentBill({required String token}) async {
    if (_billId == null) {
      throw Exception('Bill id is not initialized');
    }
    isLoading = true;
    notifyListeners();
    try {
      final bill = await ApiService.holdBill(token: token, billId: _billId!);
      _applyBill(bill);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> cancelCurrentBill({required String token}) async {
    if (_billId == null) {
      throw Exception('Bill id is not initialized');
    }
    isLoading = true;
    notifyListeners();
    try {
      await ApiService.cancelBill(token: token, billId: _billId!);
      // หลังยกเลิกบิลปัจจุบันแล้ว สลับไปสร้างบิลใหม่ว่าง ๆ
      await switchBill(token: token, targetBillId: '');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteCurrentBill({required String token}) async {
    if (_billId == null) {
      throw Exception('Bill id is not initialized');
    }
    isLoading = true;
    notifyListeners();
    try {
      await ApiService.deleteBill(token: token, billId: _billId!);
      // หลังลบบิลแล้ว สร้างบิลใหม่ให้พร้อมใช้งานต่อ
      await switchBill(token: token, targetBillId: '');
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
