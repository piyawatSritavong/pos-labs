import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:frontend/services/api_exception.dart';

void main() {
  group('ApiException.fromResponse', () {
    test('translates invalid credentials', () {
      final exception = ApiException.fromResponse(
        http.Response('{"error":"invalid_credentials"}', 401),
      );

      expect(exception.code, 'invalid_credentials');
      expect(exception.statusCode, 401);
      expect(exception.message, 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง');
    });

    test('translates duplicate barcode', () {
      final exception = ApiException.fromResponse(
        http.Response('{"error":"barcode_already_exists"}', 409),
      );

      expect(exception.message, 'Barcode นี้ถูกใช้งานกับสินค้าอื่นแล้ว');
    });

    test('translates missing stock-store configuration', () {
      final response = http.Response(
        '{"error":"stock_store_not_configured"}',
        409,
      );

      final error = ApiException.fromResponse(response);

      expect(error.message, 'ยังไม่ได้กำหนดคลังสินค้าสำหรับสาขา');
    });

    test('does not expose an unknown raw server message', () {
      final exception = ApiException.fromResponse(
        http.Response(
          '{"error":"database_failure","message":"SQLSTATE 42P01"}',
          400,
        ),
        fallback: 'บันทึกข้อมูลไม่สำเร็จ',
      );

      expect(exception.message, 'บันทึกข้อมูลไม่สำเร็จ');
      expect(exception.message, isNot(contains('SQLSTATE')));
    });

    test('uses a stable Thai message for server failures', () {
      final exception = ApiException.fromResponse(
        http.Response('upstream exploded', 503),
      );

      expect(exception.message, 'ระบบขัดข้องชั่วคราว กรุณาลองใหม่อีกครั้ง');
    });
  });
}
