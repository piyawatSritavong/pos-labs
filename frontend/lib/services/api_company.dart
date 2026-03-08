import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiCompanyService {
  static const String baseUrl = 'http://localhost:8080';

  // Helper: ดึง Map<String,dynamic> จาก response ที่อาจเป็นหลายรูปแบบ
  static Map<String, dynamic> _extractObjectFromResponse(
    dynamic decoded,
    String endpointName,
  ) {
    if (decoded is Map<String, dynamic>) {
      // ดู field ที่น่าจะห่อ object อยู่
      final objectKeys = ['data', 'bill', 'part', 'result'];
      for (final key in objectKeys) {
        if (decoded[key] is Map<String, dynamic>) {
          return decoded[key] as Map<String, dynamic>;
        }
      }
      // ถ้าไม่มี field พิเศษ ให้คืนทั้ง map เลย
      return decoded;
    }

    if (decoded is List) {
      // ถ้า backend ดันส่งมาเป็น List ให้หยิบตัวแรก
      final first = decoded.firstWhere(
        (e) => e is Map<String, dynamic>,
        orElse: () => null,
      );
      if (first is Map<String, dynamic>) {
        return first;
      }
    }

    throw Exception('Unexpected $endpointName response format: $decoded');
  }

  // GET /company - ดึงข้อมูล company
  static Future<Map<String, dynamic>> getCompany({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/company');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load company: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/company');
  }

  // PUT /company - อัพเดทข้อมูล company
  static Future<Map<String, dynamic>> updateCompany({
    required String token,
    required String companyName,
    required String companyNameTh,
    required String companyAddress,
    required String companyAddressTh,
    required String phone,
    required String email,
    required String website,
    String? logoUrl,
    required double taxRate,
    required String taxType,
  }) async {
    final uri = Uri.parse('$baseUrl/company');
    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'companyName': companyName,
        'companyNameTh': companyNameTh,
        'companyAddress': companyAddress,
        'companyAddressTh': companyAddressTh,
        'phone': phone,
        'email': email,
        'website': website,
        'logoUrl': logoUrl ?? '',
        'taxRate': taxRate,
        'taxType': taxType,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update company: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    return _extractObjectFromResponse(decoded, '/company');
  }
}