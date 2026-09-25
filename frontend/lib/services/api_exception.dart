import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException({required this.message, this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  factory ApiException.fromResponse(
    http.Response response, {
    String fallback = 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง',
  }) {
    String? code;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        code = decoded['error']?.toString();
      }
    } catch (_) {
      // Use a safe fallback instead of exposing a raw response.
    }
    return ApiException(
      message: _messageFor(code, response.statusCode, fallback),
      code: code,
      statusCode: response.statusCode,
    );
  }

  static String _messageFor(String? code, int status, String fallback) {
    switch (code) {
      case 'invalid_credentials':
        return 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง';
      case 'login_already_pending':
        return 'มีคำขอเข้าสู่ระบบของบัญชีนี้รอการยืนยันอยู่แล้ว';
      case 'barcode_already_exists':
        return 'Barcode นี้ถูกใช้งานกับสินค้าอื่นแล้ว';
      case 'stock_store_not_configured':
        return 'ยังไม่ได้กำหนดคลังสินค้าสำหรับสาขา';
      case 'invalid_address_code':
      case 'no_vehicle_stock':
      case 'not_enough_inventory':
        return 'สินค้านี้ไม่มีสต็อกที่พร้อมขาย';
      case 'invalid_bill_status':
        return 'บิลเดิมถูกปิดแล้ว กรุณาเริ่มบิลใหม่';
      case 'part_not_found':
        return 'ไม่พบสินค้านี้ในสาขา';
      case 'printer_disabled':
      case 'printer_not_configured':
        return 'ระบบนี้ไม่ได้เปิดใช้งานเครื่องพิมพ์';
      case 'failed_to_print':
        return 'พิมพ์ใบเสร็จไม่สำเร็จ';
      case 'forbidden':
      case 'access_denied':
        return 'คุณไม่มีสิทธิ์ดำเนินการนี้';
    }
    if (status >= 500) return 'ระบบขัดข้องชั่วคราว กรุณาลองใหม่อีกครั้ง';
    // Never expose arbitrary backend response text to users. Known codes are
    // translated above; everything else uses the caller's safe Thai fallback.
    return fallback;
  }

  @override
  String toString() => message;
}

String? apiErrorCode(Object error) {
  if (error is ApiException) return error.code;
  return null;
}

bool isReceiptPrinterUnavailable(Object error) {
  final code = apiErrorCode(error);
  return code == 'printer_disabled' || code == 'printer_not_configured';
}

bool isReceiptPrinterError(Object error) {
  final code = apiErrorCode(error);
  if (code == 'printer_disabled' ||
      code == 'printer_not_configured' ||
      code == 'failed_to_print') {
    return true;
  }
  final raw = error.toString();
  return raw.contains('RECEIPT_PRINTER') ||
      raw.contains('พิมพ์ใบเสร็จไม่สำเร็จ') ||
      raw.contains('พิมพ์ใบคืนสินค้าไม่สำเร็จ');
}
