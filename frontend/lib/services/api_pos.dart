import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class ApiPosService {
  // ตรวจสอบว่าแอปกำลังรันอยู่ในโหมด Release (Production) หรือไม่
  static const bool _isProduction = bool.fromEnvironment('dart.vm.product');
  // บน Flutter Web ใช้ relative URL (same-origin) ให้เรียก API ผ่าน host เดียวกับหน้าเว็บ
  static const String baseUrl = kIsWeb
      ? ''
      : (_isProduction
            ? 'http://54.169.213.40:8080'
            : 'http://localhost:8080');
      
  // Helper: ดึง List<Map> จาก response ที่อาจเป็นหลายรูปแบบ
  static List<Map<String, dynamic>> _extractListFromResponse(
    dynamic decoded,
    String endpointName,
  ) {
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }

    if (decoded is Map<String, dynamic>) {
      // ลองดู key มาตรฐานก่อน
      final listKeys = ['items', 'data', 'users', 'parts', 'results'];
      for (final key in listKeys) {
        if (decoded[key] is List) {
          return (decoded[key] as List)
              .whereType<Map<String, dynamic>>()
              .toList();
        }
      }

      // ถ้าไม่เจอ ลองหา value แรกที่เป็น List
      final firstListValue = decoded.values.firstWhere(
        (v) => v is List,
        orElse: () => null,
      );

      if (firstListValue is List) {
        return firstListValue.whereType<Map<String, dynamic>>().toList();
      }
    }

    throw Exception('Unexpected $endpointName response format: $decoded');
  }

  // GET /pos - ดึงรายการอุปกรณ์ POS
  static Future<List<Map<String, dynamic>>> getPosDevices({
    required String token,
    int limit = 50,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/pos').replace(
      queryParameters: {'limit': '$limit', 'offset': '$offset'},
    );
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load POS devices: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    return _extractListFromResponse(decoded, '/pos');
  }
}