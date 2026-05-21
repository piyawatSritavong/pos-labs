import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:frontend/providers/bill_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class PosMirrorService {
  // Singleton-like current active broadcaster — lets any widget call notifyDialog / notifyBarcode.
  static PosMirrorService? _current;
  static PosMirrorService? get current => _current;

  WebSocketChannel? _channel;
  BillProvider? _billProvider;
  Timer? _debounceTimer;
  Timer? _reconnectTimer;
  String? _wsUrl;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  bool _disposed = false;

  // Tracked UI state
  String? _activeDialog;
  String? _lastBarcode;
  Map<String, dynamic>? _dialogState;
  String? _lastAction;
  Timer? _lastActionTimer;

  void connect(String wsUrl, BillProvider billProvider) {
    _current = this;
    _wsUrl = wsUrl;
    _billProvider = billProvider;
    _disposed = false;
    _reconnectAttempts = 0;
    _openConnection();
  }

  void _openConnection() {
    if (_disposed || _wsUrl == null) return;
    try {
      final uri = Uri.parse(_wsUrl!);
      _channel = WebSocketChannel.connect(uri);
      _channel!.stream.listen(
        (_) {}, // broadcaster ignores incoming messages
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
      );
      _billProvider?.addListener(_onBillChanged);
      // Send current state immediately on connect
      _sendState();
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _billProvider?.removeListener(_onBillChanged);
    _channel = null;
    if (_reconnectAttempts >= _maxReconnectAttempts) return;
    _reconnectAttempts++;
    _reconnectTimer = Timer(const Duration(seconds: 3), _openConnection);
  }

  void _onBillChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), _sendState);
  }

  /// Call when Van Staff opens a dialog. Pass null when the dialog closes.
  /// Sends immediately (no debounce) so the Admin sees the change right away.
  void notifyDialog(String? name) {
    _activeDialog = name;
    if (name == null) _dialogState = null; // clear dialog state on close
    _debounceTimer?.cancel();
    _sendState();
  }

  /// Call from inside a dialog to broadcast its internal state.
  /// Sends immediately so Admin sees changes in real-time.
  void notifyDialogState(Map<String, dynamic>? state) {
    _dialogState = state;
    _debounceTimer?.cancel();
    _sendState();
  }

  /// Call when the barcode scanner fires with a new code.
  void notifyBarcode(String code) {
    _lastBarcode = code.isEmpty ? null : code;
    _sendState();
  }

  /// Call when Van Staff taps a cart action (pay, hold, clear, discount_N, qty_add, qty_remove).
  /// The action name is broadcast for 2 seconds then auto-clears.
  void notifyLastAction(String action) {
    _lastActionTimer?.cancel();
    _lastAction = action;
    _sendState();
    _lastActionTimer = Timer(const Duration(seconds: 2), () {
      _lastAction = null;
      _sendState();
    });
  }

  void _sendState() {
    // BUGFIX: previous version also bailed out when `_channel == null`, which
    // meant localStorage (the channel that actually reaches the customer popup
    // opened via window.open) was never written if the WebSocket happened to
    // be disconnected. Now we only require a BillProvider — every transport
    // below is best-effort and independent.
    if (_billProvider == null) return;
    final bill = _billProvider!;
    final state = {
      'type': 'pos_state',
      'billId': bill.billId,
      'items': bill.items
          .map(
            (item) => {
              'partCode': item['partCode'] ?? item['part_code'] ?? '',
              'partName': item['partName'] ?? item['part_name'] ?? '',
              'qty': item['qty'] ?? 0,
              'unitPrice': item['unitPrice'] ?? item['unit_price'] ?? 0,
              'lineTotal': item['lineTotal'] ?? item['line_total'] ?? 0,
            },
          )
          .toList(),
      'subtotal': bill.subtotal,
      'discount': bill.discount,
      'tax': bill.tax,
      'total': bill.total,
      'returnItems': bill.returnLines
          .map(
            (item) => {
              'partCode': item['partCode'] ?? item['part_code'] ?? '',
              'partName':
                  item['partName'] ??
                  item['nameTh'] ??
                  item['name'] ??
                  item['part_name'] ??
                  '',
              'qty': item['qty'] ?? 0,
              'unitPrice': item['unitPrice'] ?? item['price'] ?? 0,
              'lineTotal': item['lineTotal'] ?? item['amount'] ?? 0,
            },
          )
          .toList(),
      'returnCreditAmount': bill.returnCreditAmount,
      'netSettlementAmount': bill.netSettlementAmount,
      'hasReturnItems': bill.hasReturnItems,
      'member': bill.assignedMember == null
          ? null
          : {
              'code': bill.assignedMember!['code'],
              'name': bill.assignedMember!['name'],
            },
      'taxRate': (bill.taxRate * 100).roundToDouble(),
      'isAwaitingCash': bill.isAwaitingCashPayment,
      'cashAmount': bill.awaitingCashAmount,
      'isAwaitingQr': bill.isAwaitingQrPayment,
      'showThankYou': bill.showThankYouOverlay,
      'activeDialog': _activeDialog,
      'lastBarcode': _lastBarcode,
      'dialogState': _dialogState,
      'lastAction': _lastAction,
    };
    final encoded = jsonEncode(state);

    // 1) WebSocket — only when actually connected. If the WS is down (back-end
    // unreachable, reconnect throttled) we still update localStorage so the
    // customer popup keeps working.
    if (_channel != null) {
      try {
        _channel!.sink.add(encoded);
      } catch (_) {}
    }

    // 2) Cross-window mirroring for the customer display (จอ 2).
    //
    // BroadcastChannel ONLY works between same browsing-context tabs/iframes —
    // it does NOT reach windows opened via `window.open()`. localStorage DOES
    // fire a 'storage' event in every other same-origin window. We write here
    // and the customer screen listens (see customer_screen.dart).
    //
    // BroadcastChannel is kept as a best-effort secondary path for same-tab
    // listeners that legitimately exist.
    if (kIsWeb) {
      try {
        html.window.localStorage['pos_mirror_state'] = encoded;
        // Bump a counter to guarantee `storage` event fires even if encoded
        // payload happens to be byte-identical to the previous write.
        html.window.localStorage['pos_mirror_seq'] = DateTime.now()
            .microsecondsSinceEpoch
            .toString();
      } catch (_) {}
      try {
        final bc = html.BroadcastChannel('pos_mirror');
        bc.postMessage(encoded);
        bc.close();
      } catch (_) {}
    }
  }

  void dispose() {
    _disposed = true;
    if (_current == this) _current = null;
    _debounceTimer?.cancel();
    _reconnectTimer?.cancel();
    _lastActionTimer?.cancel();
    _billProvider?.removeListener(_onBillChanged);
    _channel?.sink.close();
    _channel = null;
    _billProvider = null;
  }
}

/// Builds the WebSocket URL for the POS mirror broadcaster.
/// Uses ws:// for http:// base URLs (dev), wss:// for https:// (prod).
///
/// บน Flutter Web ใช้ same-origin (Uri.base) — Go backend serve ทั้ง Web และ
/// WebSocket จาก host เดียวกัน (เช่น Windows POS: http://127.0.0.1:8080)
/// บน desktop/mobile ใช้ค่า hardcoded เดิม
String buildPosMirrorWsUrl(String token) {
  String baseUrl;
  if (kIsWeb) {
    final origin = Uri.base;
    baseUrl = '${origin.scheme}://${origin.authority}';
  } else {
    baseUrl = 'http://localhost:8080';
  }
  final wsBase = baseUrl
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');
  return '$wsBase/ws/pos-mirror?token=$token';
}

String buildCustomerDisplayWsUrl() {
  String baseUrl;
  if (kIsWeb) {
    final origin = Uri.base;
    baseUrl = '${origin.scheme}://${origin.authority}';
  } else {
    baseUrl = 'http://localhost:8080';
  }
  final wsBase = baseUrl
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');
  final query = Uri(
    queryParameters: {
      'branchId': ApiService.defaultBranchId,
      'posId': ApiService.defaultPosId,
      'posSecret': ApiService.posSecret,
    },
  ).query;
  return '$wsBase/ws/customer-display?$query';
}
