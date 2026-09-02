import 'dart:convert';

/// A request the backend refused.
///
/// Every API call used to fail with `Exception('Failed to X: 400 {"error":…}')`
/// and most screens print the exception straight into a red bar, so cashiers
/// were reading Go struct-tag noise. Keeping the pieces apart lets the text on
/// screen be a Thai sentence while the raw body stays available for logs and
/// for the handful of places that branch on the machine-readable reason.
class ApiException implements Exception {
  ApiException({
    required this.action,
    required this.statusCode,
    required this.body,
  });

  /// What the call was trying to do, in English, for logs only.
  final String action;

  final int statusCode;

  /// The response body verbatim.
  final String body;

  Map<String, dynamic>? get _payload {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// The backend's machine-readable reason, e.g. `not_enough_inventory`.
  String? get code {
    final value = _payload?['error'];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// The backend's own explanation. Often already Thai, in which case it is
  /// better than anything this file could invent.
  String? get serverMessage {
    final value = _payload?['message'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  @override
  String toString() => describeApiError(
    code: code,
    serverMessage: serverMessage,
    statusCode: statusCode,
    payload: _payload,
  );

  /// The original text, for `debugPrint` and bug reports.
  String get debugString => '$action: $statusCode $body';
}

/// Pulls the reason code out of anything that might be an API failure.
String? apiErrorCode(Object? error) {
  if (error is ApiException) return error.code;
  if (error == null) return null;
  final match = RegExp(
    r'"error"\s*:\s*"([a-z0-9_]+)"',
  ).firstMatch(error.toString());
  return match?.group(1);
}

/// True when [error] is the backend refusing for [code].
bool isApiErrorCode(Object? error, String code) => apiErrorCode(error) == code;

final RegExp _thaiScript = RegExp(r'[฀-๿]');

/// Nouns behind the `<thing>_not_found` / `missing_<thing>` families, so a code
/// nobody has spelled out by hand still reads as Thai.
const Map<String, String> _entityNames = {
  'address': 'ที่เก็บสินค้า',
  'barcode': 'บาร์โค้ด',
  'bill': 'บิล',
  'branch': 'สาขา',
  'branch_id': 'สาขา',
  'cash_reconciliation': 'การกระทบยอดเงินสด',
  'code': 'รหัส',
  'company': 'ข้อมูลบริษัท',
  'daily_close': 'การปิดยอดประจำวัน',
  'date': 'วันที่',
  'discount': 'ส่วนลด',
  'file': 'ไฟล์',
  'item': 'รายการสินค้า',
  'items': 'รายการสินค้า',
  'member': 'สมาชิก',
  'member_id': 'สมาชิก',
  'part': 'สินค้า',
  'pos': 'เครื่อง POS',
  'pos_id': 'เครื่อง POS',
  'promotion': 'โปรโมชั่น',
  'promotion_code': 'รหัสโปรโมชั่น',
  'purchase_order': 'ใบสั่งซื้อ',
  'return_note': 'ใบคืนสินค้า',
  'role': 'บทบาทผู้ใช้',
  'stock_count': 'ใบนับสต๊อก',
  'transfer': 'ใบเบิก',
  'user': 'ผู้ใช้',
  'user_branch': 'สิทธิ์สาขาของผู้ใช้',
  'user_id': 'ผู้ใช้',
};

/// Reasons worth spelling out because a cashier meets them mid-sale and the
/// backend has no Thai text of its own for them.
const Map<String, String> _codeMessages = {
  'access_denied': 'ไม่มีสิทธิ์ทำรายการนี้',
  'admin_only': 'เมนูนี้สำหรับผู้ดูแลระบบเท่านั้น',
  'barcode_exists': 'บาร์โค้ดนี้ถูกใช้กับสินค้าอื่นแล้ว',
  'bill_access_denied': 'บิลนี้ไม่ได้อยู่ในสาขา/เครื่อง POS ที่ใช้อยู่',
  'bill_not_completed': 'บิลนี้ยังไม่ได้ชำระเงิน',
  'cannot_delete_completed_bill':
      'บิลที่ชำระเงินแล้วลบไม่ได้ ถ้าต้องการยกเลิกให้ใช้ปุ่มยกเลิกบิล',
  'cannot_delete_superuser': 'ผู้ใช้ระดับ superuser ลบไม่ได้',
  'cash_below_total': 'เงินที่รับมาน้อยกว่ายอดที่ต้องชำระ',
  'cash_drawer_disabled': 'เครื่องนี้ยังไม่ได้เปิดใช้งานลิ้นชักเก็บเงิน',
  'credit_term_requires_positive_total':
      'บิลเครดิตต้องมียอดมากกว่า 0 บาท',
  'cross_branch_access_denied': 'ข้อมูลนี้เป็นของสาขาอื่น',
  'duplicate_barcode': 'บาร์โค้ดนี้ซ้ำกับสินค้าอื่น',
  'duplicate_part_code': 'รหัสสินค้านี้มีอยู่แล้ว',
  'empty_bill': 'บิลนี้ยังไม่มีสินค้า',
  'forbidden': 'ไม่มีสิทธิ์ทำรายการนี้',
  'global_scope_forbidden': 'บัญชีนี้ดูข้อมูลข้ามสาขาไม่ได้',
  'invalid_address_code': 'สินค้านี้ไม่มีสต๊อกในคลังประจำ POS',
  'invalid_credentials': 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง',
  'invalid_request': 'ข้อมูลที่ส่งไปไม่ครบหรือไม่ถูกต้อง',
  'invalid_line_total': 'ราคาติดลบไม่ได้ ถ้าต้องการแถมสินค้าให้ใส่ราคา 0',
  'item_not_found': 'ไม่พบรายการสินค้านี้ในบิล',
  'member_not_found': 'ไม่พบสมาชิกที่ใช้เบอร์นี้ — กรุณาสมัครสมาชิกก่อน',
  'no_vehicle_stock': 'สินค้านี้ไม่มีสต๊อกในคลังประจำ POS',
  'part_archived':
      'สินค้านี้ถูกปิดใช้งานแล้ว — ป้ายบาร์โค้ดเป็นของเก่า กรุณาค้นหาด้วยชื่อสินค้าแทน',
  'part_not_found': 'ไม่พบสินค้านี้ในระบบ',
  'pos_has_no_vehicle_stock': 'เครื่อง POS นี้ยังไม่มีสต๊อกในคลังประจำเครื่อง',
  'pos_store_not_configured': 'POS นี้ยังไม่ได้ตั้งค่าคลังประจำเครื่อง',
  'printer_disabled': 'เครื่องนี้ยังไม่ได้เปิดใช้งานเครื่องพิมพ์ใบเสร็จ',
  'printer_not_configured': 'ยังไม่ได้ตั้งค่าเครื่องพิมพ์ใบเสร็จ',
  'failed_to_print': 'พิมพ์ใบเสร็จไม่สำเร็จ ตรวจสอบสายและกระดาษของเครื่องพิมพ์',
  'failed_to_open_drawer': 'เปิดลิ้นชักเก็บเงินไม่สำเร็จ',
  'scope_access_denied': 'บัญชีนี้ดูข้อมูลในขอบเขตที่ขอไม่ได้',
  'session_not_allow':
      'เครื่องนี้ยังไม่ได้ผูกสาขา/เครื่อง POS กรุณาเข้าสู่ระบบใหม่',
  'unauthorized': 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่',
  'unreadable_file': 'อ่านไฟล์ไม่ได้ กรุณาตรวจสอบว่าเป็นไฟล์ Excel (.xlsx)',
  'user_not_visible': 'บัญชีนี้ไม่อยู่ในขอบเขตที่คุณดูแล',
};

/// Turns a backend refusal into one Thai sentence a cashier can act on.
///
/// The backend's own `message` wins whenever it is already Thai — that keeps
/// the wording in one place instead of forking it per screen.
String describeApiError({
  String? code,
  String? serverMessage,
  int? statusCode,
  Map<String, dynamic>? payload,
}) {
  if (serverMessage != null && _thaiScript.hasMatch(serverMessage)) {
    return serverMessage;
  }

  if (code != null) {
    if (code == 'not_enough_inventory') {
      // The number on the vehicle is the answer the cashier needs; a bare
      // "สต๊อกไม่พอ" only starts another question.
      final requested = payload?['requestedQty'];
      final available = payload?['availableQty'];
      if (requested is num && available is num) {
        return 'สต๊อกไม่พอ ขอ $requested ชิ้น '
            'เหลือในคลังของ POS นี้ $available ชิ้น';
      }
      return 'สต๊อกในคลังประจำ POS ไม่พอ';
    }

    final known = _codeMessages[code];
    if (known != null) return known;

    if (code == 'invalid_bill_status') {
      final raw = serverMessage ?? '';
      if (raw.contains("'cancelled'")) {
        return 'บิลนี้ถูกยกเลิกไปแล้ว (อาจถูกยกเลิกจากหน้าจอหรือแท็บอื่น) '
            'กรุณากดขึ้นบิลใหม่แล้วสแกนสินค้าอีกครั้ง';
      }
      if (raw.contains("'completed'")) {
        return 'บิลนี้ถูกชำระเงินไปแล้ว (อาจชำระจากหน้าจอหรือแท็บอื่น) '
            'กรุณาตรวจในประวัติการขายก่อนเก็บเงินซ้ำ';
      }
      return 'บิลนี้ไม่อยู่ในสถานะที่แก้ไขหรือชำระเงินได้แล้ว กรุณาขึ้นบิลใหม่';
    }

    final byShape = _describeByShape(code);
    if (byShape != null) return byShape;
  }

  return _describeByStatus(statusCode);
}

/// Reads the shape of a code the table above does not list. The backend names
/// them consistently, so `promotion_not_found` and `missing_count_id` can be
/// answered without adding every one by hand.
String? _describeByShape(String code) {
  if (code.startsWith('failed_to_')) {
    return 'เซิร์ฟเวอร์ทำรายการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }
  if (code.endsWith('_access_denied')) {
    final noun = _entityNames[code.substring(0, code.length - 14)];
    return noun == null ? 'ไม่มีสิทธิ์เข้าถึงข้อมูลนี้' : 'ไม่มีสิทธิ์เข้าถึง$noun';
  }
  if (code.endsWith('_not_found')) {
    final noun = _entityNames[code.substring(0, code.length - 10)];
    return noun == null ? 'ไม่พบข้อมูลที่ต้องการ' : 'ไม่พบ$noun';
  }
  if (code.startsWith('missing_')) {
    final noun = _entityNames[code.substring(8)];
    return noun == null ? 'ข้อมูลที่ส่งไปไม่ครบ' : 'ข้อมูลไม่ครบ ต้องระบุ$noun';
  }
  if (code.startsWith('duplicate_')) {
    final noun = _entityNames[code.substring(10)];
    return noun == null ? 'ข้อมูลนี้ซ้ำกับที่มีอยู่แล้ว' : '$nounนี้ซ้ำกับที่มีอยู่แล้ว';
  }
  if (code.startsWith('invalid_')) {
    final noun = _entityNames[code.substring(8)];
    return noun == null ? 'ข้อมูลที่กรอกไม่ถูกต้อง' : 'ข้อมูล$nounไม่ถูกต้อง';
  }
  if (code.startsWith('cannot_') || code.startsWith('conflicting')) {
    return 'ทำรายการนี้ไม่ได้ในสถานะปัจจุบัน';
  }
  return null;
}

String _describeByStatus(int? statusCode) {
  switch (statusCode) {
    case 400:
      return 'ข้อมูลที่ส่งไปไม่ถูกต้อง';
    case 401:
      return 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
    case 403:
      return 'ไม่มีสิทธิ์ทำรายการนี้';
    case 404:
      return 'ไม่พบข้อมูลที่ต้องการ';
    case 409:
      return 'ข้อมูลถูกแก้ไขจากที่อื่นแล้ว กรุณาโหลดใหม่';
    case 413:
      return 'ไฟล์ใหญ่เกินกว่าที่ระบบรับได้';
    case 429:
      return 'ส่งคำขอถี่เกินไป กรุณารอสักครู่';
    case 503:
      return 'ระบบไม่พร้อมให้บริการชั่วคราว กรุณาลองใหม่';
  }
  if (statusCode != null && statusCode >= 500) {
    return 'เซิร์ฟเวอร์ขัดข้อง (HTTP $statusCode) กรุณาลองใหม่อีกครั้ง';
  }
  if (statusCode != null) {
    return 'ทำรายการไม่สำเร็จ (HTTP $statusCode)';
  }
  return 'ทำรายการไม่สำเร็จ';
}
