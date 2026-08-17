import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/bill_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/pos_mirror_service.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class CustomerScreen extends StatefulWidget {
  const CustomerScreen({super.key});

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  // BroadcastChannel — works only within same browsing context (tabs spawned by the same script).
  html.BroadcastChannel? _bc;
  // 'storage' event listener — fires whenever ANOTHER same-origin window writes localStorage.
  // This is the channel that actually reaches the popup opened by window.open().
  html.EventListener? _storageHandler;
  // Polling fallback — in rare cases the 'storage' event can be missed (browser quirks),
  // so we also poll the same key every 1.5 s and re-apply if its sequence changed.
  Timer? _pollTimer;
  String? _lastSeenSeq;
  WebSocketChannel? _customerChannel;
  Timer? _reconnectTimer;
  String _connectionStatus = 'connecting';
  String? _connectionError;
  int _reconnectAttempts = 0;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _bc = html.BroadcastChannel('pos_mirror');
      _bc!.addEventListener('message', _onMirrorMessage);

      _storageHandler = (html.Event event) {
        final se = event as html.StorageEvent;
        if (se.key == 'pos_mirror_state' || se.key == 'pos_mirror_seq') {
          _applyFromLocalStorage();
        }
      };
      html.window.addEventListener('storage', _storageHandler);

      // Pull whatever state exists at startup (cashier may have written it before
      // this popup was opened).
      _applyFromLocalStorage();
      _connectCustomerDisplayWebSocket();

      _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
        final seq = html.window.localStorage['pos_mirror_seq'];
        if (seq != null && seq != _lastSeenSeq) {
          _applyFromLocalStorage();
        }
      });

      // ขอ fullscreen หลังหน้าถูก render เสร็จ (Web only) เพื่อให้แสดงเต็มจอ 2
      // user gesture จากปุ่มในหน้าหลักจะส่งต่อมาให้ popup นี้ใช้สิทธิ์ขอ fullscreen ได้
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestFullscreen());
    }
  }

  void _requestFullscreen() {
    try {
      html.document.documentElement?.requestFullscreen();
    } catch (_) {
      // permission denied / not in user gesture context — แสดง windowed mode ปกติ
    }
  }

  void _onMirrorMessage(html.Event event) {
    final me = event as html.MessageEvent;
    try {
      final data = jsonDecode(me.data as String) as Map<String, dynamic>;
      _applyMirrorState(data);
    } catch (_) {}
  }

  void _connectCustomerDisplayWebSocket() {
    _reconnectTimer?.cancel();
    _customerChannel?.sink.close();
    _customerChannel = null;
    if (!mounted) return;
    setState(() {
      _connectionStatus = 'connecting';
      _connectionError = null;
    });

    try {
      final uri = Uri.parse(buildCustomerDisplayWsUrl());
      final channel = WebSocketChannel.connect(uri);
      _customerChannel = channel;
      channel.ready.then(
        (_) {
          if (mounted) {
            setState(() {
              _connectionStatus = 'connected';
              _connectionError = null;
            });
          }
        },
        onError: (error) {
          _connectionError = error.toString();
          _scheduleReconnect();
        },
      );
      channel.stream.listen(
        (message) {
          _reconnectAttempts = 0;
          if (mounted) {
            setState(() {
              _connectionStatus = 'connected';
              _connectionError = null;
            });
          }
          try {
            final data = jsonDecode(message.toString()) as Map<String, dynamic>;
            _applyMirrorState(data);
          } catch (_) {}
        },
        onError: (error) {
          _connectionError = error.toString();
          _scheduleReconnect();
        },
        onDone: _scheduleReconnect,
      );
    } catch (e) {
      _connectionError = e.toString();
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!mounted) return;
    _customerChannel = null;
    setState(() {
      _connectionStatus = 'reconnecting';
    });
    final seconds = _reconnectAttempts < 5 ? 2 + _reconnectAttempts : 8;
    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) {
        _connectCustomerDisplayWebSocket();
      }
    });
  }

  void _applyMirrorState(Map<String, dynamic> data) {
    if (!mounted) return;
    context.read<BillProvider>().updateFromMirrorState(data);
  }

  /// Read the latest pos_mirror_state from localStorage and apply it to the
  /// BillProvider. Used by the 'storage' event listener, the periodic poller,
  /// and at startup.
  void _applyFromLocalStorage() {
    final raw = html.window.localStorage['pos_mirror_state'];
    if (raw == null || raw.isEmpty) return;
    _lastSeenSeq = html.window.localStorage['pos_mirror_seq'];
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _applyMirrorState(data);
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    _customerChannel?.sink.close();
    _customerChannel = null;
    if (_storageHandler != null) {
      html.window.removeEventListener('storage', _storageHandler);
      _storageHandler = null;
    }
    _bc?.close();
    _bc = null;
    super.dispose();
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  List<_CustomerLineItem> _mapItems(
    List<Map<String, dynamic>> rawItems, {
    bool isReturn = false,
  }) {
    return rawItems.map((item) {
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

      return _CustomerLineItem(
        name:
            item['nameTh']?.toString() ??
            item['partName']?.toString() ??
            item['part_name']?.toString() ??
            item['name']?.toString() ??
            item['description']?.toString() ??
            'สินค้า',
        code: partCode ?? '-',
        qty: qty,
        price: resolvedPrice,
        isReturn: isReturn,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bill = context.watch<BillProvider>();
    final items = [
      ..._mapItems(bill.items),
      ..._mapItems(bill.returnLines, isReturn: true),
    ];
    final subtotal = bill.subtotal;
    final discount = bill.discount;
    final amountAfterDiscount = bill.amountAfterDiscount;
    final taxRate = bill.taxRate;
    final tax = bill.tax;
    final total = bill.total;
    final returnCredit = bill.returnCreditAmount;
    final netSettlement = bill.netSettlementAmount;
    final hasReturnItems = bill.hasReturnItems;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'ยินดีต้อนรับ',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'กรุณาตรวจสอบรายการสินค้า และยอดชำระ',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppSizes.radius),
                        border: Border.all(color: AppColors.border),
                        boxShadow: AppShadows.soft,
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header แสดงจำนวนสินค้าในตะกร้า
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'รายการสินค้า',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${items.length} รายการ',
                                style: const TextStyle(color: AppColors.muted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // ส่วนแสดงรายการสินค้า + สรุปยอด (scroll ได้)
                          Expanded(
                            child: items.isEmpty
                                ? const Center(
                                    child: Text(
                                      'ยินดีให้บริการครับ/ค่ะ\nเมื่อพนักงานเพิ่มรายการสินค้า รายการจะปรากฏที่นี่',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: AppColors.muted),
                                    ),
                                  )
                                : SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // รายการสินค้าแต่ละบรรทัด (เหมือน CartSummarySection)
                                        ...items.map((it) {
                                          final lineAmount = it.price * it.qty;
                                          final lineTotal = lineAmount
                                              .abs()
                                              .toStringAsFixed(2);
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  flex: 5,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        it.isReturn
                                                            ? 'คืน ${it.name}'
                                                            : it.name,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: it.isReturn
                                                              ? Colors
                                                                    .red
                                                                    .shade700
                                                              : null,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        it.code,
                                                        style: const TextStyle(
                                                          color:
                                                              AppColors.muted,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                // The customer is looking at
                                                // this screen to check the
                                                // arithmetic, so show it:
                                                // quantity times price each.
                                                Expanded(
                                                  flex: 3,
                                                  child: Text(
                                                    '${it.isReturn ? '-' : ''}'
                                                    '${it.qty} × ฿'
                                                    '${it.price.toStringAsFixed(2)}',
                                                    textAlign: TextAlign.right,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: it.isReturn
                                                          ? Colors.red.shade700
                                                          : null,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  flex: 3,
                                                  child: Text(
                                                    '${it.isReturn ? '- ' : ''}฿$lineTotal',
                                                    textAlign: TextAlign.right,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: it.isReturn
                                                          ? Colors.red.shade700
                                                          : null,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                        const SizedBox(height: 12),
                                        Divider(
                                          height: 1,
                                          color: AppColors.border.withValues(
                                            alpha: 0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        // สรุปยอดเหมือนเดิม
                                        _buildSummaryRow(
                                          'ก่อนลด',
                                          '฿${subtotal.toStringAsFixed(2)}',
                                        ),
                                        const SizedBox(height: 8),
                                        _buildSummaryRow(
                                          'ส่วนลด',
                                          '- ฿${discount.toStringAsFixed(2)}',
                                        ),
                                        const SizedBox(height: 8),
                                        _buildSummaryRow(
                                          'หลังหักส่วนลด',
                                          '฿${amountAfterDiscount.toStringAsFixed(2)}',
                                        ),
                                        const SizedBox(height: 8),
                                        _buildSummaryRow(
                                          'ภาษี (${(taxRate * 100).toStringAsFixed(0)}%)',
                                          '฿${tax.toStringAsFixed(2)}',
                                        ),
                                        if (hasReturnItems) ...[
                                          const SizedBox(height: 8),
                                          _buildSummaryRow(
                                            'ยอดคืนสินค้า',
                                            '- ฿${returnCredit.toStringAsFixed(2)}',
                                          ),
                                        ],
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                            horizontal: 14,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.05,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              AppSizes.radius,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text(
                                                'รวมสุทธิ',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              Text(
                                                '฿${total.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  color: AppColors.primary,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (hasReturnItems) ...[
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                              horizontal: 14,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  (netSettlement < 0
                                                          ? Colors.red
                                                          : AppColors.primary)
                                                      .withValues(alpha: 0.08),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppSizes.radius,
                                                  ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  netSettlement < 0
                                                      ? 'ยอดคืนเงินสุทธิ'
                                                      : 'ยอดชำระสุทธิหลังคืน',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                Text(
                                                  '${netSettlement < 0 ? '-฿' : '฿'}${netSettlement.abs().toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    color: netSettlement < 0
                                                        ? Colors.red.shade700
                                                        : AppColors.primary,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 18,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'ยอดและรายการนี้เป็นแบบอ่านอย่างเดียว\nการเปลี่ยนแปลงทำได้จากหน้าจอพนักงานเท่านั้น',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (bill.isAwaitingCashPayment)
            _CashPaymentOverlay(amount: bill.awaitingCashAmount),
          if (bill.isAwaitingQrPayment) _QrScanOverlay(amount: netSettlement),
          // Mirror cashier's _ReceiptDialog so the customer can verify totals.
          // Cashier sets activeDialog='receipt' just before showDialog and
          // clears it on dispose; we render an equivalent summary card here.
          if (bill.activeDialog == 'receipt')
            _ReceiptConfirmationOverlay(
              subtotal: bill.subtotal,
              discount: bill.discount,
              tax: bill.tax,
              total: bill.total,
              returnCredit: bill.returnCreditAmount,
              netSettlement: bill.netSettlementAmount,
            ),
          if (bill.showThankYouOverlay) const _ThankYouOverlay(),
          _ConnectionBadge(status: _connectionStatus, error: _connectionError),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
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
            color: isEmphasis ? AppColors.primary : null,
          ),
        ),
      ],
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.status, this.error});

  final String status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final connected = status == 'connected';
    final color = connected ? Colors.green.shade700 : Colors.orange.shade800;
    final label = connected ? 'เชื่อมต่อแล้ว' : 'กำลังเชื่อมต่อ';

    return Positioned(
      right: 12,
      top: 12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.45)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                connected ? Icons.wifi : Icons.wifi_off,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!connected && error != null && error!.isNotEmpty) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: error!,
                  child: Icon(Icons.info_outline, size: 14, color: color),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerLineItem {
  _CustomerLineItem({
    required this.name,
    required this.code,
    required this.qty,
    required this.price,
    this.isReturn = false,
  });

  final String name;
  final String code;
  final int qty;
  final double price;
  final bool isReturn;
}

class _CashPaymentOverlay extends StatelessWidget {
  const _CashPaymentOverlay({required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              elevation: 12,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.payments, size: 56, color: AppColors.primary),
                    const SizedBox(height: 12),
                    const Text(
                      'กรุณาชำระเงิน',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'โปรดชำระเงินสดตามยอดด้านล่าง',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppColors.muted),
                    ),
                    const Divider(height: 32, thickness: 1),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'ยอดชำระ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '฿${amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'โปรดแจ้งพนักงานเมื่อชำระเงินเรียบร้อย',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThankYouOverlay extends StatelessWidget {
  const _ThankYouOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSizes.radius),
              boxShadow: AppShadows.soft,
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ขอบคุณที่ใช้บริการของเรา',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'ขอให้มีวันที่ดี แล้วพบกันใหม่ในครั้งถัดไป',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QrScanOverlay extends StatefulWidget {
  const _QrScanOverlay({required this.amount});

  final double amount;

  @override
  State<_QrScanOverlay> createState() => _QrScanOverlayState();
}

class _QrScanOverlayState extends State<_QrScanOverlay> {
  // รูป QR ที่ร้านอัพโหลดไว้ (backoffice → ตั้งค่าการชำระเงิน) — โหลดครั้งเดียว
  // ตอน overlay ขึ้น ถ้ายังไม่ได้อัพโหลด/โหลดไม่สำเร็จ fallback เป็นรูปในแอป
  Uint8List? _qrBytes;

  @override
  void initState() {
    super.initState();
    _loadUploadedQr();
  }

  Future<void> _loadUploadedQr() async {
    try {
      final token = context.read<AuthProvider>().token;
      if (token == null || token.isEmpty) return;
      final bytes = await ApiService.getQrImage(token: token);
      if (mounted && bytes.isNotEmpty) {
        setState(() => _qrBytes = bytes);
      }
    } catch (_) {
      // ไม่มีรูปที่อัพโหลด — ใช้ fallback ด้านล่าง
    }
  }

  double get amount => widget.amount;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.4),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSizes.radius),
              boxShadow: AppShadows.soft,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'สแกนเพื่อชำระเงิน',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'กรุณาสแกน QR Code เพื่อชำระเงินตามยอด ฿${amount.toStringAsFixed(2)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 260,
                  width: 260,
                  child: _qrBytes != null
                      ? Image.memory(_qrBytes!, fit: BoxFit.contain)
                      : Image.asset(
                          'images/shop_qr.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Text(
                                'กรุณาติดต่อพนักงานเพื่อขอ QR Code ชำระเงิน',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'โปรดแจ้งพนักงานเมื่อสแกนและชำระเงินเรียบร้อย',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mirror of the cashier's `_ReceiptDialog` for the customer-facing screen.
///
/// Shown when `BillProvider.activeDialog == 'receipt'` (set by the cashier's
/// dialog open/close lifecycle in cart_summary_section.dart). The card is
/// read-only — the customer reviews the totals while the cashier prints the
/// physical receipt on the 80mm thermal printer.
class _ReceiptConfirmationOverlay extends StatelessWidget {
  const _ReceiptConfirmationOverlay({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.returnCredit,
    required this.netSettlement,
  });

  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double returnCredit;
  final double netSettlement;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              elevation: 12,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.receipt_long,
                      size: 56,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'กรุณาตรวจสอบยอดเงิน',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'พนักงานกำลังพิมพ์ใบเสร็จ',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppColors.muted),
                    ),
                    const Divider(height: 32, thickness: 1),
                    _line('ก่อนลด', subtotal),
                    const SizedBox(height: 6),
                    _line('ส่วนลด', -discount),
                    const SizedBox(height: 6),
                    _line('ภาษี', tax),
                    if (returnCredit > 0) ...[
                      const SizedBox(height: 6),
                      _line('ยอดคืนสินค้า', -returnCredit),
                    ],
                    const Divider(height: 24, thickness: 1),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'รวมสุทธิ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '฿${total.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    if (returnCredit > 0) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            netSettlement < 0
                                ? 'ยอดคืนเงินสุทธิ'
                                : 'ยอดชำระสุทธิหลังคืน',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${netSettlement < 0 ? '-฿' : '฿'}${netSettlement.abs().toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: netSettlement < 0
                                  ? Colors.red.shade700
                                  : AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(String label, double value) {
    final isNeg = value < 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        Text(
          '${isNeg ? '- ' : ''}฿${value.abs().toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 16),
        ),
      ],
    );
  }
}
