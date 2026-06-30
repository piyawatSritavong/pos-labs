import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:frontend/config/feature_flags.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/bill_provider.dart';
import 'package:frontend/providers/company_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/pos_mirror_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

class CartSummarySection extends StatefulWidget {
  const CartSummarySection({super.key});

  @override
  State<CartSummarySection> createState() => _CartSummarySectionState();
}

class _CartSummarySectionState extends State<CartSummarySection> {
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _memberPhoneController = TextEditingController();
  Map<String, TextEditingController>? _itemPriceControllers;
  Map<String, FocusNode>? _itemPriceFocusNodes;
  Map<String, double>? _itemBaseUnitPrices;
  Map<String, TextEditingController>? _qtyControllers;
  Map<String, FocusNode>? _qtyFocusNodes;
  bool _isPercentMode = true; // true = %, false = บาท
  double _discountAmount = 0.0;
  String _lastDiscountSyncSignature = '';

  Map<String, TextEditingController> get _safeItemPriceControllers =>
      _itemPriceControllers ??= <String, TextEditingController>{};
  Map<String, FocusNode> get _safeItemPriceFocusNodes =>
      _itemPriceFocusNodes ??= <String, FocusNode>{};
  Map<String, TextEditingController> get _safeQtyControllers =>
      _qtyControllers ??= <String, TextEditingController>{};
  Map<String, FocusNode> get _safeQtyFocusNodes =>
      _qtyFocusNodes ??= <String, FocusNode>{};
  Map<String, double> get _safeItemBaseUnitPrices =>
      _itemBaseUnitPrices ??= <String, double>{};

  @override
  void dispose() {
    _discountController.dispose();
    _memberPhoneController.dispose();
    for (final controller in _safeItemPriceControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _safeItemPriceFocusNodes.values) {
      focusNode.dispose();
    }
    for (final c in _safeQtyControllers.values) {
      c.dispose();
    }
    for (final f in _safeQtyFocusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String _itemKey(_BillLineItem item) {
    return '${item.partCode ?? item.code}|${item.addressCode ?? ''}|${item.isReturn}';
  }

  void _syncItemPriceEditors(List<_BillLineItem> items) {
    final itemPriceControllers = _safeItemPriceControllers;
    final itemPriceFocusNodes = _safeItemPriceFocusNodes;
    final itemBaseUnitPrices = _safeItemBaseUnitPrices;
    final activeKeys = items
        .where((item) => !item.isReturn)
        .map(_itemKey)
        .toSet();

    final staleKeys = itemPriceControllers.keys
        .where((key) => !activeKeys.contains(key))
        .toList();
    for (final key in staleKeys) {
      itemPriceControllers.remove(key)?.dispose();
      itemPriceFocusNodes.remove(key)?.dispose();
      itemBaseUnitPrices.remove(key);
    }

    for (final item in items.where((entry) => !entry.isReturn)) {
      final key = _itemKey(item);
      final controller = itemPriceControllers.putIfAbsent(
        key,
        () => TextEditingController(),
      );
      final focusNode = itemPriceFocusNodes.putIfAbsent(key, () => FocusNode());
      itemBaseUnitPrices.putIfAbsent(key, () => item.price);
      final lineTotal = (item.price * item.qty).toStringAsFixed(2);
      if (!focusNode.hasFocus && controller.text != lineTotal) {
        controller.text = lineTotal;
      }
    }
  }

  void _syncQtyEditors(List<_BillLineItem> items) {
    final controllers = _safeQtyControllers;
    final focusNodes = _safeQtyFocusNodes;
    final activeKeys = items.where((i) => !i.isReturn).map(_itemKey).toSet();

    for (final key
        in controllers.keys.where((k) => !activeKeys.contains(k)).toList()) {
      controllers.remove(key)?.dispose();
      focusNodes.remove(key)?.dispose();
    }

    for (final item in items.where((i) => !i.isReturn)) {
      final key = _itemKey(item);
      final controller = controllers.putIfAbsent(
        key,
        () => TextEditingController(text: '${item.qty}'),
      );
      focusNodes.putIfAbsent(key, () => FocusNode());
      final expected = '${item.qty}';
      if (!focusNodes[key]!.hasFocus && controller.text != expected) {
        controller.text = expected;
      }
    }
  }

  Future<void> _setItemQty(
    BuildContext context,
    _BillLineItem item,
    int newQty,
  ) async {
    if (item.isReturn || item.partCode == null || item.addressCode == null) {
      return;
    }
    final currentQty = item.qty;
    if (newQty == currentQty) return;

    final auth = context.read<AuthProvider>();
    final bill = context.read<BillProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final token = auth.token;
    if (token == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
      );
      return;
    }

    try {
      if (newQty <= 0) {
        PosMirrorService.current?.notifyLastAction('qty_remove');
        await bill.removeItem(
          token: token,
          partCode: item.partCode!,
          addressCode: item.addressCode!,
          qty: 1,
          isRemoveAll: true,
        );
      } else if (newQty > currentQty) {
        PosMirrorService.current?.notifyLastAction('qty_add');
        await bill.addItem(
          token: token,
          partCode: item.partCode!,
          addressCode: item.addressCode!,
          qty: newQty - currentQty,
        );
      } else {
        PosMirrorService.current?.notifyLastAction('qty_remove');
        await bill.removeItem(
          token: token,
          partCode: item.partCode!,
          addressCode: item.addressCode!,
          qty: currentQty - newQty,
          isRemoveAll: false,
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('อัปเดตจำนวนสินค้าไม่สำเร็จ: $e')),
      );
    }
  }

  double _computeDiscountPreviewAmount(
    double subtotal,
    double inputValue,
    bool isPercentMode,
  ) {
    final rawAmount = isPercentMode
        ? subtotal * (inputValue / 100.0)
        : inputValue;
    return rawAmount.clamp(0.0, subtotal).toDouble();
  }

  String _friendlyItemPriceError(Object error) {
    final message = error.toString();
    if (message.contains('price_below_minimum')) {
      return 'ลดราคาได้ไม่เกิน 10% ของยอดรายการนี้';
    }
    if (message.contains('invalid_line_total')) {
      return 'กรุณากรอกราคามากกว่า 0';
    }
    return 'แก้ไขราคาไม่สำเร็จ: $error';
  }

  Future<void> _increaseItemQty(
    BuildContext context,
    _BillLineItem item,
  ) async {
    if (item.isReturn || item.partCode == null || item.addressCode == null) {
      return;
    }
    final auth = context.read<AuthProvider>();
    final bill = context.read<BillProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final token = auth.token;
    if (token == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
      );
      return;
    }

    PosMirrorService.current?.notifyLastAction('qty_add');
    try {
      await bill.addItem(
        token: token,
        partCode: item.partCode!,
        addressCode: item.addressCode!,
        qty: 1,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('เพิ่มจำนวนสินค้าไม่สำเร็จ: $e')),
      );
    }
  }

  Future<void> _decreaseItemQty(
    BuildContext context,
    _BillLineItem item,
  ) async {
    if (item.isReturn || item.partCode == null || item.addressCode == null) {
      return;
    }
    final auth = context.read<AuthProvider>();
    final bill = context.read<BillProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final token = auth.token;
    if (token == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
      );
      return;
    }

    PosMirrorService.current?.notifyLastAction('qty_remove');
    try {
      await bill.removeItem(
        token: token,
        partCode: item.partCode!,
        addressCode: item.addressCode!,
        qty: 1,
        isRemoveAll: item.qty <= 1,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('ลดจำนวนสินค้าไม่สำเร็จ: $e')),
      );
    }
  }

  Future<void> _updateLineTotalPrice(
    BuildContext context,
    _BillLineItem item,
  ) async {
    if (item.isReturn || item.partCode == null || item.addressCode == null) {
      return;
    }
    final key = _itemKey(item);
    final controller = _safeItemPriceControllers[key];
    if (controller == null) {
      return;
    }

    final raw = controller.text.trim().replaceAll(',', '');
    final currentLineTotal = item.price * item.qty;
    if (raw.isEmpty) {
      controller.text = currentLineTotal.toStringAsFixed(2);
      return;
    }

    final parsed = double.tryParse(raw);
    if (parsed == null) {
      controller.text = currentLineTotal.toStringAsFixed(2);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('รูปแบบราคาไม่ถูกต้อง')));
      return;
    }

    if ((parsed - currentLineTotal).abs() < 0.0001) {
      controller.text = currentLineTotal.toStringAsFixed(2);
      return;
    }

    final auth = context.read<AuthProvider>();
    final bill = context.read<BillProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final token = auth.token;
    if (token == null) {
      controller.text = currentLineTotal.toStringAsFixed(2);
      messenger.showSnackBar(
        const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
      );
      return;
    }

    try {
      await bill.updateItemLineTotal(
        token: token,
        partCode: item.partCode!,
        addressCode: item.addressCode!,
        lineTotal: parsed,
      );
    } catch (e) {
      controller.text = currentLineTotal.toStringAsFixed(2);
      messenger.showSnackBar(
        SnackBar(content: Text(_friendlyItemPriceError(e))),
      );
    }
  }

  List<_BillLineItem> _mapItems(
    List<Map<String, dynamic>> rawItems,
    List<Map<String, dynamic>> returnLines,
  ) {
    final purchaseItems = rawItems.map((item) {
      final qtyRaw = _toDouble(
        item['qty'] ?? item['quantity'] ?? item['amount'],
      );
      final qty = qtyRaw <= 0 ? 1 : qtyRaw.toInt();
      final price = _toDouble(
        item['unitPrice'] ?? item['price'] ?? item['unit_price'],
      );
      final total = _toDouble(item['amount'] ?? item['total'] ?? price * qty);
      final resolvedPrice = price > 0 ? price : (qty > 0 ? total / qty : total);
      final partCode = item['partCode']?.toString() ?? item['code']?.toString();
      final addressCode =
          item['addressCode']?.toString() ?? item['storeCode']?.toString();

      final totalStock = (item['totalStock'] ?? item['total_stock'] ?? 0) is num
          ? ((item['totalStock'] ?? item['total_stock'] ?? 0) as num).toInt()
          : 0;

      return _BillLineItem(
        name:
            item['nameTh']?.toString() ??
            item['name']?.toString() ??
            item['description']?.toString() ??
            'สินค้า',
        code: partCode ?? '-',
        qty: qty,
        price: resolvedPrice,
        partCode: partCode,
        addressCode: addressCode,
        isReturn: false,
        totalStock: totalStock,
      );
    }).toList();

    final mappedReturn = returnLines.map((line) {
      final qtyRaw = _toDouble(line['qty']);
      final qty = qtyRaw <= 0 ? 1 : qtyRaw.toInt();
      final lineTotal = _toDouble(line['lineTotal'] ?? line['amount']).abs();
      final unitPrice = qty > 0 ? lineTotal / qty : lineTotal;
      return _BillLineItem(
        name: line['name']?.toString() ?? 'คืนสินค้า',
        code: line['partCode']?.toString() ?? '-',
        qty: qty,
        price: unitPrice,
        partCode: line['partCode']?.toString(),
        addressCode: line['addressCode']?.toString(),
        isReturn: true,
      );
    }).toList();

    return [...mappedReturn, ...purchaseItems];
  }

  Future<void> _holdBill(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final bill = context.read<BillProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final token = auth.token;
    if (token == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
      );
      return;
    }

    PosMirrorService.current?.notifyLastAction('hold');
    try {
      await bill.holdCurrentBill(token: token);
      bill.resetCurrentBillState();
      messenger.showSnackBar(const SnackBar(content: Text('พักบิลแล้ว')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('พักบิลไม่สำเร็จ: $e')));
    }
  }

  Future<void> _clearBill(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final bill = context.read<BillProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final token = auth.token;
    if (token == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
      );
      return;
    }

    PosMirrorService.current?.notifyLastAction('clear');
    try {
      await bill.clearBill(token: token);
      messenger.showSnackBar(const SnackBar(content: Text('ล้างตะกร้าแล้ว')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('ล้างบิลไม่สำเร็จ: $e')));
    }
  }

  Future<void> _attachMemberToBill(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final bill = context.read<BillProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final token = auth.token;
    if (token == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
      );
      return;
    }

    final phone = _memberPhoneController.text.trim();
    if (phone.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('กรุณากรอกเบอร์โทรสมาชิก')),
      );
      return;
    }

    try {
      await bill.assignMemberByPhone(token: token, phone: phone);
      if (!mounted) return;
      _memberPhoneController.clear();
      messenger.showSnackBar(
        const SnackBar(content: Text('ผูกสมาชิกเข้าบิลแล้ว')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('ผูกสมาชิกไม่สำเร็จ: $e')));
    }
  }

  void _applyQuickDiscount(
    BuildContext context,
    double percent,
    double subtotal,
  ) {
    PosMirrorService.current?.notifyLastAction('discount_${percent.toInt()}');
    final bill = context.read<BillProvider>();
    final nextAmount = _computeDiscountPreviewAmount(subtotal, percent, true);
    setState(() {
      _isPercentMode = true;
      _discountController.text = percent.toStringAsFixed(0);
      _discountAmount = nextAmount;
    });
    bill.applyLocalDiscount(discountAmount: nextAmount);
  }

  void _recalculateDiscount(BuildContext context, double subtotal) {
    final bill = context.read<BillProvider>();
    final raw = _discountController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _discountAmount = 0.0;
      });
      bill.applyLocalDiscount(discountAmount: 0.0);
      return;
    }

    final parsed = double.tryParse(raw.replaceAll(',', ''));
    if (parsed == null) {
      return;
    }

    final nextAmount = _computeDiscountPreviewAmount(
      subtotal,
      parsed,
      _isPercentMode,
    );
    setState(() {
      _discountAmount = nextAmount;
    });
    bill.applyLocalDiscount(discountAmount: nextAmount);
  }

  String _formatDiscountInput(double value) {
    if (value <= 0) {
      return '';
    }
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.0001) {
      return rounded.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  void _syncDiscountInputFromBill(BillProvider bill) {
    final manual = bill.manualDiscountDetail;
    final signature = [
      bill.billId ?? '',
      manual?['promotionCode']?.toString() ?? '',
      manual?['unit']?.toString() ?? '',
      manual?['amount']?.toString() ?? '',
      bill.subtotal.toStringAsFixed(2),
      _discountController.text.trim(),
      _isPercentMode.toString(),
    ].join('|');
    if (signature == _lastDiscountSyncSignature) {
      return;
    }
    _lastDiscountSyncSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final hasManual = manual != null;
      if (hasManual) {
        final nextPercentMode = bill.isManualDiscountPercentMode;
        final inputValue = bill.manualDiscountInputValue;
        final nextAmount = _computeDiscountPreviewAmount(
          bill.subtotal,
          inputValue,
          nextPercentMode,
        );
        final nextText = _formatDiscountInput(inputValue);
        final requiresStateSync =
            _isPercentMode != nextPercentMode ||
            (_discountAmount - nextAmount).abs() >= 0.01 ||
            _discountController.text != nextText;

        if (requiresStateSync) {
          setState(() {
            _isPercentMode = nextPercentMode;
            _discountAmount = nextAmount;
            if (_discountController.text != nextText) {
              _discountController.text = nextText;
            }
          });
        }
        return;
      }

      final raw = _discountController.text.trim().replaceAll(',', '');
      if (raw.isEmpty) {
        if (_discountAmount != 0.0) {
          setState(() {
            _discountAmount = 0.0;
          });
        }
        return;
      }

      final parsed = double.tryParse(raw);
      if (parsed == null) {
        return;
      }

      final nextAmount = _computeDiscountPreviewAmount(
        bill.subtotal,
        parsed,
        _isPercentMode,
      );
      if ((_discountAmount - nextAmount).abs() >= 0.01) {
        setState(() {
          _discountAmount = nextAmount;
        });
      }
      if ((bill.discount - nextAmount).abs() >= 0.01) {
        bill.applyLocalDiscount(discountAmount: nextAmount);
      }
    });
  }

  Future<bool> _persistManualDiscount(
    BuildContext context, {
    required String token,
  }) async {
    final bill = context.read<BillProvider>();
    final messenger = ScaffoldMessenger.of(context);

    if (bill.items.isEmpty) {
      return true;
    }

    final raw = _discountController.text.trim().replaceAll(',', '');
    if (raw.isEmpty) {
      try {
        await bill.clearManualDiscount(token: token);
        return true;
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('ลบส่วนลดไม่สำเร็จ: $e')),
        );
        return false;
      }
    }

    final parsed = double.tryParse(raw);
    if (parsed == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('รูปแบบส่วนลดไม่ถูกต้อง')),
      );
      return false;
    }

    if (parsed <= 0) {
      try {
        await bill.clearManualDiscount(token: token);
        return true;
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('ลบส่วนลดไม่สำเร็จ: $e')),
        );
        return false;
      }
    }

    try {
      await bill.setManualDiscount(
        token: token,
        isPercentMode: _isPercentMode,
        inputValue: parsed,
      );
      return true;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('บันทึกส่วนลดไม่สำเร็จ: $e')),
      );
      return false;
    }
  }

  void _resetPaymentState() {
    setState(() {
      _discountAmount = 0.0;
      _isPercentMode = true;
      _discountController.clear();
      _lastDiscountSyncSignature = '';
    });
  }

  Future<void> _handleConfirmPayment(BuildContext context) async {
    PosMirrorService.current?.notifyLastAction('pay');
    final bill = context.read<BillProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('token หาย กรุณา login ใหม่')),
      );
      return;
    }

    final discountSaved = await _persistManualDiscount(context, token: token);
    if (!discountSaved || !mounted) {
      return;
    }

    final total = bill.netSettlementAmount;
    final hasPurchaseItems = bill.items.isNotEmpty;
    final hasReturnItems = bill.hasReturnItems;
    String returnSettleMode = 'none';
    final referenceBillId = bill.returnReferenceBillId;
    _PaymentSelection? paymentSelection;

    if (hasReturnItems && total < 0) {
      final settle = await showDialog<_ReturnSettlement>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ReturnSettlementDialog(
          refundAmount: total.abs(),
          hasMember: bill.assignedMember != null,
        ),
      );
      if (settle == null || !mounted) return;
      returnSettleMode = settle == _ReturnSettlement.credit
          ? 'customer_credit'
          : 'cash_refund';
    } else if (hasReturnItems) {
      returnSettleMode = 'exchange';
    }

    if (hasPurchaseItems) {
      if (total > 0) {
        final selectedMethod = await showDialog<_PaymentSelection>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _PaymentMethodDialog(total: total),
        );

        if (selectedMethod == null || !mounted) return;
        paymentSelection = selectedMethod;

        if (selectedMethod.kind == _PaymentKind.transfer) {
          bill.setAwaitingQrPayment(true);

          if (!mounted) return;

          final confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('ลูกค้าชำระเงินเรียบร้อย'),
              content: Text(
                'ลูกค้าชำระเงินผ่านการโอน ตามยอด ฿${total.toStringAsFixed(2)} เรียบร้อยแล้วหรือไม่?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('ไม่ใช่'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('ใช่'),
                ),
              ],
            ),
          );

          if (!mounted) return;

          if (confirmed != true) {
            bill.setAwaitingQrPayment(false);
            return;
          }

          bill.setAwaitingQrPayment(false);
        } else if (selectedMethod.kind == _PaymentKind.cash) {
          bill.setAwaitingCashPayment(value: true, amount: total);

          if (!mounted) return;

          final cashResult = await showDialog<_CashPaymentResult>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => _CashConfirmDialog(total: total),
          );

          if (!mounted) return;

          if (cashResult == null) {
            bill.setAwaitingCashPayment(value: false);
            return;
          }

          paymentSelection = _PaymentSelection.cash(
            receivedAmount: cashResult.receivedAmount,
            changeAmount: cashResult.changeAmount,
            totalAmount: total,
          );
          bill.setAwaitingCashPayment(value: false);
        }
      } else {
        paymentSelection = _PaymentSelection.exchange(
          netSettlementAmount: total,
        );
      }
    }

    if (!mounted) return;
    final checkoutBillId = bill.billId;
    var paymentSaved = false;
    var returnSaved = false;
    var receiptPrinted = false;
    var returnReceiptPrinted = false;
    String? returnNoteId;

    Future<void> finalizeCheckout() async {
      if (!paymentSaved &&
          hasPurchaseItems &&
          paymentSelection != null &&
          checkoutBillId != null) {
        await bill.payCurrentBill(
          token: token,
          paymentMethod: paymentSelection.backendMethod,
          paymentMeta: paymentSelection.paymentMeta,
        );
        paymentSaved = true;
      }

      if (!returnSaved && hasReturnItems && referenceBillId != null) {
        final returnNote = await bill.createReturnNote(
          token: token,
          settlementMode: returnSettleMode == 'none'
              ? 'exchange'
              : returnSettleMode,
          purchaseBillId: hasPurchaseItems ? checkoutBillId : null,
          paymentMethod: paymentSelection?.backendMethod,
          paymentMeta: paymentSelection?.paymentMeta,
        );
        returnNoteId =
            returnNote['id']?.toString() ??
            returnNote['returnNoteId']?.toString();
        if (returnNoteId == null || returnNoteId!.isEmpty) {
          throw Exception('สร้างใบคืนสินค้าแล้วแต่ไม่พบเลขที่ใบคืนสินค้า');
        }
        returnSaved = true;
      }

      if (!receiptPrinted && hasPurchaseItems && checkoutBillId != null) {
        await ApiService.printReceipt(
          token: token,
          billId: checkoutBillId,
          idempotencyKey: 'checkout:$checkoutBillId',
        );
        receiptPrinted = true;
      }

      if (!returnReceiptPrinted && hasReturnItems && returnNoteId != null) {
        await ApiService.printReturnReceipt(
          token: token,
          returnNoteId: returnNoteId!,
          idempotencyKey: 'return:${returnNoteId!}',
        );
        returnReceiptPrinted = true;
      }
    }

    bill.setShowThankYouOverlay(false);
    final paid = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ReceiptDialog(
        settlementTotal: total,
        hasPurchaseItems: hasPurchaseItems,
        onFinalize: finalizeCheckout,
        paymentSelection: paymentSelection,
        returnSettleMode: returnSettleMode == 'none' ? null : returnSettleMode,
      ),
    );

    if (paid == true && mounted) {
      bill.clearReturnSession();
      _resetPaymentState();
      bill.resetCurrentBillState();
    }

    if (mounted && paid != true) {
      bill.setShowThankYouOverlay(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bill = context.watch<BillProvider>();
    _syncDiscountInputFromBill(bill);
    final items = _mapItems(bill.items, bill.returnLines);
    _syncItemPriceEditors(items);
    _syncQtyEditors(items);
    final subtotal = bill.subtotal;
    final taxRate = bill.taxRate;
    final tax = bill.tax;
    final effectiveDiscount = bill.discount;
    final returnCredit = bill.returnCreditAmount;
    final total = bill.netSettlementAmount;
    final hasSettlementItems = bill.items.isNotEmpty || bill.hasReturnItems;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobileView = MediaQuery.of(context).size.shortestSide < 600;
        final isCompact =
            constraints.maxWidth < 400 || constraints.maxHeight < 520;
        final isTightHeight = constraints.maxHeight < 480;
        final panelPadding = isMobileView
            ? 6.0
            : (isTightHeight ? 14.0 : (isCompact ? 16.0 : 20.0));
        final sectionGap = isMobileView
            ? 6.0
            : (isTightHeight ? 6.0 : (isCompact ? 8.0 : 12.0));
        final summaryRowGap = isMobileView ? 6.0 : (isTightHeight ? 6.0 : 8.0);
        final useSplitLayout = constraints.maxWidth >= 760;
        final quickDiscountButtonStyle = OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(
            horizontal: isMobileView ? 6 : 10,
            vertical: isMobileView ? 6 : 8,
          ),
          minimumSize: const Size(0, 34),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          visualDensity: VisualDensity.compact,
        );
        final itemListPanel = Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colorBorder),
          ),
          padding: EdgeInsets.all(isMobileView ? 6 : (isTightHeight ? 10 : 12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: Text(
                      'ชื่อ',
                      style: TextStyle(
                        color: context.colorMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'จำนวน',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.colorMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'ราคา',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: context.colorMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Divider(
                height: 1,
                color: context.colorBorder.withValues(alpha: 0.7),
              ),
              SizedBox(height: sectionGap),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          'ยังไม่มีสินค้าในตะกร้า',
                          style: TextStyle(color: context.colorMuted),
                        ),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        padding: EdgeInsets.symmetric(vertical: sectionGap),
                        itemBuilder: (context, index) {
                          final it = items[index];
                          final lineTotal = (it.price * it.qty).toStringAsFixed(
                            2,
                          );
                          final itemKey = _itemKey(it);
                          final priceController =
                              _safeItemPriceControllers[itemKey];
                          final priceFocusNode =
                              _safeItemPriceFocusNodes[itemKey];
                          return Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: isMobileView ? 6 : 8,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${it.name} • ${it.code}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (!it.isReturn &&
                                          it.totalStock > 0 &&
                                          it.qty >= it.totalStock)
                                        const Row(
                                          children: [
                                            Icon(
                                              Icons.warning_amber_rounded,
                                              size: 12,
                                              color: Colors.orange,
                                            ),
                                            SizedBox(width: 3),
                                            Text(
                                              'สต๊อกใกล้หมด',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.orange,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: it.isReturn
                                      ? Text(
                                          '-${it.qty}',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        )
                                      : Align(
                                          alignment: Alignment.center,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.center,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  onPressed: bill.isLoading
                                                      ? null
                                                      : () => _decreaseItemQty(
                                                          context,
                                                          it,
                                                        ),
                                                  icon: const Icon(
                                                    Icons.remove,
                                                  ),
                                                  iconSize: 18,
                                                  padding: EdgeInsets.zero,
                                                  constraints:
                                                      const BoxConstraints.tightFor(
                                                        width: 24,
                                                        height: 24,
                                                      ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  tooltip: 'ลดจำนวน',
                                                ),
                                                SizedBox(
                                                  width: 40,
                                                  child: TextField(
                                                    controller:
                                                        _safeQtyControllers[itemKey],
                                                    focusNode:
                                                        _safeQtyFocusNodes[itemKey],
                                                    textAlign: TextAlign.center,
                                                    keyboardType:
                                                        TextInputType.number,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 13,
                                                    ),
                                                    decoration: const InputDecoration(
                                                      isDense: true,
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                            vertical: 4,
                                                            horizontal: 2,
                                                          ),
                                                      border:
                                                          OutlineInputBorder(),
                                                    ),
                                                    onSubmitted: (v) {
                                                      final n = int.tryParse(v);
                                                      if (n != null) {
                                                        _setItemQty(
                                                          context,
                                                          it,
                                                          n,
                                                        );
                                                      }
                                                    },
                                                    onTapOutside: (_) {
                                                      final v =
                                                          _safeQtyControllers[itemKey]
                                                              ?.text ??
                                                          '';
                                                      final n = int.tryParse(v);
                                                      if (n != null) {
                                                        _setItemQty(
                                                          context,
                                                          it,
                                                          n,
                                                        );
                                                      }
                                                      _safeQtyFocusNodes[itemKey]
                                                          ?.unfocus();
                                                    },
                                                  ),
                                                ),
                                                IconButton(
                                                  onPressed: bill.isLoading
                                                      ? null
                                                      : () => _increaseItemQty(
                                                          context,
                                                          it,
                                                        ),
                                                  icon: const Icon(Icons.add),
                                                  iconSize: 18,
                                                  padding: EdgeInsets.zero,
                                                  constraints:
                                                      const BoxConstraints.tightFor(
                                                        width: 24,
                                                        height: 24,
                                                      ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  tooltip: 'เพิ่มจำนวน',
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: it.isReturn
                                      ? Text(
                                          '-฿$lineTotal',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: context.colorDanger,
                                          ),
                                        )
                                      : Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TextField(
                                              controller: priceController,
                                              focusNode: priceFocusNode,
                                              enabled: !bill.isLoading,
                                              textAlign: TextAlign.right,
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                prefixText: '฿',
                                                border: OutlineInputBorder(),
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 6,
                                                    ),
                                              ),
                                              onSubmitted: (_) =>
                                                  _updateLineTotalPrice(
                                                    context,
                                                    it,
                                                  ),
                                              onTapOutside: (_) =>
                                                  _updateLineTotalPrice(
                                                    context,
                                                    it,
                                                  ),
                                            ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
        final pricingPanel = Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colorBorder),
          ),
          padding: EdgeInsets.all(isMobileView ? 6 : (isTightHeight ? 10 : 12)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDialogSummaryRow(
                    context,
                    'ราคารวม',
                    '฿${subtotal.toStringAsFixed(2)}',
                  ),
                  SizedBox(height: summaryRowGap),
                  _buildDialogSummaryRow(
                    context,
                    'ส่วนลด',
                    '- ฿${effectiveDiscount.toStringAsFixed(2)}',
                  ),
                  if (returnCredit > 0) ...[
                    SizedBox(height: summaryRowGap),
                    _buildDialogSummaryRow(
                      context,
                      'คืนสินค้า (Credit)',
                      '- ฿${returnCredit.toStringAsFixed(2)}',
                    ),
                  ],
                  SizedBox(height: summaryRowGap),
                  _buildDialogSummaryRow(
                    context,
                    'ภาษี (${(taxRate * 100).toStringAsFixed(0)}%)',
                    '฿${tax.toStringAsFixed(2)}',
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'ส่วนลด',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      SizedBox(width: isMobileView ? 6 : 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final percent in [5, 10, 15, 20])
                            OutlinedButton(
                              style: quickDiscountButtonStyle,
                              onPressed: () => _applyQuickDiscount(
                                context,
                                percent.toDouble(),
                                subtotal,
                              ),
                              child: Text('$percent%'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: sectionGap),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _discountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'ส่วนลด',
                            hintText: 'เช่น 5 หรือ 100',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) =>
                              _recalculateDiscount(context, subtotal),
                        ),
                      ),
                      SizedBox(width: isMobileView ? 6 : 8),
                      DropdownButton<bool>(
                        value: _isPercentMode,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _isPercentMode = value);
                          _recalculateDiscount(context, subtotal);
                        },
                        items: const [
                          DropdownMenuItem(value: true, child: Text('%')),
                          DropdownMenuItem(value: false, child: Text('บาท')),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      vertical: isMobileView ? 6 : (isCompact ? 10 : 12),
                      horizontal: isMobileView ? 6 : 14,
                    ),
                    decoration: BoxDecoration(
                      color: context.colorPrimary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(AppSizes.radius),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'รวมสุทธิ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${total < 0 ? '-฿' : '฿'}${total.abs().toStringAsFixed(2)}',
                          style: TextStyle(
                            color: total < 0
                                ? context.colorDanger
                                : context.colorPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: sectionGap),
                  ElevatedButton(
                    onPressed: (bill.isLoading || !hasSettlementItems)
                        ? null
                        : () => _handleConfirmPayment(context),
                    child: const Text('ชำระเงิน'),
                  ),
                  SizedBox(height: sectionGap),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: bill.isLoading
                              ? null
                              : () => _holdBill(context),
                          child: const Text('พักบิล'),
                        ),
                      ),
                      SizedBox(width: isMobileView ? 6 : 12),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.colorDanger,
                            side: BorderSide(color: context.colorDanger),
                          ),
                          onPressed: bill.isLoading
                              ? null
                              : () => _clearBill(context),
                          child: const Text('ล้างบิล'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );

        return Container(
          decoration: BoxDecoration(
            color: context.colorSurface,
            borderRadius: BorderRadius.circular(AppSizes.radius),
            border: Border.all(color: context.colorBorder),
            boxShadow: AppShadows.soft,
          ),
          padding: EdgeInsets.all(panelPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'ตะกร้าสินค้า',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(width: isMobileView ? 6 : 12),
                  if (bill.assignedMember != null) ...[
                    // Member chip — show who is linked
                    Expanded(
                      child: Container(
                        height: 40,
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobileView ? 6 : 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.person,
                              size: 16,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                bill.memberDisplayName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: isMobileView ? 6 : 8),
                    IconButton(
                      tooltip: 'ยกเลิกสมาชิก',
                      onPressed: bill.isLoading
                          ? null
                          : () async {
                              final token = context.read<AuthProvider>().token;
                              if (token == null) return;
                              try {
                                await context
                                    .read<BillProvider>()
                                    .unassignMember(token: token);
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('ยกเลิกสมาชิกไม่สำเร็จ: $e'),
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ] else ...[
                    // Phone input for linking a member
                    Expanded(
                      child: TextField(
                        controller: _memberPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: 'เบอร์โทรสมาชิก',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _attachMemberToBill(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: bill.isLoading
                          ? null
                          : () => _attachMemberToBill(context),
                      child: const Text('ผูกสมาชิก'),
                    ),
                  ],
                ],
              ),
              if (bill.hasReturnItems) ...[
                SizedBox(height: sectionGap),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobileView ? 6 : 10,
                    vertical: isMobileView ? 6 : (isCompact ? 6 : 8),
                  ),
                  decoration: BoxDecoration(
                    color: context.colorDanger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: context.colorDanger.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'คืนจากบิล ${bill.returnReferenceBillId ?? '-'} • ${bill.returnLineCount} ชิ้น',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colorDanger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: bill.isLoading
                            ? null
                            : bill.clearReturnSession,
                        child: const Text('ล้างรายการคืน'),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: sectionGap),
              Expanded(
                child: useSplitLayout
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 6, child: itemListPanel),
                          SizedBox(width: sectionGap),
                          Expanded(flex: 4, child: pricingPanel),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(flex: 2, child: itemListPanel),
                          SizedBox(height: sectionGap),
                          Expanded(flex: 3, child: pricingPanel),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDialogSummaryRow(
    BuildContext context,
    String label,
    String value, {
    bool isEmphasis = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isEmphasis ? FontWeight.bold : FontWeight.normal,
            fontSize: isEmphasis ? 16 : 14,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isEmphasis ? FontWeight.bold : FontWeight.normal,
            fontSize: isEmphasis ? 16 : 14,
            color: isEmphasis ? context.colorPrimary : null,
          ),
        ),
      ],
    );
  }
}

class _QrPaymentDialog extends StatefulWidget {
  const _QrPaymentDialog();

  @override
  State<_QrPaymentDialog> createState() => _QrPaymentDialogState();
}

class _QrPaymentDialogState extends State<_QrPaymentDialog> {
  bool _showSuccess = false;
  Future<Uint8List>? _qrFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _qrFuture ??= ApiService.getQrImage(
      token: context.read<AuthProvider>().token ?? '',
    );
  }

  Future<void> _handleConfirm() async {
    if (_showSuccess) return;
    setState(() => _showSuccess = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'สแกนเพื่อชำระเงิน',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 440,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: FutureBuilder<Uint8List>(
                        future: _qrFuture,
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (snap.hasData && snap.data != null) {
                            return Image.memory(
                              snap.data!,
                              fit: BoxFit.contain,
                            );
                          }
                          return const Center(
                            child: Text(
                              'ไม่พบรูป QR code\nกรุณาอัปโหลดที่หน้าตั้งค่าการชำระเงิน',
                              textAlign: TextAlign.center,
                            ),
                          );
                        },
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: _showSuccess ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(color: Colors.black),
                    ),
                    AnimatedScale(
                      scale: _showSuccess ? 1.0 : 0.6,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutBack,
                      child: AnimatedOpacity(
                        opacity: _showSuccess ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 96,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _handleConfirm,
                child: const Text('ชำระเสร็จสิ้น'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('ยกเลิก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BillLineItem {
  _BillLineItem({
    required this.name,
    required this.code,
    required this.qty,
    required this.price,
    this.partCode,
    this.addressCode,
    required this.isReturn,
    this.totalStock = 0,
  });

  final String name;
  final String code;
  final int qty;
  final double price;
  final String? partCode;
  final String? addressCode;
  final bool isReturn;
  final int totalStock;
}

enum _PaymentKind { cash, transfer, creditTerm, exchange }

class _CreditTermInstallment {
  const _CreditTermInstallment({required this.dueDate, required this.amount});

  final DateTime dueDate;
  final double amount;

  Map<String, dynamic> toJson(int index) {
    return <String, dynamic>{
      'label': 'งวดที่ ${index + 1}',
      'dueDate': _formatDateValue(dueDate),
      'amount': amount,
    };
  }
}

class _PaymentSelection {
  const _PaymentSelection({
    required this.kind,
    required this.backendMethod,
    required this.label,
    this.paymentMeta,
    this.deliveryDate,
    this.installments = const <_CreditTermInstallment>[],
  });

  factory _PaymentSelection.cash({
    double? receivedAmount,
    double? changeAmount,
    double? totalAmount,
  }) {
    return _PaymentSelection(
      kind: _PaymentKind.cash,
      backendMethod: 'cash',
      label: 'เงินสด',
      paymentMeta: <String, dynamic>{
        'type': 'cash',
        if (receivedAmount != null) 'receivedAmount': receivedAmount,
        if (changeAmount != null) 'changeAmount': changeAmount,
        if (totalAmount != null) 'totalAmount': totalAmount,
      },
    );
  }

  factory _PaymentSelection.transfer() {
    return const _PaymentSelection(
      kind: _PaymentKind.transfer,
      backendMethod: 'bank',
      label: 'โอน',
    );
  }

  factory _PaymentSelection.creditTerm({
    required DateTime deliveryDate,
    required List<_CreditTermInstallment> installments,
  }) {
    final paymentMeta = <String, dynamic>{
      'type': 'credit_term',
      'deliveryDate': _formatDateValue(deliveryDate),
      'installments': [
        for (var i = 0; i < installments.length; i++) installments[i].toJson(i),
      ],
    };
    return _PaymentSelection(
      kind: _PaymentKind.creditTerm,
      backendMethod: 'credit_term',
      label: 'เงินเซ็น',
      paymentMeta: paymentMeta,
      deliveryDate: deliveryDate,
      installments: installments,
    );
  }

  factory _PaymentSelection.exchange({required double netSettlementAmount}) {
    return _PaymentSelection(
      kind: _PaymentKind.exchange,
      backendMethod: 'exchange',
      label: 'แลกเปลี่ยน',
      paymentMeta: <String, dynamic>{
        'type': 'exchange',
        'netSettlementAmount': netSettlementAmount,
      },
    );
  }

  final _PaymentKind kind;
  final String backendMethod;
  final String label;
  final Object? paymentMeta;
  final DateTime? deliveryDate;
  final List<_CreditTermInstallment> installments;
}

String _formatDateValue(DateTime date) {
  final local = date.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

class _ReceiptDialog extends StatefulWidget {
  const _ReceiptDialog({
    required this.settlementTotal,
    required this.hasPurchaseItems,
    required this.onFinalize,
    this.paymentSelection,
    this.returnSettleMode,
  });

  final double settlementTotal;
  final bool hasPurchaseItems;
  final Future<void> Function() onFinalize;
  final _PaymentSelection? paymentSelection;
  final String? returnSettleMode;

  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
  // Snapshot of `widget.*` for terser access inside build().
  double get settlementTotal => widget.settlementTotal;
  bool get hasPurchaseItems => widget.hasPurchaseItems;
  Future<void> Function() get onFinalize => widget.onFinalize;
  _PaymentSelection? get paymentSelection => widget.paymentSelection;
  String? get returnSettleMode => widget.returnSettleMode;
  bool _isFinalizing = false;
  bool _finalizeAttempted = false;
  bool _finalizeSucceeded = false;
  String? _finalizeError;

  // True when the finalize failure is a receipt-printer problem. The payment is
  // saved before the print step, so on a printer error the sale is already
  // complete — we show a friendly message and a "finish without printing"
  // option instead of leaving the cashier stuck on a retry-only screen.
  bool get _isPrinterError {
    final e = _finalizeError;
    if (e == null) return false;
    return e.contains('printer_disabled') ||
        e.contains('RECEIPT_PRINTER') ||
        e.contains('พิมพ์ใบเสร็จไม่สำเร็จ') ||
        e.contains('พิมพ์ใบคืนสินค้าไม่สำเร็จ');
  }

  // User-facing error text: printer failures get a plain message instead of the
  // raw 503/JSON exception.
  String? get _finalizeErrorMessage {
    if (_finalizeError == null) return null;
    if (_isPrinterError) return 'เชื่อมต่อเครื่องปริ้นไม่สำเร็จ';
    return _finalizeError;
  }

  @override
  void initState() {
    super.initState();
    // 1) Tell the customer display (จอ 2) that the receipt dialog is now open
    //    so it can render the matching overlay (customer_screen handles
    //    `activeDialog == 'receipt'`).
    PosMirrorService.current?.notifyDialog('receipt');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleFinalize(closeOnSuccess: false);
    });
  }

  Future<void> _handleFinalize({bool closeOnSuccess = true}) async {
    if (_isFinalizing) return;
    if (_finalizeSucceeded) {
      if (closeOnSuccess && mounted) {
        Navigator.of(context).pop(true);
      }
      return;
    }
    setState(() {
      _isFinalizing = true;
      _finalizeAttempted = true;
      _finalizeError = null;
    });
    try {
      await onFinalize();
      if (!mounted) return;
      setState(() {
        _finalizeSucceeded = true;
      });
      if (closeOnSuccess) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _finalizeError = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('ปิดการขายไม่สำเร็จ: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isFinalizing = false);
      }
    }
  }

  @override
  void dispose() {
    // Clear customer-side overlay when the cashier closes the dialog.
    PosMirrorService.current?.notifyDialog(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bill = Provider.of<BillProvider>(context, listen: false);

    final subtotal = bill.subtotal;
    final discount = bill.discount;
    final amountAfterDiscount = bill.amountAfterDiscount;
    final taxRate = bill.taxRate;
    final tax = bill.tax;
    final total = bill.total;
    final returnCredit = bill.returnCreditAmount;
    final netTotal = settlementTotal;

    // Company info for the receipt header. CompanyProvider is loaded at app
    // startup (office_screen); if it hasn't loaded yet, fields fall back to
    // empty strings so the receipt still renders.
    final company =
        Provider.of<CompanyProvider>(context, listen: false).company ??
        const <String, dynamic>{};
    final companyNameTh =
        company['companyNameTh']?.toString().isNotEmpty == true
        ? company['companyNameTh'].toString()
        : (company['companyName']?.toString() ?? '');
    final companyAddressTh =
        company['companyAddressTh']?.toString().isNotEmpty == true
        ? company['companyAddressTh'].toString()
        : (company['companyAddress']?.toString() ?? '');
    final taxId = company['taxId']?.toString() ?? '';
    final phone = company['phone']?.toString() ?? '';
    final website = company['website']?.toString() ?? '';
    final receiptFooter = company['receiptFooter']?.toString() ?? '';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── HEADER: company info (per receiptpos.png) ───────────────
              if (companyNameTh.isNotEmpty) ...[
                Text(
                  companyNameTh,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
              ],
              if (companyAddressTh.isNotEmpty) ...[
                Text(
                  companyAddressTh,
                  style: const TextStyle(fontSize: 11),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
              ],
              if (taxId.isNotEmpty) ...[
                Text(
                  'เลขผู้เสียภาษี $taxId',
                  style: const TextStyle(fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
              if (phone.isNotEmpty) ...[
                Text(
                  'โทร. $phone',
                  style: const TextStyle(fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
              if (website.isNotEmpty) ...[
                Text(
                  'เว็บไซต์ $website',
                  style: const TextStyle(fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
              const Divider(height: 20, thickness: 1),
              // ── BODY heading ────────────────────────────────────────────
              const Text(
                'ใบกำกับภาษีอย่างย่อ/ใบเสร็จรับเงิน',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              if ((bill.billId ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  bill.billId ?? '',
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final auth = Provider.of<AuthProvider>(
                    context,
                    listen: false,
                  );
                  final userName = auth.name ?? 'Admin';
                  final now = DateTime.now();
                  final dateTimeStr =
                      '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'พนักงานขาย: $userName',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'วันที่: $dateTimeStr',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              if (paymentSelection != null) ...[
                _buildReceiptRow('วิธีชำระเงิน', paymentSelection!.label),
                const SizedBox(height: 4),
              ],
              if (paymentSelection?.kind == _PaymentKind.creditTerm &&
                  paymentSelection?.deliveryDate != null) ...[
                _buildReceiptRow(
                  'วันที่รับของ',
                  _formatDateValue(paymentSelection!.deliveryDate!),
                ),
                const SizedBox(height: 4),
                for (
                  var i = 0;
                  i < paymentSelection!.installments.length;
                  i++
                ) ...[
                  _buildReceiptRow(
                    'งวดที่ ${i + 1}',
                    '${_formatDateValue(paymentSelection!.installments[i].dueDate)} • ฿${paymentSelection!.installments[i].amount.toStringAsFixed(2)}',
                  ),
                  const SizedBox(height: 4),
                ],
              ],
              if (returnSettleMode != null && returnSettleMode!.isNotEmpty) ...[
                _buildReceiptRow('ปิดรายการคืน', switch (returnSettleMode) {
                  'cash_refund' => 'คืนเงินสด',
                  'customer_credit' => 'เก็บเป็นเครดิตลูกค้า',
                  _ => 'แลกเปลี่ยนสินค้า',
                }),
                const SizedBox(height: 4),
              ],
              if (bill.items.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: Text(
                        'สินค้า',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        'จำนวน',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'ราคา',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: bill.items.map<Widget>((raw) {
                    double toDouble(dynamic v) {
                      if (v == null) return 0.0;
                      if (v is num) return v.toDouble();
                      return double.tryParse(v.toString()) ?? 0.0;
                    }

                    final qtyRaw = toDouble(
                      raw['qty'] ?? raw['quantity'] ?? raw['amount'],
                    );
                    final qty = qtyRaw <= 0 ? 1 : qtyRaw.toInt();
                    final price = toDouble(
                      raw['unitPrice'] ?? raw['price'] ?? raw['unit_price'],
                    );
                    final total = toDouble(
                      raw['amount'] ?? raw['total'] ?? price * qty,
                    );
                    final resolvedPrice = price > 0
                        ? price
                        : (qty > 0 ? total / qty : total);
                    final name =
                        raw['nameTh']?.toString() ??
                        raw['name']?.toString() ??
                        raw['description']?.toString() ??
                        'สินค้า';
                    final code =
                        raw['partCode']?.toString() ??
                        raw['code']?.toString() ??
                        '-';
                    final lineTotal = (resolvedPrice * qty).toStringAsFixed(2);

                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 6,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    code,
                                    style: TextStyle(
                                      color: context.colorMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                '$qty',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '฿$lineTotal',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
              _buildReceiptRow('ก่อนลด', '฿${subtotal.toStringAsFixed(2)}'),
              const SizedBox(height: 4),
              _buildReceiptRow('ส่วนลด', '- ฿${discount.toStringAsFixed(2)}'),
              const SizedBox(height: 4),
              _buildReceiptRow(
                'หลังหักส่วนลด',
                '฿${amountAfterDiscount.toStringAsFixed(2)}',
              ),
              const SizedBox(height: 4),
              _buildReceiptRow(
                'ภาษี (${(taxRate * 100).toStringAsFixed(0)}%)',
                '฿${tax.toStringAsFixed(2)}',
              ),
              if (returnCredit > 0) ...[
                const SizedBox(height: 4),
                _buildReceiptRow(
                  'ยอดคืนสินค้า',
                  '- ฿${returnCredit.toStringAsFixed(2)}',
                ),
              ],
              const Divider(height: 16, thickness: 1),
              _buildReceiptRow(
                'รวมสุทธิ',
                '฿${total.toStringAsFixed(2)}',
                isEmphasis: true,
              ),
              if (returnCredit > 0) ...[
                const SizedBox(height: 4),
                _buildReceiptRow(
                  'ยอดชำระสุทธิหลังคืน',
                  '${netTotal < 0 ? '-฿' : '฿'}${netTotal.abs().toStringAsFixed(2)}',
                  isEmphasis: true,
                ),
              ],
              const SizedBox(height: 8),
              // VAT INCLUDED notice — matches receiptpos.png layout
              const Text(
                'VAT INCLUDED',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 12),
              // Editable receipt footer from company_setting.receipt_footer
              // (set in Backoffice → Company → "ข้อความท้ายใบเสร็จ").
              if (receiptFooter.isNotEmpty) ...[
                const Divider(height: 16, thickness: 1),
                Text(
                  receiptFooter,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 4),
              ],
              if (_finalizeError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _finalizeErrorMessage!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _isFinalizing || _finalizeAttempted
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('ย้อนกลับ'),
              ),
              const SizedBox(height: 8),
              if (_finalizeSucceeded)
                ElevatedButton(
                  onPressed: _isFinalizing
                      ? null
                      : () => Navigator.of(context).pop(true),
                  child: const Text('กลับสู่หน้าหลัก'),
                )
              else if (_isPrinterError && !_isFinalizing)
                // Printer failed but the payment is already saved. Let the
                // cashier retry the print or finish the sale without a receipt
                // so they aren't stuck on the order.
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            _handleFinalize(closeOnSuccess: false),
                        child: const Text('ลองใหม่อีกครั้ง'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('ทำต่อโดยไม่ปริ้น'),
                      ),
                    ),
                  ],
                )
              else
                ElevatedButton(
                  onPressed: _isFinalizing
                      ? null
                      : () => _handleFinalize(closeOnSuccess: false),
                  child: _isFinalizing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('ลองใหม่อีกครั้ง'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptRow(
    String label,
    String value, {
    bool isEmphasis = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isEmphasis ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isEmphasis ? FontWeight.bold : FontWeight.normal,
            color: isEmphasis ? const Color(0xFF1F6F5D) : null,
          ),
        ),
      ],
    );
  }
}

enum _ReturnSettlement { cash, credit }

class _ReturnSettlementDialog extends StatelessWidget {
  const _ReturnSettlementDialog({
    required this.refundAmount,
    required this.hasMember,
  });

  final double refundAmount;
  final bool hasMember;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'สรุปการคืนเงิน',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'ลูกค้าต้องรับคืน ฿${refundAmount.toStringAsFixed(2)}',
                style: TextStyle(
                  color: context.colorDanger,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).pop(_ReturnSettlement.cash),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('คืนเงินสด'),
                ),
              ),
              const SizedBox(height: 8),
              Tooltip(
                message: hasMember ? '' : 'กรุณาผูกสมาชิกก่อนเพื่อเก็บเครดิต',
                child: OutlinedButton(
                  onPressed: hasMember
                      ? () =>
                            Navigator.of(context).pop(_ReturnSettlement.credit)
                      : null,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('เก็บเป็นเครดิตลูกค้า'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('ยกเลิก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreditTermInstallmentDraft {
  _CreditTermInstallmentDraft({required this.dueDate, required double amount})
    : amountController = TextEditingController(text: amount.toStringAsFixed(2));

  DateTime dueDate;
  final TextEditingController amountController;

  double get amount =>
      double.tryParse(amountController.text.replaceAll(',', '').trim()) ?? 0.0;

  void dispose() {
    amountController.dispose();
  }
}

class _PaymentMethodDialog extends StatefulWidget {
  const _PaymentMethodDialog({required this.total});

  final double total;

  @override
  State<_PaymentMethodDialog> createState() => _PaymentMethodDialogState();
}

class _PaymentMethodDialogState extends State<_PaymentMethodDialog> {
  late _PaymentKind _selectedKind;
  late DateTime _deliveryDate;
  late List<_CreditTermInstallmentDraft> _installments;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _selectedKind = _PaymentKind.cash;
    _deliveryDate = DateTime(today.year, today.month, today.day);
    _installments = <_CreditTermInstallmentDraft>[
      _CreditTermInstallmentDraft(
        dueDate: _deliveryDate.add(const Duration(days: 1)),
        amount: widget.total,
      ),
    ];
    for (final installment in _installments) {
      installment.amountController.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final installment in _installments) {
      installment.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  double get _scheduledTotal => _installments.fold<double>(
    0.0,
    (sum, installment) => sum + installment.amount,
  );

  double get _difference => widget.total - _scheduledTotal;

  bool get _isCreditTermValid {
    if (_installments.isEmpty) {
      return false;
    }
    final allPositive = _installments.every(
      (installment) => installment.amount > 0,
    );
    return allPositive && _difference.abs() < 0.01;
  }

  DateTime _minimumDueDateForIndex(int index) {
    final anchorDate = index == 0
        ? _deliveryDate
        : _installments[index - 1].dueDate;
    return DateTime(
      anchorDate.year,
      anchorDate.month,
      anchorDate.day,
    ).add(const Duration(days: 1));
  }

  void _normalizeInstallmentDates({int startIndex = 0}) {
    for (var i = startIndex; i < _installments.length; i++) {
      final minimumDate = _minimumDueDateForIndex(i);
      if (_installments[i].dueDate.isBefore(minimumDate)) {
        _installments[i].dueDate = minimumDate;
      }
    }
  }

  void _updateDeliveryDate(DateTime date) {
    setState(() {
      _deliveryDate = DateTime(date.year, date.month, date.day);
      _normalizeInstallmentDates(startIndex: 0);
    });
  }

  void _updateInstallmentDueDate(int index, DateTime date) {
    setState(() {
      final minimumDate = _minimumDueDateForIndex(index);
      final normalizedDate = DateTime(date.year, date.month, date.day);
      _installments[index].dueDate = normalizedDate.isBefore(minimumDate)
          ? minimumDate
          : normalizedDate;
      _normalizeInstallmentDates(startIndex: index + 1);
    });
  }

  Future<void> _pickDate({
    required DateTime initialDate,
    DateTime? firstDate,
    required ValueChanged<DateTime> onSelected,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate ?? DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return;
    }
    onSelected(DateTime(picked.year, picked.month, picked.day));
  }

  void _addInstallment() {
    final last = _installments.isNotEmpty ? _installments.last : null;
    final nextDueDate = _minimumDueDateForIndex(_installments.length);
    double nextAmount = 0.0;
    if (last != null && last.amount > 0) {
      final half = double.parse((last.amount / 2).toStringAsFixed(2));
      final remainder = double.parse((last.amount - half).toStringAsFixed(2));
      last.amountController.text = half.toStringAsFixed(2);
      nextAmount = remainder;
    }

    final installment = _CreditTermInstallmentDraft(
      dueDate: nextDueDate,
      amount: nextAmount,
    );
    installment.amountController.addListener(_refresh);
    setState(() {
      _installments.add(installment);
    });
  }

  void _removeInstallment(int index) {
    if (_installments.length <= 1) {
      return;
    }
    final removed = _installments.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  void _applyShortcut(int index, int days) {
    setState(() {
      _installments[index].dueDate = _installments[index].dueDate.add(
        Duration(days: days),
      );
      _normalizeInstallmentDates(startIndex: index + 1);
    });
  }

  void _confirm() {
    switch (_selectedKind) {
      case _PaymentKind.cash:
        Navigator.of(context).pop(_PaymentSelection.cash());
        return;
      case _PaymentKind.transfer:
        Navigator.of(context).pop(_PaymentSelection.transfer());
        return;
      case _PaymentKind.creditTerm:
        if (!_isCreditTermValid) {
          return;
        }
        Navigator.of(context).pop(
          _PaymentSelection.creditTerm(
            deliveryDate: _deliveryDate,
            installments: _installments
                .map(
                  (installment) => _CreditTermInstallment(
                    dueDate: installment.dueDate,
                    amount: installment.amount,
                  ),
                )
                .toList(),
          ),
        );
        return;
      case _PaymentKind.exchange:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final differenceColor = _difference.abs() < 0.01
        ? context.colorPrimary
        : (_difference > 0 ? context.colorDanger : context.colorAccent);
    final maxDialogHeight = MediaQuery.of(context).size.height * 0.85;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxDialogHeight),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'วิธีชำระเงิน',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _selectedKind == _PaymentKind.cash
                              ? context.colorPrimary.withValues(alpha: 0.08)
                              : null,
                        ),
                        onPressed: () {
                          setState(() => _selectedKind = _PaymentKind.cash);
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('เงินสด'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor:
                              _selectedKind == _PaymentKind.transfer
                              ? context.colorPrimary.withValues(alpha: 0.08)
                              : null,
                        ),
                        onPressed: () {
                          setState(() => _selectedKind = _PaymentKind.transfer);
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('โอน'),
                        ),
                      ),
                    ),
                    // "เงินเซ็น" (credit term) — hidden for branches that don't
                    // use the credit system (see kEnableCreditTerm).
                    if (kEnableCreditTerm) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor:
                                _selectedKind == _PaymentKind.creditTerm
                                ? context.colorPrimary.withValues(alpha: 0.08)
                                : null,
                          ),
                          onPressed: () {
                            setState(
                              () => _selectedKind = _PaymentKind.creditTerm,
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('เงินเซ็น'),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (_selectedKind == _PaymentKind.creditTerm) ...[
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => _pickDate(
                      initialDate: _deliveryDate,
                      onSelected: _updateDeliveryDate,
                    ),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'วันที่รับของ',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: Text(_formatDateValue(_deliveryDate)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(_installments.length, (index) {
                    final installment = _installments[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == _installments.length - 1 ? 0 : 12,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: context.colorBorder),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'งวดที่ ${index + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                if (_installments.length > 1)
                                  IconButton(
                                    onPressed: () => _removeInstallment(index),
                                    icon: const Icon(Icons.close),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () => _pickDate(
                                initialDate: installment.dueDate,
                                firstDate: _minimumDueDateForIndex(index),
                                onSelected: (date) =>
                                    _updateInstallmentDueDate(index, date),
                              ),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'วันนัดจ่ายเงิน',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                child: Text(
                                  _formatDateValue(installment.dueDate),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: installment.amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'จำนวนเงินงวดนี้',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final days in const [10, 15, 30])
                                  OutlinedButton(
                                    onPressed: () =>
                                        _applyShortcut(index, days),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    child: Text('$days วัน'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _addInstallment,
                        icon: const Icon(Icons.add),
                        label: const Text('เพิ่มงวด'),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'ยอดบิล ฿${widget.total.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            _difference.abs() < 0.01
                                ? 'ยอดงวดครบแล้ว'
                                : (_difference > 0
                                      ? 'ขาดอีก ฿${_difference.toStringAsFixed(2)}'
                                      : 'เกิน ฿${(-_difference).toStringAsFixed(2)}'),
                            style: TextStyle(
                              color: differenceColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('ยกเลิก'),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed:
                          _selectedKind == _PaymentKind.creditTerm &&
                              !_isCreditTermValid
                          ? null
                          : _confirm,
                      child: const Text('ยืนยัน'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Inserted: _CashConfirmDialog ---
class _CashConfirmDialog extends StatefulWidget {
  const _CashConfirmDialog({required this.total});

  final double total;

  @override
  State<_CashConfirmDialog> createState() => _CashConfirmDialogState();
}

class _CashConfirmDialogState extends State<_CashConfirmDialog> {
  final TextEditingController _controller = TextEditingController();
  double _paidAmount = 0.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final cleaned = value.replaceAll(',', '').trim();
    final parsed = double.tryParse(cleaned);
    setState(() {
      _paidAmount = parsed ?? 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.total;
    final change = _paidAmount - total;
    final bool isEnough = _paidAmount >= total && total > 0;

    // กำหนด label / สี / ค่า สำหรับแถว "เงินทอน / ขาดอีก"
    String changeLabel;
    Color changeColor;
    String changeValue;

    if (_paidAmount <= 0) {
      changeLabel = 'เงินทอน';
      changeColor = Colors.grey;
      changeValue = '-';
    } else if (!isEnough) {
      changeLabel = 'ขาดอีก';
      changeColor = Colors.red;
      changeValue = '฿${(-change).toStringAsFixed(2)}';
    } else {
      changeLabel = 'เงินทอน';
      changeColor = Colors.green;
      changeValue = '฿${change.toStringAsFixed(2)}';
    }

    return AlertDialog(
      title: const Text('ลูกค้าชำระเงินสด'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCashRow(
              label: 'ยอดที่ต้องชำระ',
              rightWidget: Text(
                '฿${total.toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildCashRow(
              label: 'จำนวนที่ลูกค้าชำระ',
              rightWidget: TextField(
                controller: _controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  hintText: 'เช่น 1000',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: _onChanged,
              ),
            ),
            const SizedBox(height: 12),
            _buildCashRow(
              label: changeLabel,
              labelColor: changeColor,
              rightWidget: Text(
                changeValue,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: changeColor,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton(
          onPressed: isEnough
              ? () => Navigator.of(context).pop(
                  _CashPaymentResult(
                    receivedAmount: _paidAmount,
                    changeAmount: change,
                  ),
                )
              : null,
          child: const Text('ยืนยัน'),
        ),
      ],
    );
  }

  Widget _buildCashRow({
    required String label,
    required Widget rightWidget,
    Color? labelColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: labelColor ?? Colors.black,
            ),
          ),
        ),
        const SizedBox(width: 32),
        SizedBox(width: 120, child: rightWidget),
      ],
    );
  }
}

class _CashPaymentResult {
  const _CashPaymentResult({
    required this.receivedAmount,
    required this.changeAmount,
  });

  final double receivedAmount;
  final double changeAmount;
}
